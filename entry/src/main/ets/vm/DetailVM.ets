import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { CategoryRecord, ChapterRecord, MangaRecord, ProgressRecord } from '../model/LibraryTypes';
import { CallContext } from '../model/RequestTypes';
import { ListDataSource } from '../ui/ListDataSource';
import { ViewOperation, viewError } from './ViewOperation';

@Observed
export class DetailVM {
  title: string = '漫画详情';
  description: string = '';
  favorite: boolean = false;
  busy: boolean = false;
  status: string = '正在读取本地记录…';
  count: number = 0;
  categories: CategoryRecord[] = [];
  assigned: string[] = [];
  continueId: string = '';
  selected: string[] = [];
  reverse: boolean = false;
  filter: string = 'all';
  chapterQuery: string = '';
  visibleCount: number = 0;
  private chapters: ChapterRecord[] = [];
  cover: string = ''; sourceId: string = ''; remoteId: string = ''; authors: string = ''; tags: string = '';
  readonly data: ListDataSource<ChapterRecord> = new ListDataSource();
  private id: string = '';
  private app?: AppContainer;
  private readonly operation: ViewOperation = new ViewOperation();

  async initialize(context: common.UIAbilityContext, id: string): Promise<void> {
    this.operation.reopen(); this.app = new AppContainer(context); this.id = id; const ctx = this.operation.begin(60000); this.busy = true;
    try {
      await this.cached(ctx); if (!this.operation.active(ctx)) { return; }
      this.status = this.count ? '已读取本地目录，可刷新' : '正在读取完整目录…';
      if (this.count === 0) { await this.app.catalogService.refresh(id, ctx); if (this.operation.active(ctx)) { await this.cached(ctx); this.status = '完整目录已保存，共' + this.count.toString() + '章'; } }
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error) + '，已有目录保留'; } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  private async cached(ctx: CallContext): Promise<void> {
    if (!this.app) { return; }
    const manga = await this.app.catalog.manga(this.id); const chapters = await this.app.catalog.chapters(this.id);
    const categories = await this.app.library.categories(); const assigned = await this.app.library.categoryIds(this.id); const progress = await this.app.progress.get(this.id);
    if (!this.operation.active(ctx)) { return; }
    if (manga) { this.title = manga.detail.title; this.description = manga.detail.description; this.favorite = manga.favorite; this.cover = manga.detail.cover || ''; this.sourceId = manga.detail.ref.sourceId; this.remoteId = manga.detail.ref.remoteId; this.authors = manga.detail.authors.join(' / '); this.tags = manga.detail.tags.join(' · '); }
    this.chapters = chapters; this.applyFilter(); this.count = chapters.length; this.categories = categories; this.assigned = assigned;
    const unread = chapters.find((chapter: ChapterRecord) => !chapter.read);
    this.continueId = progress && !progress.completed ? progress.chapterId : unread ? unread.id : chapters.length ? chapters[0].id : '';
  }
  async refresh(): Promise<void> {
    if (this.busy || !this.app) { return; } const ctx = this.operation.begin(60000); this.busy = true; this.status = '正在完整刷新目录…';
    try { await this.app.catalogService.refresh(this.id, ctx); if (this.operation.active(ctx)) { await this.cached(ctx); this.status = this.sourceId === 'org.hsmihon.local' ? '本地目录已刷新；添加或替换章节请使用本地漫画入口' : '完整目录已保存，共' + this.count.toString() + '章'; } }
    catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error) + '，已有目录保留'; } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  async toggleFavorite(): Promise<void> {
    if (this.busy || !this.app) { return; }
    const ctx = this.operation.begin(30000); this.busy = true; const next = !this.favorite;
    try { await this.app.catalog.favorite(this.id, next); if (this.operation.active(ctx)) { this.favorite = next; this.status = next ? '已加入书架' : '已取消收藏，历史和离线文件保留'; } }
    catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  async assign(category: CategoryRecord): Promise<void> {
    if (this.busy || !this.app) { return; }
    const ctx = this.operation.begin(30000); this.busy = true;
    try { await this.app.library.assign(this.id, category.id, this.assigned.indexOf(category.id) < 0); const assigned = await this.app.library.categoryIds(this.id); if (this.operation.active(ctx)) { this.assigned = assigned; } }
    catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  cancel(): void { this.operation.cancel(); this.busy = false; this.status = '已取消刷新，旧目录保留'; }
  select(id: string): void { this.selected = this.selected.indexOf(id) >= 0 ? this.selected.filter((value: string) => value !== id) : this.selected.concat([id]); }
  all(): void { this.selected = this.selected.length === this.visibleCount ? [] : this.filtered().map((item: ChapterRecord) => item.id); }
  sort(): void { this.reverse = !this.reverse; this.applyFilter(); }
  filterChapters(value: string): void { this.filter = value; this.selected = []; this.applyFilter(); }
  searchChapters(value: string): void { this.chapterQuery = value; this.selected = []; this.applyFilter(); }
  private filtered(): ChapterRecord[] {
    const query = this.chapterQuery.trim().toLowerCase();
    const chapters = this.chapters.filter((chapter: ChapterRecord) => (!query || chapter.title.toLowerCase().includes(query)) &&
      (this.filter === 'all' || this.filter === 'unread' && !chapter.read || this.filter === 'read' && chapter.read || this.filter === 'bookmark' && chapter.bookmarked || this.filter === 'offline' && chapter.downloaded));
    return this.reverse ? chapters.reverse() : chapters;
  }
  private applyFilter(): void { const chapters = this.filtered(); this.visibleCount = chapters.length; this.data.replace(chapters); }
  async mark(read: boolean): Promise<void> {
    if (!this.app || this.busy || this.selected.length === 0) { return; } this.busy = true;
    try { await this.app.progress.mark(this.selected.slice(),read); this.selected = []; const ctx = this.operation.begin(30000); await this.cached(ctx); this.status = read ? '所选章节已标记读完' : '所选章节已标记未读并重置位置'; }
    catch (error) { this.status = viewError(error as Error); } finally { this.busy = false; }
  }
  async bookmark(chapter: ChapterRecord): Promise<void> {
    if (!this.app || this.busy) { return; } this.busy = true;
    try { await this.app.progress.bookmark(chapter.id,!chapter.bookmarked); const ctx = this.operation.begin(30000); await this.cached(ctx); }
    catch (error) { this.status = viewError(error as Error); } finally { this.busy = false; }
  }
  async download(ids: string[]): Promise<void> {
    if (!this.app || this.busy || ids.length === 0) { return; } const ctx = this.operation.begin(60000); this.busy = true; let queued = 0;
    try {
      for (let i = 0; i < ids.length; i++) { if (!this.operation.active(ctx)) { return; } await this.app.downloads.enqueue(ids[i]); queued++; }
      if (this.operation.active(ctx)) { this.status = '已加入下载队列：' + queued.toString() + '章'; this.selected = []; }
    } catch (error) { if (this.operation.active(ctx)) { this.status = '已加入' + queued.toString() + '章；' + viewError(error as Error); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  dispose(): void { this.operation.close(); }
  async reloadCached(): Promise<void> { if (!this.app || this.busy) { return; } const ctx = this.operation.begin(30000); try { await this.cached(ctx); } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); } } }
}
