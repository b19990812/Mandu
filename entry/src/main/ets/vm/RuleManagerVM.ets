import { RuleSubscription } from '../source/RuleSubscriptionService';
import { CancelScope } from '../model/CancelScope';
import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { AppError } from '../model/ErrorTypes';
import { ManagedSource, RuleImportPreview } from '../source/SourceImportService';
import { RuleFilePicker } from '../storage/RuleFilePicker';

@Observed
export class RuleManagerVM {
  subscriptionUrl: string = '';
  expectedDigest: string = '';
  subscriptions: RuleSubscription[] = [];
  private subscriptionAddress: string = '';
  private fetchScope?: CancelScope;
  input: string = '';
  status: string = '选择本地JSON或载入演示规则，校验后预览并激活。';
  previewText: string = '';
  hasPreview: boolean = false;
  sources: ManagedSource[] = [];
  busy: boolean = false;
  demoRevision: number = 1;
  private preview?: RuleImportPreview;
  private app?: AppContainer;
  private picker?: RuleFilePicker;
  private disposed: boolean = false;

  initialize(context: common.UIAbilityContext): void {
    this.disposed = false;
    try { this.app = new AppContainer(context); this.picker = new RuleFilePicker(context); this.reload(); }
    catch (_) { this.status = '无法打开源规则存储，请检查存储状态'; }
  }
  change(value: string): void { this.input = value; this.subscriptionAddress = ''; this.preview = undefined; this.hasPreview = false; this.previewText = ''; }
  private async run(action: (app: AppContainer) => Promise<string>): Promise<void> {
    if (this.busy || !this.app || this.disposed) { return; }
    this.busy = true;
    try {
      const message = await action(this.app);
      if (!this.disposed) { this.sources = await this.app.imports.list(); this.subscriptions = await this.app.subscriptions.list(); this.demoRevision = this.app.demoSite.revision(); this.status = message; }
    } catch (error) {
      if (!this.disposed) { this.status = error instanceof AppError ? error.code + '：' + error.message : '操作失败，请重新读取后重试'; }
    } finally { if (!this.disposed) { this.busy = false; } }
  }
  reload(): void { this.run(async () => '源规则已重新读取'); }
  pick(): void {
    this.run(async () => {
      const text = await this.picker!.select(); if (text === undefined) { return '未选择文件，现有规则保持不变'; }
      this.change(text); return '文件已读取，请校验预览';
    });
  }
  sample(name: string): void {
    if (this.busy || !this.picker) { return; }
    try { this.change(this.picker.sample(name)); this.status = '已载入内置示例规则，请校验预览'; }
    catch (error) { this.status = error instanceof AppError ? error.message : '样本读取失败'; }
  }
  inspect(): void {
    this.hasPreview = false; this.preview = undefined;
    this.run(async (app: AppContainer) => {
      const preview = await app.imports.preview(this.input);
      if (this.disposed) { return ''; }
      this.showPreview(preview);
      return '校验通过；确认规则与版本后激活';
    });
  }
  private showPreview(preview: RuleImportPreview): void {
    this.preview = preview; this.hasPreview = true;
    this.previewText = preview.rule.name + '\nID：' + preview.rule.id + '\n版本：' + preview.oldVersion.toString() + ' → ' + preview.rule.sourceVersion.toString() +
        '\n根网址：' + preview.rule.baseUrl + '\n声明域名（不限制访问）：' + preview.rule.allowedHosts.join('、') +
        '\n新增声明：' + (preview.addedHosts.join('、') || '无') + '\n移除声明：' + (preview.removedHosts.join('、') || '无') +
        '\n能力：搜索、详情、目录、图像清单；匿名GET，不执行脚本' + (preview.unchanged ? '\n与当前版本相同' : '');
    this.previewText += '\nSHA256：' + preview.key;
  }
  fetchSubscription(item?: RuleSubscription): void {
    const address = item ? item.address : this.subscriptionUrl.trim();
    const expected = item ? item.sourceId : '';
    this.run(async (app: AppContainer) => {
      this.change(''); const scope = new CancelScope(); this.fetchScope = scope;
      const preview = await app.subscriptions.fetch(address,expected,item ? '' : this.expectedDigest.trim(),{ callId: 'subscription',deadlineMs: Date.now() + 60000,cancel: scope,ruleRevision: 1 });
      if (this.disposed) { return ''; }
      this.input = preview.raw; this.subscriptionAddress = address; this.showPreview(preview);
      return '订阅已下载；请核对规则、版本及摘要后激活';
    });
  }
  removeSubscription(item: RuleSubscription): void { this.run(async (app: AppContainer) => { await app.subscriptions.remove(item.sourceId); return '已取消订阅，已安装规则和阅读数据保留'; }); }
  activate(): void {
    const preview = this.preview; if (!preview) { return; }
    this.run(async (app: AppContainer) => {
      await app.imports.activate(preview); if (this.subscriptionAddress) { await app.subscriptions.remember(preview.rule.id,this.subscriptionAddress); this.subscriptionAddress = ''; } this.preview = undefined; this.hasPreview = false; this.previewText = '';
      return '规则已激活，后续请求使用新版本';
    });
  }
  toggle(item: ManagedSource): void { this.run(async (app: AppContainer) => { await app.imports.setEnabled(item.state.id, !item.state.enabled, item.state.revision); return '源状态已保存'; }); }
  rollback(item: ManagedSource): void { this.run(async (app: AppContainer) => { await app.imports.rollback(item.state.id, item.state.revision); return '已回滚到上一版本'; }); }
  remove(item: ManagedSource): void { this.run(async (app: AppContainer) => { await app.imports.remove(item.state.id, item.state.revision); return '源已移除；版本文件及阅读数据保留，重新导入可恢复'; }); }
  setDemoRevision(revision: number): void {
    this.run(async (app: AppContainer) => { await app.demoSite.setRevision(revision); return '自有演示网站已切换为结构v' + revision.toString() + '，真实网站不受影响'; });
  }
  dispose(): void { this.fetchScope?.cancel(); this.disposed = true; }
}
