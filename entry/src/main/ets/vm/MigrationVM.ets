import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { MigrationService, MigrationPreview } from '../business/MigrationService';
import { ViewOperation, viewError } from './ViewOperation';

@Observed
export class MigrationVM {
  status: string = '搜索并选择其他来源的同一作品，再核对章节匹配。';
  summary: string = ''; ready: boolean = false; busy: boolean = false;
  private app?: AppContainer; private source: string = ''; private preview?: MigrationPreview;
  private operation: ViewOperation = new ViewOperation();
  initialize(context: common.UIAbilityContext,id: string): void { this.app = new AppContainer(context); this.source = id; this.operation.reopen(); }
  async select(id: string): Promise<void> {
    if (!this.app || this.busy) { return; } this.busy = true; this.ready = false; const ctx = this.operation.begin(60000);
    try {
      await this.app.catalogService.refresh(id,ctx);
      const preview = await new MigrationService(this.app.catalog).preview(this.source,id);
      if (!this.operation.active(ctx)) { return; }
      this.preview = preview; this.summary = preview.sourceTitle + ' → ' + preview.targetTitle + '\n唯一同名章节匹配 ' + preview.matches.length.toString() + '，未匹配 ' + preview.unmatched.toString() + '\n' + preview.matches.map((item) => item.title).join('\n');
      this.ready = true; this.status = '复制收藏、分类和匹配章节的已读/书签；原作品与离线文件保留。页内位置不跨源复制。';
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  async apply(): Promise<void> {
    if (!this.app || !this.preview || this.busy) { return; } this.busy = true;
    try { await new MigrationService(this.app.catalog).apply(this.preview); this.ready = false; this.status = '迁移完成；目标已加入书架，原作品与离线内容保留'; }
    catch (error) { this.status = viewError(error as Error); } finally { this.busy = false; }
  }
  dispose(): void { this.operation.close(); }
}
