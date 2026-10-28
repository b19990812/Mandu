import { AppError, ErrorCode } from '../model/ErrorTypes';
import { ChapterRecord } from '../model/LibraryTypes';
import { CallContext } from '../model/RequestTypes';
import { ChapterPageSource, PageRef } from '../model/SourceTypes';
import { OfflineSnapshot } from '../model/DownloadTypes';
import { ReaderAssetCache } from '../image/ReaderAssetCache';
import { SourceRegistry } from '../source/SourceRegistry';
import { CatalogRepository } from '../storage/CatalogRepository';
import { ProgressRepository } from '../storage/ProgressRepository';
import { collectChapterManifest } from './ChapterManifest';
import { AssetProvider } from '../image/AssetProvider';
import { OfflineAssetProvider } from '../image/OfflineAssetProvider';
import { HybridAssetProvider } from '../image/HybridAssetProvider';
import { DownloadRepository } from '../storage/DownloadRepository';
import { FileStore } from '../storage/FileStore';
import { ManifestCodec } from '../parsing/ManifestCodec';

export interface BookSession {
  chapter: ChapterRecord; mangaTitle: string; source: ChapterPageSource | undefined; pages: PageRef[];
  cache: AssetProvider; startIndex: number; startRatio: number; positionChanged: boolean;
  previousId: string; nextId: string; offline: boolean;
  startCompleted: boolean;
  partialOffline: boolean;
}

export class ReaderService {
  private readonly registry: SourceRegistry;
  private readonly catalog: CatalogRepository;
  private readonly progress: ProgressRepository;
  private readonly cacheDir: string;
  private readonly downloads: DownloadRepository;
  private readonly files: FileStore;
  constructor(registry: SourceRegistry, catalog: CatalogRepository, progress: ProgressRepository, cacheDir: string, downloads: DownloadRepository, files: FileStore) {
    this.registry = registry; this.catalog = catalog; this.progress = progress; this.cacheDir = cacheDir;
    this.downloads = downloads; this.files = files;
  }
  async open(chapterId: string, ctx: CallContext, offlineOnly: boolean = false, skipRead: boolean = false): Promise<BookSession> {
    const chapter = await this.catalog.chapter(chapterId); if (!chapter) { throw new AppError(ErrorCode.NOT_FOUND, '章节记录不存在'); }
    const manga = await this.catalog.manga(chapter.mangaId); if (!manga) { throw new AppError(ErrorCode.NOT_FOUND, '漫画记录不存在'); }
    const snapshot = await this.downloads.snapshot(chapterId);
    let source: ChapterPageSource | undefined = undefined; let pages: PageRef[] = [];
    let cache: AssetProvider; let offline = false; let partial = false;
    if (snapshot && (snapshot.complete || offlineOnly)) {
      pages = this.offlinePages(snapshot); cache = new OfflineAssetProvider(this.files, snapshot.pages); offline = true; partial = !snapshot.complete;
    } else {
      if (chapter.ref.sourceId === 'org.hsmihon.local') { throw new AppError(ErrorCode.OFFLINE,'本地章节文件不完整，请从本地漫画入口重新导入'); }
      if (offlineOnly) { throw new AppError(ErrorCode.OFFLINE, '该章节暂无可读离线图像'); }
      try {
        const handle = await this.registry.open(chapter.ref.sourceId); source = handle.source;
        const call: CallContext = { callId: ctx.callId, deadlineMs: ctx.deadlineMs, cancel: ctx.cancel, ruleRevision: handle.source.version };
        const manifest = await collectChapterManifest(handle.source, chapter.ref, call); pages = manifest.pages;
        const online = new ReaderAssetCache(this.cacheDir, handle.transport, 134217728, 33554432,handle.snapshotKey);
        if (snapshot && snapshot.task.ruleKey === handle.snapshotKey && snapshot.task.manifest === new ManifestCodec().encode(handle.snapshotKey, pages.map((page: PageRef) => page.pageKey))) {
          cache = new HybridAssetProvider(new OfflineAssetProvider(this.files, snapshot.pages), online, snapshot.pages.map((page) => page.pageKey));
        } else { cache = online; }
      } catch (error) {
        if (ctx.cancel.cancelled || Date.now() >= ctx.deadlineMs || !snapshot) {
          if (error instanceof AppError) { throw error; } throw new AppError(ErrorCode.NETWORK_ERROR, '章节读取失败');
        }
        pages = this.offlinePages(snapshot); cache = new OfflineAssetProvider(this.files, snapshot.pages); source = undefined; offline = true; partial = true;
      }
    }
    const saved = await this.progress.chapter(chapterId); let startIndex = 0; let ratio = 0; let changed = false;
    if (saved && saved.chapterId === chapterId) {
      const matched = pages.findIndex((page: PageRef) => page.pageKey === saved.pageKey);
      startIndex = matched >= 0 ? matched : Math.min(saved.pageIndex, pages.length - 1); ratio = matched >= 0 ? saved.inPageRatio : 0; changed = matched < 0;
    }
    const chapters = await this.catalog.chapters(chapter.mangaId); const index = chapters.findIndex((item: ChapterRecord) => item.id === chapterId);
    const before = index < 0 ? undefined : chapters.slice(0,index).reverse().find((item: ChapterRecord) => (!skipRead || !item.read) && (!offlineOnly || item.downloaded));
    const after = index < 0 ? undefined : chapters.slice(index + 1).find((item: ChapterRecord) => (!skipRead || !item.read) && (!offlineOnly || item.downloaded));
    return { chapter: chapter, mangaTitle: manga.detail.title, source: source, pages: pages,
      cache: cache, startIndex: startIndex, startRatio: ratio, positionChanged: changed,
      previousId: before?.id || '',nextId: after?.id || '', offline: offline, partialOffline: partial,
      startCompleted: chapter.read };
  }
  private offlinePages(snapshot: OfflineSnapshot): PageRef[] {
    return snapshot.manifest.pageKeys.map((key: string, index: number): PageRef => {
      const saved = snapshot.pages.find((page) => page.pageKey === key);
      return { pageKey: key, ordinal: index, locator: saved ? saved.fileKey : '', width: saved?.width, height: saved?.height };
    });
  }
  async save(session: BookSession, index: number, ratio: number, completed: boolean = false): Promise<void> {
    if (!session.pages[index]) { return; }
    await this.progress.save({ mangaId: session.chapter.mangaId, chapterId: session.chapter.id, pageKey: session.pages[index].pageKey,
      pageIndex: index, inPageRatio: Math.max(0, Math.min(1, ratio)), completed: completed, updatedAt: Date.now() });
  }
}
