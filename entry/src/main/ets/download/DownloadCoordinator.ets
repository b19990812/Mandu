import { UpdateDownloads } from '../model/UpdateDownloads';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CancelScope } from '../model/CancelScope';
import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { DownloadTaskRecord, DownloadedPage } from '../model/DownloadTypes';
import { SourceState } from '../model/SourcePackageTypes';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceChanges } from '../source/SourceChanges';
import { checkCall, requireHttpSuccess } from '../source/SourceHttp';
import { CatalogRepository } from '../storage/CatalogRepository';
import { DownloadRepository } from '../storage/DownloadRepository';
import { FileStore } from '../storage/FileStore';
import { FilePins } from '../storage/FilePins';
import { fileDigest } from '../storage/FileDigest';
import { ManifestCodec } from '../parsing/ManifestCodec';
import { collectChapterManifest } from '../business/ChapterManifest';
import { FileVerifier, VerifiedImage } from './FileVerifier';
import { ReaderPreferencesRepository } from '../storage/ReaderPreferencesRepository';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { NetworkPolicy } from '../network/NetworkPolicy';
import { transferAsset } from '../image/AssetTransfer';
import { BackgroundTransferLease } from './BackgroundTransferLease';

interface ActiveDownload { sourceId: string; cancel: CancelScope; done: Promise<void>; }

// Durable chapter coordinator. Browser cache and offline files have separate roots.
// New pages are submitted in foreground; current transports follow their backend's lifecycle.
export class DownloadCoordinator implements UpdateDownloads {
  private static instances: Map<string, DownloadCoordinator> = new Map();
  readonly files: FileStore;
  private readonly registry: SourceRegistry;
  private readonly catalog: CatalogRepository;
  private readonly records: DownloadRepository;
  private readonly active: Map<string, ActiveDownload> = new Map();
  private starting?: Promise<void>;
  private pumping: boolean = false;
  private pumpAgain: boolean = false;
  private foreground: boolean = true;
  private reserved: number = 0;
  private readonly preferences: ReaderPreferencesRepository;
  private wakeTimer: number = -1;
  private readonly background: BackgroundTransferLease;
  private constructor(context: common.UIAbilityContext, registry: SourceRegistry, catalog: CatalogRepository, records: DownloadRepository) {
    this.files = new FileStore(context.filesDir, 'downloads'); this.registry = registry; this.catalog = catalog; this.records = records;
    this.preferences = new ReaderPreferencesRepository(ReaderDatabase.shared(context));
    this.background = new BackgroundTransferLease(context);
    SourceChanges.subscribeAll((state: SourceState) => {
      if (!state.enabled || state.removed) { this.pauseSource(state.id).catch(() => hilog.error(0x0001, 'HSReader', 'DOWNLOAD_SOURCE_PAUSE_FAILED')); }
    });
  }
  static shared(context: common.UIAbilityContext, registry: SourceRegistry, catalog: CatalogRepository, records: DownloadRepository): DownloadCoordinator {
    let instance = DownloadCoordinator.instances.get(context.filesDir);
    if (!instance) { instance = new DownloadCoordinator(context, registry, catalog, records); DownloadCoordinator.instances.set(context.filesDir, instance); }
    return instance;
  }
  async start(): Promise<void> {
    if (!this.starting) {
      this.starting = (async (): Promise<void> => {
        await this.records.recover(); const tasks = await this.records.list();
        for (let i = 0; i < tasks.length; i++) { if (tasks[i].state === 'cancelled') { await this.cleanFiles(tasks[i]); } }
      })();
    }
    try { await this.starting; } catch (error) { this.starting = undefined; throw error as Error; }
  }
  backgroundStatus(): string { return this.background.status(); }
  setForeground(value: boolean): void {
    this.foreground = value;
    if (this.wakeTimer >= 0) { clearInterval(this.wakeTimer); this.wakeTimer = -1; }
    if (value) { this.pump(); this.wakeTimer = setInterval(() => this.pump(), 5000); }
  }
  async enqueue(chapterId: string): Promise<void> {
    await this.start(); const chapter = await this.catalog.chapter(chapterId);
    if (!chapter) { throw new AppError(ErrorCode.NOT_FOUND, '章节不存在'); }
    const handle = await this.registry.open(chapter.ref.sourceId);
    await this.records.enqueue(chapter, handle.snapshotKey); await this.pump();
  }
  async pause(id: string): Promise<void> { await this.records.desired(id, 'paused'); const active = this.active.get(id); if (active) { active.cancel.cancel(); await active.done; } }
  async resume(id: string): Promise<void> { const active = this.active.get(id); if (active && active.cancel.cancelled) { await active.done; } await this.records.desired(id, 'run'); await this.pump(); }
  async move(id: string,direction: number): Promise<void> { await this.records.move(id,direction); await this.pump(); }
  async cancel(id: string): Promise<void> {
    const task = await this.records.task(id); if (!task || task.state === 'completed') { return; }
    await this.records.desired(id, 'cancelled');
    const active = this.active.get(id);
    if (active) { active.cancel.cancel(); await active.done; } else { await this.cleanFiles(task); await this.records.clear(id); }
  }
  async removeOffline(id: string): Promise<void> {
    if (this.active.has(id)) { throw new AppError(ErrorCode.CONFLICT, '请先暂停当前任务'); }
    const task = await this.records.task(id); if (!task) { return; }
    this.assertUnpinned(task); await this.records.clear(id); await this.cleanFiles(task);
  }
  async repair(id: string): Promise<void> {
    if (this.active.has(id)) { throw new AppError(ErrorCode.CONFLICT,'请先暂停当前任务再修复'); }
    const task = await this.records.task(id); if (!task) { return; }
    this.assertUnpinned(task); await this.records.repair(id); await this.pump();
  }
  private async pauseSource(sourceId: string): Promise<void> {
    const tasks = await this.records.list();
    for (let i = 0; i < tasks.length; i++) {
      if (tasks[i].sourceId === sourceId && ['queued','running'].indexOf(tasks[i].state) >= 0) { await this.pause(tasks[i].id); }
    }
  }
  private async pump(): Promise<void> {
    if (this.pumping) { this.pumpAgain = true; return; } if (!this.foreground) { return; } this.pumping = true;
    try {
      await this.start(); const tasks = (await this.records.list()).sort((a: DownloadTaskRecord, b: DownloadTaskRecord) => a.queueOrder - b.queueOrder || a.id.localeCompare(b.id));
      const prefs = await this.preferences.read();
      for (let i = 0; i < tasks.length; i++) {
        if (tasks[i].state === 'paused' && tasks[i].desiredState === 'run' && ['OFFLINE','WAITING_WIFI'].indexOf(tasks[i].errorCode) >= 0 && await NetworkPolicy.allowed(prefs.wifiOnly)) { await this.records.desired(tasks[i].id, 'run'); tasks[i].state = 'queued'; }
      }
      for (let i = 0; i < tasks.length && this.active.size < 2; i++) {
        const task = tasks[i]; if (task.state !== 'queued' || task.desiredState !== 'run' || this.active.has(task.id)) { continue; }
        let sourceCount = 0; this.active.forEach((active: ActiveDownload) => { if (active.sourceId === task.sourceId) { sourceCount++; } });
        if (sourceCount >= 2 || !await this.records.claim(task.id)) { continue; }
        const scope = new CancelScope(); const active: ActiveDownload = { sourceId: task.sourceId, cancel: scope, done: Promise.resolve() }; this.active.set(task.id, active);
        active.done = this.process(task.id, scope).catch((error: Error) => hilog.error(0x0001, 'HSReader', 'DOWNLOAD_UNHANDLED code=%{public}s', error instanceof AppError ? error.code : 'SYSTEM_ERROR'))
          .finally(() => { this.active.delete(task.id); this.pump(); });
      }
    } catch (error) { hilog.error(0x0001, 'HSReader', 'DOWNLOAD_QUEUE_FAILED code=%{public}s', error instanceof AppError ? error.code : 'SYSTEM_ERROR'); }
    finally { this.pumping = false; if (this.pumpAgain) { this.pumpAgain = false; this.pump(); } }
  }
  private context(scope: CancelScope, version: number): CallContext {
    return { callId: 'download', deadlineMs: Date.now() + 60000, cancel: scope, ruleRevision: version };
  }
  private async process(id: string, scope: CancelScope): Promise<void> {
    let task = await this.records.task(id); if (!task) { return; }
    try {
      const chapter = await this.catalog.chapter(task.chapterId); if (!chapter) { throw new AppError(ErrorCode.NOT_FOUND, '章节记录不存在'); }
      const handle = await this.registry.openPinned(task.sourceId, task.ruleKey); const source = handle.source;
      const network = async (): Promise<void> => {
        if (handle.rule.baseUrl === 'https://fixture.invalid/') { return; }
        const prefs = await this.preferences.read();
        if (!await NetworkPolicy.allowed(prefs.wifiOnly)) { throw new AppError(prefs.wifiOnly ? ErrorCode.WAITING_WIFI : ErrorCode.OFFLINE, prefs.wifiOnly ? '等待 Wi-Fi 网络' : '等待网络恢复'); }
      };
      await network();
      const metadata = this.context(scope, source.version); const manifest = await collectChapterManifest(source, chapter.ref, metadata);
      const raw = new ManifestCodec().encode(task.ruleKey, manifest.pages.map((page) => page.pageKey));
      checkCall(metadata); await this.records.manifest(id, raw);
      const saved = await this.records.pages(id); const existing: Map<string, DownloadedPage> = new Map(); saved.forEach((page: DownloadedPage) => existing.set(page.pageKey, page));
      for (let index = 0; index < manifest.pages.length; index++) {
        const ctx = this.context(scope, source.version); checkCall(ctx);
        const current = await this.records.task(id);
        if (!current || current.desiredState !== 'run') { throw new AppError(ErrorCode.CANCELLED, '下载已暂停或取消'); }
        if (!this.foreground) { await this.records.park(id); return; }
        await network();
        const page = manifest.pages[index]; const stored = existing.get(page.pageKey);
        if (stored) {
          let valid = false;
          try { valid = this.files.size(stored.fileKey) === stored.bytes && await fileDigest(this.files.localPath(stored.fileKey), ctx) === stored.digest; }
          catch (error) { checkCall(ctx); }
          if (valid) { continue; }
          if (FilePins.inUse(this.files.localPath(stored.fileKey))) { throw new AppError(ErrorCode.CONFLICT, '章节正在阅读，关闭后再修复'); }
          this.files.remove(stored.fileKey); await this.records.dropPage(id, stored.pageKey, false);
        }
        const key = id.replace(/-/g, '') + '_' + index.toString(); let verified: VerifiedImage | undefined = undefined;
        if (this.files.exists(key)) {
          try { verified = await new FileVerifier().verify(this.files.localPath(key), ctx); }
          catch (error) { checkCall(ctx); this.files.remove(key); }
        }
        if (!verified) {
          const free = await this.files.freeBytes();
          if (free - this.reserved < 209715200) { throw new AppError(ErrorCode.STORAGE_FULL, '剩余空间不足200MiB，请释放空间后重试'); }
          this.reserved += 33554432; const unpin = FilePins.pin(this.files.localPath(key));
          let releaseBackground: () => Promise<void> = async (): Promise<void> => {};
          try {
            if (handle.rule.baseUrl !== 'https://fixture.invalid/') { releaseBackground = await this.background.acquire(); }
            verified = await transferAsset(this.files,key,source,chapter.ref,page,handle.transport,ctx,33554432);
          } finally { try { await releaseBackground(); } finally { this.reserved -= 33554432; unpin(); } }
        }
        checkCall(ctx);
        await this.records.savePage({ taskId: id, pageKey: page.pageKey, ordinal: index, fileKey: key,
          bytes: verified!.bytes, width: verified!.width, height: verified!.height, digest: verified!.digest });
      }
      checkCall(this.context(scope, source.version)); await this.records.complete(id);
    } catch (error) {
      const code = error instanceof AppError ? error.code : ErrorCode.IO_ERROR;
      hilog.error(0x0001, 'HSReader', 'DOWNLOAD_FAILURE code=%{public}s', code);
      task = await this.records.task(id); if (!task) { return; }
      if (task.desiredState === 'cancelled') { await this.records.stop(id,ErrorCode.CANCELLED); await this.cleanFiles(task); await this.records.clear(id); }
      else if (!this.foreground && task.desiredState === 'run') { await this.records.park(id); }
      else { await this.records.stop(id, code); }
    }
  }
  private ownedKeys(task: DownloadTaskRecord): string[] {
    const prefix = task.id.replace(/-/g, '') + '_';
    return this.files.keys().filter((name: string) => name.startsWith(prefix) && /^[a-f0-9]{32}_[0-9]+(?:\.part)?$/.test(name));
  }
  private assertUnpinned(task: DownloadTaskRecord): void {
    if (this.ownedKeys(task).some((key: string) => FilePins.inUse(this.files.localPath(key.replace(/\.part$/, ''))))) { throw new AppError(ErrorCode.CONFLICT, '该章节正在阅读，请退出阅读器后再删除或修复'); }
  }
  private async cleanFiles(task: DownloadTaskRecord): Promise<void> {
    this.assertUnpinned(task); const keys = this.ownedKeys(task);
    keys.forEach((key: string) => this.files.remove(key.replace(/\.part$/, '')));
  }
}
