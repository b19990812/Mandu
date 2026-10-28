import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { HistoryRecord } from '../model/LibraryTypes';
import { ListDataSource } from '../ui/ListDataSource';
import { ViewOperation, viewError } from './ViewOperation';
import { HistoryDeletePlan } from '../model/HistoryDeletion';

@Observed
export class HistoryVM {
  status: string = '';
  busy: boolean = false;
  count: number = 0;
  readonly data: ListDataSource<HistoryRecord> = new ListDataSource();
  private app?: AppContainer;
  private readonly operation: ViewOperation = new ViewOperation();
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.operation.reopen(); this.app = new AppContainer(context); await this.load();
  }
  private async load(): Promise<void> {
    if (!this.app) { return; } const ctx = this.operation.begin(30000); this.busy = true;
    try { const items = await this.app.progress.history(); if (this.operation.active(ctx)) { this.replace(items); } }
    catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  private replace(items: HistoryRecord[],prefix: string = ''): void {
    this.data.replace(items); this.count = items.length;
    this.status = prefix + (items.length ? '共 ' + items.length.toString() + ' 部漫画 · 每部显示最近阅读位置' : '还没有阅读记录');
  }
  async prepareRemoval(range: string,mangaId: string = ''): Promise<HistoryDeletePlan | undefined> {
    if (!this.app || this.busy) { return undefined; } const ctx = this.operation.begin(30000); this.busy = true;
    try {
      const plan = await this.app.progress.planHistoryDeletion(range,mangaId); if (!this.operation.active(ctx)) { return undefined; }
      if (!plan.targets.length) { this.status = '所选范围内没有可删除的历史'; return undefined; } return plan;
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } return undefined; }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  async applyRemoval(plan: HistoryDeletePlan): Promise<void> {
    if (!this.app || this.busy) { return; } const ctx = this.operation.begin(30000); this.busy = true;
    try {
      const count = await this.app.progress.deleteHistory(plan); const items = await this.app.progress.history();
      if (this.operation.active(ctx)) {
        const preserved = plan.targets.length - count;
        this.replace(items,'已删除 ' + count.toString() + ' 部漫画的历史' + (preserved ? '，' + preserved.toString() + ' 部已重新阅读或不再属于原记录' : '') + '；');
      }
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  async remove(mangaId: string): Promise<void> {
    const plan = await this.prepareRemoval('all',mangaId); if (plan) { await this.applyRemoval(plan); }
  }
  dispose(): void { this.operation.close(); }
}
