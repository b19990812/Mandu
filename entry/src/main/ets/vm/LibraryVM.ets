import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { CategoryRecord, MangaRecord } from '../model/LibraryTypes';
import { ListDataSource } from '../ui/ListDataSource';
import { ViewOperation, viewError } from './ViewOperation';

@Observed
export class LibraryVM {
  categories: CategoryRecord[] = [];
  selectedCategory: string = '';
  categoryName: string = '';
  status: string = '';
  count: number = 0;
  busy: boolean = false;
  query: string = '';
  order: string = 'updated';
  filter: string = 'all';
  selected: string[] = [];
  batchCategory: string = '';
  private items: MangaRecord[] = [];
  readonly data: ListDataSource<MangaRecord> = new ListDataSource();
  private app?: AppContainer;
  private readonly operation: ViewOperation = new ViewOperation();
  initialize(context: common.UIAbilityContext): void { this.operation.reopen(); this.app = new AppContainer(context); this.load(); }
  async load(): Promise<void> {
    if (!this.app) { return; } const ctx = this.operation.begin(30000); this.busy = true;
    try {
      const categories = await this.app.library.categories();
      if (this.selectedCategory && !categories.some((item: CategoryRecord) => item.id === this.selectedCategory)) { this.selectedCategory = ''; }
      const manga = await this.app.catalog.library(this.selectedCategory);
      if (this.operation.active(ctx)) { this.categories = categories; this.items = manga; this.selected = this.selected.filter((id: string) => manga.some((item: MangaRecord) => item.id === id)); this.apply(); this.status = manga.length ? '书架共' + manga.length.toString() + '部' : '书架为空，从浏览页搜索后收藏漫画'; }
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  select(id: string): void { this.selectedCategory = id; this.load(); }
  search(value: string): void { this.query = value; this.apply(); }
  private filtered(): MangaRecord[] {
    const query = this.query.trim().toLowerCase();
    const items = this.items.filter((item: MangaRecord) => (!query || (item.detail.title + ' ' + item.detail.authors.join(' ')).toLowerCase().includes(query)) && (this.filter === 'all' || this.filter === 'unread' && (item.unreadCount || 0) > 0 || this.filter === 'offline' && (item.offlineCount || 0) > 0));
    return items.sort((a: MangaRecord,b: MangaRecord) => this.order === 'title' ? a.detail.title.localeCompare(b.detail.title) : this.order === 'unread' ? (b.unreadCount || 0) - (a.unreadCount || 0) || a.id.localeCompare(b.id) : this.order === 'read' ? (b.lastReadAt || 0) - (a.lastReadAt || 0) || a.id.localeCompare(b.id) : b.updatedAt - a.updatedAt || a.id.localeCompare(b.id));
  }
  apply(): void { const items = this.filtered(); this.data.replace(items); this.count = items.length; }
  toggle(id: string): void { this.selected = this.selected.indexOf(id) >= 0 ? this.selected.filter((value: string) => value !== id) : this.selected.concat([id]); }
  selectAll(): void { const ids = this.filtered().map((item: MangaRecord) => item.id); this.selected = ids.every((id: string) => this.selected.indexOf(id) >= 0) ? [] : ids; }
  async batch(action: string): Promise<void> {
    if (!this.app || this.busy || this.selected.length === 0) { return; } this.busy = true;
    try {
      if (action === 'remove') { await this.app.catalog.favorites(this.selected.slice(),false); }
      else { await this.app.library.assignMany(this.selected.slice(),this.batchCategory,action === 'assign'); }
      this.selected = []; await this.load(); this.status = action === 'remove' ? '已移出书架，进度和离线保留' : '批量分类已保存';
    } catch (error) { this.status = viewError(error as Error); this.busy = false; }
  }
  async categoryAction(action: string): Promise<void> {
    if (this.busy || !this.app) { return; } this.busy = true;
    try {
      if (action === 'add') { await this.app.library.addCategory(this.categoryName); }
      else if (action === 'rename' && this.selectedCategory) { await this.app.library.renameCategory(this.selectedCategory, this.categoryName); }
      else if (action === 'delete' && this.selectedCategory) { await this.app.library.deleteCategory(this.selectedCategory); this.selectedCategory = ''; }
      this.categoryName = ''; await this.load();
    } catch (error) { this.status = viewError(error as Error); this.busy = false; }
  }
  dispose(): void { this.operation.close(); }
}
