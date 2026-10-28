import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { DownloadTaskRecord } from '../model/DownloadTypes';
import { ListDataSource } from '../ui/ListDataSource';
import { viewError } from './ViewOperation';
import { picker } from '@kit.CoreFileKit';
import { OfflineExportService } from '../business/OfflineExportService';
import { CancelScope } from '../model/CancelScope';

@Observed
export class DownloadsVM {
  status: string = '正在恢复任务…';
  busy: boolean = false;
  count: number = 0;
  background: string = '';
  readonly data: ListDataSource<DownloadTaskRecord> = new ListDataSource();
  private app?: AppContainer;
  private timer: number = -1;
  private closed: boolean = true;
  private loading: boolean = false;
  private context?: common.UIAbilityContext;
  private exportScope?: CancelScope;
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.closed = false; this.app = new AppContainer(context); this.context = context;
    try { await this.app.downloads.start(); this.app.downloads.setForeground(true); this.status = '任务恢复完成'; await this.refresh(); }
    catch (error) { this.status = viewError(error as Error); }
    if (!this.closed) { this.timer = setInterval(() => this.refresh(), 700); }
  }
  async refresh(): Promise<void> {
    if (!this.app || this.closed || this.loading) { return; } this.loading = true;
    try { const tasks = await this.app.downloadRecords.list(); if (!this.closed) { this.data.replace(tasks); this.count = tasks.length; this.background = this.app.downloads.backgroundStatus(); } }
    catch (error) { if (!this.closed) { this.status = viewError(error as Error); } }
    finally { this.loading = false; }
  }
  label(task: DownloadTaskRecord): string {
    const state = task.state === 'running' && task.desiredState !== 'run' ? (task.desiredState === 'paused' ? '正在暂停' : '正在取消') :
      task.state === 'running' ? '下载中' : task.state === 'queued' ? '排队中' : task.state === 'completed' ? '完整离线' : task.state === 'paused' ? '已暂停' : task.state === 'cancelled' ? '已取消' : '失败';
    return state + ' · ' + task.completed.toString() + ' / ' + (task.total || '?').toString() + (task.errorCode ? ' · ' + task.errorCode : '');
  }
  async action(task: DownloadTaskRecord, action: string): Promise<void> {
    if (!this.app || this.busy) { return; } this.busy = true;
    try {
      if (task.sourceId === 'org.hsmihon.local' && action !== 'delete') { this.status = '本地章节请重新导入修复'; return; }
      if (action === 'pause') { await this.app.downloads.pause(task.id); }
      else if (action === 'resume') { await this.app.downloads.resume(task.id); }
      else if (action === 'cancel') { await this.app.downloads.cancel(task.id); }
      else if (action === 'repair') { await this.app.downloads.repair(task.id); }
      else if (action === 'up' || action === 'down') { await this.app.downloads.move(task.id,action === 'up' ? -1 : 1); }
      else if (action === 'delete') { await this.app.downloads.removeOffline(task.id); }
      if (!this.closed) { this.status = '操作已保存'; await this.refresh(); }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error); } }
    finally { this.busy = false; }
  }
  async export(task: DownloadTaskRecord): Promise<void> {
    if (!this.context || this.busy || this.closed) { return; } this.busy = true; const scope = new CancelScope(); this.exportScope = scope;
    try {
      const options = new picker.DocumentSaveOptions(); options.newFileNames = [(task.mangaTitle + '-' + task.chapterTitle).replace(/[\\/:*?"<>|\u0000-\u001f]/g,'_').slice(0,100) + '.cbz'];
      const targets = await new picker.DocumentViewPicker(this.context).save(options); if (!targets.length || this.closed) { return; }
      await new OfflineExportService(this.context).export(task.id,targets[0],{ callId: 'cbz-export',deadlineMs: Date.now() + 900000,cancel: scope,ruleRevision: 1 },(done: number,total: number) => { if (!this.closed) { this.status = '正在导出CBZ ' + done.toString() + ' / ' + total.toString(); } });
      if (!this.closed) { this.status = 'CBZ已导出'; }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error); } } finally { this.busy = false; this.exportScope = undefined; }
  }
  cancelExport(): void { this.exportScope?.cancel(); }
  dispose(): void { this.closed = true; this.exportScope?.cancel(); if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; } }
}
