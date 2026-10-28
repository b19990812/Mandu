import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { CancelScope } from '../model/CancelScope';
import { AppError } from '../model/ErrorTypes';
import { COPY20_REPOSITORY, ExtensionEntry, additionalSources, AdditionalSource } from '../source/ExtensionCatalog';
import { RepositoryPreview, SavedRepository } from '../source/ExtensionRepositoryService';

@Observed
export class ExtensionManagerVM {
  address: string = COPY20_REPOSITORY;
  status: string = '输入扩展目录地址后预览。可关联本项目适配器；Android APK 不会被安装或执行。';
  busy: boolean = false; hasPreview: boolean = false;
  entries: ExtensionEntry[] = []; repositories: SavedRepository[] = [];
  additional: AdditionalSource[] = additionalSources();
  private preview?: RepositoryPreview; private app?: AppContainer; private scope?: CancelScope; private disposed: boolean = false;
  initialize(context: common.UIAbilityContext): void { this.disposed = false; this.app = new AppContainer(context); this.reload(); }
  dispose(): void { this.disposed = true; this.scope?.cancel(); }
  change(value: string): void { if (this.busy) { return; } this.address = value; this.preview = undefined; this.hasPreview = false; this.entries = []; }
  private async run(action: (app: AppContainer) => Promise<string>): Promise<void> {
    if (!this.app || this.busy || this.disposed) { return; } this.busy = true;
    try { const message = await action(this.app); if (!this.disposed) { this.repositories = await this.app.extensionRepositories.list(); this.status = message; } }
    catch (error) { if (!this.disposed) { this.status = error instanceof AppError ? error.code + '：' + error.message : '操作失败，请重试'; } }
    finally { if (!this.disposed) { this.busy = false; } }
  }
  reload(): void { this.run(async () => '已读取本地仓库目录；可检查更新或预览新仓库'); }
  fetch(address: string = this.address): void {
    this.preview = undefined; this.hasPreview = false; this.entries = [];
    this.run(async (app: AppContainer) => {
      this.scope = new CancelScope(); const preview = await app.extensionRepositories.fetch(address,{ callId: 'extension-preview',deadlineMs: Date.now() + 60000,cancel: this.scope,ruleRevision: 1 });
      if (!this.disposed) { this.address = preview.address; this.preview = preview; this.entries = preview.entries; this.hasPreview = true; }
      return '已读取 ' + preview.entries.length.toString() + ' 个源。确认保存目录后，可启用已有适配器；目录更新不自动变更网站或适配器代码。';
    });
  }
  save(): void { this.run(async (app: AppContainer) => { if (!this.preview) { return '请先预览'; } await app.extensionRepositories.save(this.preview); this.preview = undefined; this.hasPreview = false; return '仓库目录已保存'; }); }
  show(item: SavedRepository): void { if (this.busy) { return; } this.change(item.address); this.entries = item.entries; this.status = '显示本地目录；上游版本号与本项目原生适配器版本分别管理'; }
  remove(item: SavedRepository): void { this.run(async (app: AppContainer) => { await app.extensionRepositories.remove(item.key); this.entries = []; this.preview = undefined; this.hasPreview = false; return '已移除仓库目录；已启用源及书架数据保留'; }); }
  enable(item: ExtensionEntry): void {
    this.run(async (app: AppContainer) => {
      if (!item.nativeId || this.hasPreview || !this.repositories.some((repo: SavedRepository) => repo.address === this.address && repo.entries.some((entry: ExtensionEntry) => entry.pkg === item.pkg && entry.externalId === item.externalId && entry.nativeId === item.nativeId))) { return '请先保存支持的仓库目录'; }
      const entry = (await app.nativeSources.list()).find((source) => source.state.id === item.nativeId); if (!entry) { return '此源没有本项目实现'; }
      if (!entry.state.enabled) { await app.nativeSources.setEnabled(item.nativeId,true,entry.state.revision); }
      return '已启用 ' + item.name + '，返回浏览页即可使用。适配状态：' + item.status;
    });
  }
  enableAdditional(item: AdditionalSource): void {
    this.run(async (app: AppContainer) => {
      if (!item.nativeId || !additionalSources().some((known: AdditionalSource) => known.nativeId === item.nativeId && known.address === item.address)) { return '此网站尚无本项目适配器'; }
      const source = (await app.nativeSources.list()).find((entry) => entry.state.id === item.nativeId);
      if (!source) { return '此网站尚无本项目适配器'; }
      if (!source.state.enabled) { await app.nativeSources.setEnabled(item.nativeId,true,source.state.revision); }
      return '已启用 ' + item.name + '，返回浏览页即可使用。';
    });
  }
}
