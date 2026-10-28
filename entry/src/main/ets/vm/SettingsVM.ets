import { AppTheme } from '../business/AppTheme';
import { DEFAULT_PREFETCH_PAGES } from '../model/ReaderPreferences';
import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { bundleManager } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { BrowserCache } from '../image/BrowserCache';
import { viewError } from './ViewOperation';
import { FileSink } from '../storage/FileStore';
import { BackupService } from '../business/BackupService';
import { ReaderDatabase } from '../storage/ReaderDatabase';

@Observed
export class SettingsVM {
  theme: string = 'system';
  async setTheme(value: string): Promise<void> { if (!this.context) { return; } try { await AppTheme.save(this.context,value); this.theme = value; } catch (error) { this.status = viewError(error as Error); } }
  mode: string = 'paged'; direction: string = 'ltr'; prefetch: boolean = true; prefetchPages: number = DEFAULT_PREFETCH_PAGES; wifiOnly: boolean = false; cacheMiB: number = 512;
  autoNext: boolean = true; preloadNext: boolean = true; skipRead: boolean = false; prefetchWifi: boolean = false;
  background: string = 'dark'; scale: string = 'auto'; tapZones: string = 'sides'; invertTap: boolean = false; incognito: boolean = false;
  backupPreview: string = '';
  backupReady: boolean = false;
  private backupText: string = '';
  status: string = '正在读取设置…'; version: string = ''; reclaimable: number = 0; busy: boolean = false;
  private app?: AppContainer; private cache?: BrowserCache; private context?: common.UIAbilityContext; private closed: boolean = true;
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.closed = false; this.context = context; this.app = new AppContainer(context); this.cache = new BrowserCache(context.cacheDir);
    try {
      this.theme = await AppTheme.read(context);
      const prefs = await this.app.preferences.read(); const size = await this.cache.reclaimable();
      if (!this.closed) { this.background = prefs.background; this.scale = prefs.scale; this.tapZones = prefs.tapZones; this.invertTap = prefs.invertTap; this.incognito = prefs.incognito; }
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      if (!this.closed) { this.mode = prefs.mode; this.direction = prefs.direction; this.prefetch = prefs.prefetch; this.prefetchPages = prefs.prefetchPages; this.wifiOnly = prefs.wifiOnly; this.cacheMiB = prefs.cacheMiB; this.autoNext = prefs.autoNext; this.preloadNext = prefs.preloadNext; this.skipRead = prefs.skipRead; this.prefetchWifi = prefs.prefetchWifi; this.reclaimable = size; this.version = info.versionName; this.status = '设置已读取'; }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error); } }
  }
  async save(): Promise<void> {
    if (!this.app || this.busy) { return; } this.busy = true;
    try { await this.app.preferences.save({ mode: this.mode,direction: this.direction,prefetch: this.prefetch,prefetchPages: this.prefetchPages,wifiOnly: this.wifiOnly,cacheMiB: this.cacheMiB,autoNext: this.autoNext,preloadNext: this.preloadNext,skipRead: this.skipRead,prefetchWifi: this.prefetchWifi,background: this.background,scale: this.scale,tapZones: this.tapZones,invertTap: this.invertTap,incognito: this.incognito }); BrowserCache.setBudget(this.cacheMiB); this.app.downloads.setForeground(true); if (!this.closed) { this.status = '默认设置已保存，下次打开章节生效'; } }
    catch (error) { if (!this.closed) { this.status = viewError(error as Error); } } finally { this.busy = false; }
  }
  async clean(): Promise<void> {
    if (!this.cache || this.busy) { return; } this.busy = true;
    try { const size = await this.cache.clean(); this.reclaimable = await this.cache.reclaimable(); if (!this.closed) { this.status = '已回收 ' + (size / 1048576).toFixed(2) + ' MiB，使用中的图像已跳过'; } }
    catch (error) { if (!this.closed) { this.status = viewError(error as Error); } } finally { this.busy = false; }
  }
  async exportDiagnostic(): Promise<void> {
    if (!this.context || !this.app || this.busy) { return; } this.busy = true;
    try {
      const tasks = await this.app.downloadRecords.list(); const sources = await this.app.listSources();
      const codes = tasks.map((task) => task.errorCode).filter((code: string) => code !== '');
      const text = '漫读诊断\n时间：' + new Date().toISOString() + '\n版本：' + this.version + '\n目标 API：26\n源数量：' + sources.length.toString() + '\n任务数量：' + tasks.length.toString() + '\n已完成章：' + tasks.filter((task) => task.state === 'completed').length.toString() + '\n任务错误码：' + codes.join(', ') + '\n可回收浏览缓存：' + this.reclaimable.toString() + ' bytes\n不含源网址、规则内容、漫画名称、Cookie或令牌。\n';
      const options = new picker.DocumentSaveOptions(); options.newFileNames = ['hs-mihon-diagnostic.txt'];
      const targets = await new picker.DocumentViewPicker(this.context).save(options); if (targets.length === 0) { return; }
      const file = fs.openSync(targets[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try { await new FileSink(file.fd).write(new util.TextEncoder().encodeInto(text).buffer as ArrayBuffer); fs.fsyncSync(file.fd); } finally { fs.closeSync(file); }
      if (!this.closed) { this.status = '已导出脱敏诊断文本'; }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error); } } finally { this.busy = false; }
  }
  async exportBackup(): Promise<void> {
    if (!this.context || this.busy) { return; } this.busy = true;
    try {
      const text = await new BackupService(ReaderDatabase.shared(this.context)).export();
      const options = new picker.DocumentSaveOptions(); options.newFileNames = ['hs-mihon-' + new Date().toISOString().slice(0,10) + '.hsmbackup'];
      const targets = await new picker.DocumentViewPicker(this.context).save(options); if (!targets.length) { return; }
      const file = fs.openSync(targets[0],fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try { await new FileSink(file.fd).write(new util.TextEncoder().encodeInto(text).buffer as ArrayBuffer); fs.fsyncSync(file.fd); } finally { fs.closeSync(file); }
      if (!this.closed) { this.status = '书架、目录、分类、逐章进度和阅读设置已备份'; }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error); } } finally { this.busy = false; }
  }
  async previewBackup(): Promise<void> {
    if (!this.context || this.busy) { return; } this.busy = true; this.backupReady = false; this.backupText = ''; this.backupPreview = '';
    try {
      const uris = await new picker.DocumentViewPicker(this.context).select({ maxSelectNumber: 1,fileSuffixFilters: ['漫读备份|.hsmbackup'] }); if (!uris.length) { return; }
      const file = fs.openSync(uris[0],fs.OpenMode.READ_ONLY); let text = '';
      try {
        const size = fs.statSync(file.fd).size; if (size < 1 || size > BackupService.MAX_BYTES) { throw new Error('备份大小超限'); }
        const bytes = new ArrayBuffer(size + 1); const count = fs.readSync(file.fd,bytes); if (count !== size) { throw new Error('备份文件读取期间改变'); }
        text = util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(new Uint8Array(bytes,0,count));
      } finally { fs.closeSync(file); }
      const summary = await new BackupService(ReaderDatabase.shared(this.context)).preview(text);
      if (!this.closed) { this.backupText = text; this.backupReady = true; this.backupPreview = summary.manga.toString() + ' 部漫画 · ' + summary.chapters.toString() + ' 章 · ' + summary.positions.toString() + ' 条章节进度 · ' + summary.categories.toString() + ' 个分类'; this.status = '备份校验通过，请确认合并恢复'; }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error); } } finally { this.busy = false; }
  }
  async restoreBackup(): Promise<void> {
    if (!this.context || this.busy || !this.backupReady) { return; } this.busy = true;
    try { await new BackupService(ReaderDatabase.shared(this.context)).restore(this.backupText); this.backupReady = false; this.backupText = ''; this.status = '已合并恢复，较新进度和已有设置保留'; }
    catch (error) { if (!this.closed) { this.status = viewError(error as Error); } } finally { this.busy = false; }
  }
  dispose(): void { this.closed = true; this.backupText = ''; this.backupReady = false; }
}
