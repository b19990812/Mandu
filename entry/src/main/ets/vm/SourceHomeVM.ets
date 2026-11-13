import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { SourceDiscoveryService } from '../business/SourceDiscoveryService';
import { SourceHandle } from '../source/SourceRegistry';
import { SourceFeed, SourceFilter, SourceFilterChoice, SourceFilterValue, SourceBrowseQuery, SourceBrowseItem, PageToken, SourceBrowseBatch } from '../model/SourceTypes';
import { ListDataSource } from '../ui/ListDataSource';
import { ViewOperation, viewError } from './ViewOperation';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { SiteSession } from '../network/SiteSession';
import { SourceChanges } from '../source/SourceChanges';

@Observed
export class SourceHomeVM {
  sourceId: string = '';
  name: string = '漫画源';
  feeds: SourceFeed[] = [];
  feed: string = '';
  filters: SourceFilter[] = [];
  selected: SourceFilterValue[] = [];
  status: string = '正在读取来源…';
  busy: boolean = false;
  opening: boolean = false;
  supported: boolean = false;
  count: number = 0;
  hasNext: boolean = false;
  readonly data: ListDataSource<SourceBrowseItem> = new ListDataSource();
  private items: SourceBrowseItem[] = [];
  private next?: PageToken;
  private tokens: Set<string> = new Set();
  private shownKey: string = '';
  private handle?: SourceHandle;
  private service?: SourceDiscoveryService;
  private readonly operation: ViewOperation = new ViewOperation();
  private readonly navigation: ViewOperation = new ViewOperation();
  async initialize(context: common.UIAbilityContext,sourceId: string): Promise<void> {
    this.operation.reopen(); this.navigation.reopen(); this.sourceId = sourceId;
    const app = new AppContainer(context); this.service = new SourceDiscoveryService(app.registry,app.catalog);
    const ctx = this.operation.begin(60000); this.busy = true;
    try {
      const handle = await this.service.open(sourceId); if (!this.operation.active(ctx)) { return; }
      this.handle = handle; this.name = handle.rule.name; this.feeds = handle.source.discovery?.feeds || []; this.supported = this.feeds.length > 0;
      this.feed = this.feeds[0]?.id || ''; this.busy = false;
      if (this.supported) { await this.load(false,false); } else { this.status = '该源暂未提供原生首页，可使用搜索或网站首页'; }
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); this.busy = false; } }
  }
  chooseFeed(id: string): void {
    if (!this.feeds.some((feed: SourceFeed) => feed.id === id) || this.feed === id) { return; }
    this.feed = id; this.selected = []; this.filters = []; this.load(false,false);
  }
  choiceIndex(group: SourceFilter): number { const value = this.selected.find((item: SourceFilterValue) => item.id === group.id)?.value || group.choices[0].value; return Math.max(0,group.choices.findIndex((choice: SourceFilterChoice) => choice.value === value)); }
  choiceTitle(group: SourceFilter): string { return group.choices[this.choiceIndex(group)].title; }
  chooseFilter(group: SourceFilter,index: number): void {
    const choice = group.choices[index]; if (!choice || this.choiceIndex(group) === index) { return; }
    this.selected = this.selected.filter((item: SourceFilterValue) => item.id !== group.id).concat([{ id: group.id,value: choice.value }]); this.load(false,false);
  }
  resetFilters(): void { this.selected = []; this.load(false,false); }
  private accept(batch: SourceBrowseBatch,more: boolean): void {
    const items = more ? this.items.slice() : []; const seen: Set<string> = new Set(items.map((item: SourceBrowseItem) => item.manga.ref.remoteId)); const before = items.length;
    batch.items.forEach((item: SourceBrowseItem) => { if (!seen.has(item.manga.ref.remoteId)) { seen.add(item.manga.ref.remoteId); items.push(item); } });
    if (items.length > 2000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'当前栏目已达到2000项，请收窄筛选条件'); }
    const key = batch.next ? JSON.stringify(batch.next) : '';
    if (more && batch.next && (this.tokens.has(key) || items.length === before)) { throw new AppError(ErrorCode.PARSE_ERROR,'来源分页重复，已有结果保留'); }
    if (!more) { this.tokens.clear(); } if (key) { this.tokens.add(key); }
    this.filters = batch.filters; this.items = items; this.data.replace(items); this.count = items.length; this.next = batch.next; this.hasNext = !!batch.next;
  }
  async load(more: boolean = false,force: boolean = true): Promise<void> {
    const handle = this.handle; const service = this.service;
    if (!handle || !service || !this.supported || more && (this.busy || !this.next)) { return; }
    this.navigation.cancel(); this.opening = false;
    const query: SourceBrowseQuery = { feed: this.feed,filters: this.selected.map((item: SourceFilterValue): SourceFilterValue => ({ id: item.id,value: item.value })) };
    const ctx = this.operation.begin(60000,handle.source.version); this.busy = true;
    const token = more ? this.next : undefined;
    const shownKey = JSON.stringify([handle.snapshotKey,handle.revision,SourceChanges.epoch(handle.source.id),SiteSession.epoch(handle.source.id),query.feed,query.filters.slice().sort((a,b) => a.id.localeCompare(b.id))]);
    if (!more && shownKey !== this.shownKey) { this.items = []; this.data.replace([]); this.count = 0; this.next = undefined; this.hasNext = false; this.tokens.clear(); this.shownKey = shownKey; }
    this.status = more ? '正在加载更多…' : '正在加载' + (this.feeds.find((feed: SourceFeed) => feed.id === query.feed)?.title || '栏目') + '…';
    try {
      if (!more && !force) {
        const cached = await service.cached(handle,query,ctx); if (!this.operation.active(ctx)) { return; }
        if (cached) {
          this.accept(cached.batch,false);
          this.status = '已读取缓存 ' + this.count.toString() + ' 部';
          if (cached.expiresAt > Date.now()) { return; }
          this.status += ' · 正在刷新…';
        }
      }
      const batch = await service.browse(handle,query,token,ctx); if (!this.operation.active(ctx)) { return; }
      this.accept(batch,more);
      this.status = this.count ? '已加载 ' + this.count.toString() + ' 部' + (batch.next ? '' : ' · 本栏目已加载完') : '此筛选下暂无漫画';
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error) + (this.count ? '（已有结果保留）' : ''); } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  async openItem(item: SourceBrowseItem): Promise<string> {
    if (!this.service || !this.handle || this.opening || this.busy && this.count === 0) { return ''; }
    const ctx = this.navigation.begin(30000,this.handle.source.version); this.opening = true;
    try { const id = await this.service.select(this.handle,item,ctx); return this.navigation.active(ctx) ? id : ''; }
    catch (error) { if (this.navigation.active(ctx)) { this.status = viewError(error as Error); } return ''; }
    finally { if (this.navigation.active(ctx)) { this.opening = false; } }
  }
  cancel(): void { this.operation.cancel(); this.busy = false; this.status = this.count ? '已取消，已有结果保留' : '已取消，可重新加载当前栏目'; }
  dispose(): void { this.operation.close(); this.navigation.close(); }
}
