import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContainer } from '../app/AppContainer';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { MangaRecord } from '../model/LibraryTypes';
import { PageToken } from '../model/SourceTypes';
import { ManagedSource } from '../source/SourceImportService';
import { SourceHandle } from '../source/SourceRegistry';
import { ListDataSource } from '../ui/ListDataSource';
import { ViewOperation, viewError } from './ViewOperation';
import { GlobalCatalogSearch, SearchGroup } from '../business/GlobalCatalogSearch';

export interface SearchResultRow {
  key: string; kind: string; sourceId: string; label: string; detail: string; action: string; mangas?: MangaRecord[];
}

@Observed
export class SearchVM {
  query: string = '';
  sourceId: string = '';
  sources: ManagedSource[] = [];
  status: string = '输入关键词后，搜索所有已激活漫画源。';
  busy: boolean = false;
  count: number = 0;
  hasNext: boolean = false;
  readonly data: ListDataSource<MangaRecord> = new ListDataSource();
  readonly groupedData: ListDataSource<SearchResultRow> = new ListDataSource();
  groups: SearchGroup[] = [];
  columns: number = 3;
  private items: MangaRecord[] = [];
  private app?: AppContainer;
  private readonly operations: ViewOperation = new ViewOperation();
  private next?: PageToken;
  private handle?: SourceHandle;
  private committedQuery: string = '';
  private tokens: Set<string> = new Set();
  private global?: GlobalCatalogSearch;
  private expanded: Set<string> = new Set();
  private folded: Set<string> = new Set();

  private activeSources(sources: ManagedSource[]): ManagedSource[] {
    const seen: Set<string> = new Set();
    return sources.filter((item: ManagedSource) => {
      if (!item.state.enabled || item.state.removed || !item.state.active || item.rule.capabilities.indexOf('search') < 0 || seen.has(item.state.id)) { return false; }
      seen.add(item.state.id); return true;
    });
  }

  async initialize(context: common.UIAbilityContext, sourceId: string = ''): Promise<void> {
    this.operations.reopen(); this.app = new AppContainer(context); const ctx = this.operations.begin(30000);
    this.global = new GlobalCatalogSearch(this.app.catalogService);
    try {
      const sources = this.activeSources(await this.app.listSources());
      const requested = sourceId || this.sourceId;
      if (this.operations.active(ctx)) {
        this.sources = sources; this.sourceId = sources.some((item: ManagedSource) => item.state.id === requested) ? requested : '*';
        this.status = sources.length ? '将搜索 ' + sources.length.toString() + ' 个已激活漫画源' : '暂无已激活且支持搜索的漫画源，请在浏览页启用。';
      }
    } catch (error) { if (this.operations.active(ctx)) { this.status = viewError(error as Error); } }
  }
  select(id: string): void {
    this.operations.cancel(); this.busy = false; this.sourceId = id; this.handle = undefined; this.next = undefined;
    this.items = []; this.data.replace([]); this.count = 0; this.hasNext = false; this.tokens.clear();
    this.global?.clear(); this.groups = []; this.groupedData.replace([]); this.committedQuery = ''; this.expanded.clear();
  }
  change(value: string): void {
    if (value === this.query) { return; }
    this.query = value; this.select(this.sourceId);
    this.status = value.trim() ? '点击搜索或按回车，搜索所有已激活漫画源。' : '请输入搜索关键词。';
  }
  async search(more: boolean = false): Promise<void> {
    if (!this.app || !this.sourceId || more && this.busy) { return; }
    if (this.sourceId === '*') { await this.searchGlobal(more); return; }
    if (more && (!this.next || !this.handle)) { return; }
    const query = more ? this.committedQuery : this.query.trim();
    if (query.length > 256 || /[\u0000-\u001f\u007f]/.test(query)) { this.status = '关键词格式无效'; return; }
    const ctx = this.operations.begin(30000); this.busy = true; this.status = more ? '正在读取下一页…' : '正在搜索…';
    let step = 'open-source';
    try {
      const handle = more ? this.handle! : await this.app.catalogService.open(this.sourceId); ctx.ruleRevision = handle.source.version;
      step = 'source-and-cache';
      const batch = await this.app.catalogService.search(handle, query, more ? this.next : undefined, ctx);
      step = 'merge-results';
      if (!this.operations.active(ctx)) { return; }
      const items = more ? this.items.slice() : []; const seen = new Set(items.map((item: MangaRecord) => item.id)); const before = items.length;
      batch.items.forEach((item: MangaRecord) => { if (!seen.has(item.id)) { seen.add(item.id); items.push(item); } });
      const tokens = more ? this.tokens : new Set<string>();
      if (batch.next) {
        const key = JSON.stringify([batch.next.kind, batch.next.value, batch.next.binding]);
        if (tokens.has(key) || more && items.length === before) { throw new AppError(ErrorCode.PARSE_ERROR, '分页重复或没有新结果，已有结果保留'); }
        tokens.add(key);
      }
      this.items = items; step = 'notify-list'; this.data.replace(items); this.count = items.length; this.next = batch.next; this.hasNext = batch.next !== undefined;
      this.handle = handle; this.committedQuery = query; this.tokens = tokens;
      this.status = items.length ? '已读取' + items.length.toString() + '项' : '该源明确返回没有结果';
    } catch (error) {
      const typed = error as Error;
      const detail = typed instanceof TypeError || typed instanceof ReferenceError ? typed.message.replace(/https?:\/\/[^\s]+/g, '[URL]').substring(0, 200) : '';
      hilog.error(0x0001, 'HSReader', 'SEARCH_FAILURE step=%{public}s type=%{public}s detail=%{public}s', step, typed.name, detail);
      if (this.operations.active(ctx)) { this.status = viewError(typed) + (this.count ? '（上次结果已保留）' : ''); }
    }
    finally { if (this.operations.active(ctx)) { this.busy = false; } }
  }
  private updateGlobalResults(): void {
    const global = this.global; if (!global) { return; }
    this.groups = global.groups(); this.items = global.items(); this.data.replace(this.items); this.count = this.items.length; this.hasNext = global.hasNext();
    const rows: SearchResultRow[] = [];
    this.groups.forEach((group: SearchGroup) => {
      const name = this.sources.find((item: ManagedSource) => item.state.id === group.sourceId)?.rule.name || group.sourceId;
      const state = group.state === 'pending' ? '等待搜索' : group.state === 'loading' ? '搜索中' : group.state === 'error' ? '搜索失败' : group.state === 'cancelled' ? '已取消' : '已完成';
      const folded = this.folded.has(group.sourceId);
      const revision = group.sourceId + ':' + group.state + ':' + group.items.length.toString();
      rows.push({ key: 'source:' + revision + ':' + folded.toString(),kind: 'source',sourceId: group.sourceId,label: name,detail: group.items.length.toString() + ' 部 · ' + state,action: folded ? 'unfold' : 'fold' });
      if (folded) { return; }
      const expanded = this.expanded.has(group.sourceId);
      const visible = expanded ? group.items : group.items.slice(0,this.columns);
      for (let offset = 0; offset < visible.length; offset += this.columns) {
        const cards = visible.slice(offset,offset + this.columns);
        rows.push({ key: 'covers:' + group.sourceId + ':' + this.columns.toString() + ':' + cards.map((manga: MangaRecord) => manga.id).join(','),kind: 'covers',sourceId: group.sourceId,label: '',detail: '',action: '',mangas: cards });
      }
      if (group.items.length > this.columns) {
        rows.push({ key: 'expand:' + revision + ':' + expanded.toString(),kind: 'status',sourceId: group.sourceId,label: '已显示 ' + visible.length.toString() + '/' + group.items.length.toString() + ' 部',detail: '',action: expanded ? 'collapse' : 'expand' });
      }
      const message = group.state === 'error' ? group.error : group.state === 'pending' ? '等待搜索此漫画源…' : group.state === 'loading' ? '正在搜索此漫画源…' : group.state === 'cancelled' ? '搜索已取消，已有结果保留' : group.hasNext ? '此漫画源还有更多结果' : group.items.length ? '此漫画源结果已加载完' : '此漫画源未找到相关漫画';
      const action = group.state === 'error' ? 'retry' : group.state === 'cancelled' ? 'continue' : group.state === 'success' && group.hasNext ? 'more' : '';
      rows.push({ key: 'status:' + revision,kind: 'status',sourceId: group.sourceId,label: message,detail: '',action: action });
    });
    this.groupedData.replace(rows);
  }
  private globalStatus(): string {
    const done = this.groups.filter((group: SearchGroup) => group.state === 'success' || group.state === 'error').length;
    const errors = this.groups.filter((group: SearchGroup) => group.state === 'error').length;
    return '已完成 ' + done.toString() + '/' + this.groups.length.toString() + ' 个漫画源，共 ' + this.count.toString() + ' 部' + (errors ? ' · ' + errors.toString() + ' 个源失败' : '');
  }
  toggleSource(id: string): void {
    if (this.expanded.has(id)) { this.expanded.delete(id); } else { this.expanded.add(id); }
    this.updateGlobalResults();
  }
  setColumns(columns: number): void {
    if (!Number.isInteger(columns) || columns < 2 || columns > 7 || columns === this.columns) { return; }
    this.columns = columns; this.updateGlobalResults();
  }
  toggleFold(id: string): void {
    if (this.folded.has(id)) { this.folded.delete(id); } else { this.folded.add(id); }
    this.updateGlobalResults();
  }
  foldAll(value: boolean): void {
    if (value) { this.groups.forEach((group: SearchGroup) => this.folded.add(group.sourceId)); }
    else { this.folded.clear(); }
    this.updateGlobalResults();
  }
  async searchSource(id: string): Promise<void> {
    if (this.busy || this.sourceId !== '*' || !this.committedQuery) { return; }
    await this.searchGlobal(true,id);
  }
  private async searchGlobal(more: boolean,onlySource: string = ''): Promise<void> {
    const global = this.global; const app = this.app; if (!global || !app) { return; }
    const query = more ? this.committedQuery : this.query.trim();
    if (!query || query.length > 256 || /[\u0000-\u001f\u007f]/.test(query)) { this.status = '全局搜索请输入1～256个可见字符'; return; }
    if (more && query !== this.query.trim()) { this.status = '关键词已改变，请重新搜索'; return; }
    const ctx = this.operations.begin(Math.max(60000,Math.ceil(this.sources.length / 2) * 35000 + 15000)); this.busy = true;
    this.status = more ? '正在读取此漫画源的结果…' : '正在读取已激活漫画源…';
    const changed = (): void => {
      if (!this.operations.active(ctx)) { return; }
      this.updateGlobalResults(); this.status = this.globalStatus();
    };
    try {
      if (!more) {
        const sources = this.activeSources(await app.listSources()); if (!this.operations.active(ctx)) { return; }
        this.sources = sources; this.committedQuery = query; global.clear(); this.expanded.clear(); this.updateGlobalResults();
        if (!sources.length) { this.status = '暂无已激活且支持搜索的漫画源，请在浏览页启用。'; return; }
        ctx.deadlineMs = Date.now() + Math.max(60000,Math.ceil(sources.length / 2) * 35000 + 15000);
      }
      if (onlySource) { await global.loadSource(onlySource,query,ctx,changed); }
      else { await global.search(this.sources.map((item: ManagedSource) => item.state.id),query,more,ctx,changed); }
      changed();
    }
    catch (error) { if (this.operations.active(ctx)) { global.cancel(); this.updateGlobalResults(); this.status = viewError(error as Error) + '，已取得结果保留'; } }
    finally { if (this.operations.active(ctx)) { this.busy = false; } }
  }
  cancel(): void { this.operations.cancel(); this.global?.cancel(); this.busy = false; this.updateGlobalResults(); this.status = '已取消，已有结果保留'; }
  dispose(): void { this.operations.close(); this.global?.cancel(); }
}
