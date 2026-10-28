import { UpdateScheduler } from '../business/UpdateScheduler';
import { UpdatePolicy } from '../storage/UpdatePolicyRepository';
import { CategoryRecord } from '../model/LibraryTypes';
import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { ListDataSource } from '../ui/ListDataSource';
import { UpdateRepository, ChapterUpdate } from '../storage/UpdateRepository';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { ViewOperation, viewError } from './ViewOperation';

@Observed
export class UpdatesVM {
  policy: UpdatePolicy = new UpdatePolicy();
  categories: CategoryRecord[] = [];
  async loadPolicy(): Promise<void> { if (!this.app) { return; } try { this.policy = await this.app.updatePolicy.read(); this.categories = await this.app.library.categories(); } catch (error) { this.status = viewError(error as Error); } }
  async savePolicy(): Promise<void> { if (!this.app) { return; } try { await this.app.updatePolicy.save(this.policy); await UpdateScheduler.configure(this.policy); this.status = '更新策略已保存；后台检查由系统择机执行'; } catch (error) { this.status = viewError(error as Error); } }
  categoryOptions(): SelectOption[] { const options: SelectOption[] = [{ value: '全部分类' }]; return options.concat(this.categories.map((item: CategoryRecord): SelectOption => ({ value: item.name }))); }
  categoryIndex(): number { return this.categories.findIndex((item: CategoryRecord) => item.id === this.policy.category) + 1; }
  categoryName(): string { const item = this.categories.find((item: CategoryRecord) => item.id === this.policy.category); return this.policy.category ? (item ? item.name : '原分类已删除，请重新选择') : '全部分类'; }
  status: string = '更新记录只在完整目录刷新后登记'; busy: boolean = false;
  readonly data: ListDataSource<ChapterUpdate> = new ListDataSource();
  private app?: AppContainer; private records?: UpdateRepository; private operation: ViewOperation = new ViewOperation();
  initialize(context: common.UIAbilityContext): void { this.operation.reopen(); this.app = new AppContainer(context); this.records = new UpdateRepository(ReaderDatabase.shared(context)); this.load(); this.loadPolicy(); }
  async load(): Promise<void> { if (!this.records) { return; } try { this.data.replace(await this.records.list()); } catch (error) { this.status = viewError(error as Error); } }
  async refresh(): Promise<void> {
    if (!this.app || this.busy) { return; } const ctx = this.operation.begin(600000); this.busy = true;
    try {
      await this.app.libraryUpdates.run(ctx,false,(message: string) => { if (this.operation.active(ctx)) { this.status = message; } });
      if (this.operation.active(ctx)) { await this.load(); }
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }

  cancel(): void { this.operation.cancel(); this.busy = false; this.status = '已取消，已完成的目录和更新记录保留'; }
  dispose(): void { this.operation.close(); }
}
