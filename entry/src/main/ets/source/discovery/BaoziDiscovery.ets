import { url } from '@kit.ArkTS';
import { SourceDiscovery, SourceFeed, SourceFilter, SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem, PageToken } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { Transport } from '../../network/Transport';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { HtmlNode } from '../rules/HtmlExtractor';
import { DiscoveryBase } from './DiscoveryBase';
import { firstText, nodeText, queryBinding, pageNumber, validateBrowse, filterValue, readFilters, uniqueCards } from './DiscoverySupport';

export class BaoziDiscovery extends DiscoveryBase implements SourceDiscovery {
  readonly feeds: SourceFeed[] = [{ id: 'recommended',title: '推荐' },{ id: 'popular',title: '热门' },{ id: 'updates',title: '更新' },{ id: 'latest',title: '新上架' },{ id: 'completed',title: '完结' },{ id: 'category',title: '分类' }];
  private filters: SourceFilter[] = [];
  private nextPages: Map<string,string> = new Map();
  constructor(site: SourceSiteAccess,transport: Transport,coverHosts: string[]) { super(site.sourceId,site,transport,coverHosts); }
  private definitions(): SourceFilter[] {
    return [{ id: 'type',title: '题材',choices: [{ value: 'all',title: '全部' }] },{ id: 'region',title: '地区',choices: [{ value: 'all',title: '全部' }] },{ id: 'state',title: '状态',choices: [{ value: 'all',title: '全部' },{ value: 'serial',title: '连载中' },{ value: 'pub',title: '已完结' }] }];
  }
  private visibleFilters(feed: string): SourceFilter[] { return this.filters.filter((group: SourceFilter) => feed !== 'completed' || group.id !== 'state'); }
  private cards(root: HtmlNode): SourceBrowseItem[] {
    const items: SourceBrowseItem[] = [];
    this.select.select(root,'div.comics-card').forEach((card: HtmlNode) => {
      let ancestor = card.parent;
      while (ancestor) { if (ancestor.tag === 'template') { return; } ancestor = ancestor.parent; }
      const link = this.select.select(card,'a.comics-card__poster')[0]; if (!link) { return; }
      const title = link.attribute('title') || firstText(card,'h3'); if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'包子首页标题缺失'); }
      items.push({ manga: { ref: this.ref(link.attribute('href')),title: title,cover: this.cardImage(card) },subtitle: firstText(card,'.last_chapter') || firstText(card,'small') });
    });
    return uniqueCards(items);
  }
  private next(raw: string,binding: string,page: number): PageToken | undefined {
    if (!raw) { return undefined; }
    const parsed = this.policy.validate(this.policy.resolve(raw,this.site.baseUrl));
    if (parsed.pathname !== '/api/bzmhq/amp_comic_list' || Number(parsed.searchParams.get('page')) !== page + 1) { throw new AppError(ErrorCode.PARSE_ERROR,'包子分类分页没有前进'); }
    this.nextPages.set(binding + ':' + (page + 1).toString(),parsed.toString());
    if (this.nextPages.size > 24) { this.nextPages.delete(this.nextPages.keys().next().value); }
    return { kind: 'source-home',value: (page + 1).toString(),binding: binding };
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    const category = query.feed === 'category' || query.feed === 'completed';
    validateBrowse(query,this.feeds,category ? this.visibleFilters(query.feed) : []);
    const binding = queryBinding(this.id,this.site.revision,query); const page = pageNumber(token,binding);
    if (page > 1) {
      const path = this.nextPages.get(binding + ':' + page.toString()); if (!category || !path || Number(new url.URL(path).searchParams.get('page')) !== page) { throw new AppError(ErrorCode.CONFIG_INVALID,'请先加载分类首页'); }
      const root = this.json(await this.read(path,ctx,true)); const list = root.members.get('items');
      if (!list || list.kind !== 'array' || list.items.length > 100) { throw new AppError(ErrorCode.PARSE_ERROR,'包子分类分页结构变化'); }
      const items = list.items.map((item): SourceBrowseItem => {
        const name = this.scalar(item,'name'); const id = this.scalar(item,'comic_id'); const image = this.scalar(item,'topic_img');
        if (!name || name.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'包子分页漫画字段无效'); }
        const cover = /^[a-zA-Z0-9_.-]{1,300}$/.test(image) ? this.cover('https://static-tw.baozimh.com/cover/' + image + '?w=285&h=375&q=100') : undefined;
        return { manga: { ref: this.ref('/comic/' + id),title: name,cover: cover },subtitle: this.scalar(item,'author') };
      });
      const next = this.scalar(root,'next'); if (next && items.length === 0) { throw new AppError(ErrorCode.PARSE_ERROR,'包子分页没有新结果'); }
      return { items: uniqueCards(items),filters: this.visibleFilters(query.feed),next: this.next(next,binding,page) };
    }
    if (category) {
      const address = new url.URL('/classify',this.site.baseUrl);
      address.searchParams.set('type',filterValue(query,'type') || 'all'); address.searchParams.set('region',filterValue(query,'region') || 'all');
      address.searchParams.set('state',query.feed === 'completed' ? 'pub' : filterValue(query,'state') || 'all'); address.searchParams.set('filter','*');
      const root = await this.document(address.toString(),ctx);
      if (!this.select.select(root,'.classify').length) { throw new AppError(ErrorCode.PARSE_ERROR,'包子分类页面结构变化'); }
      const filters = readFilters(root,address.toString(),'/classify',this.filters.length ? this.filters : this.definitions());
      if (filters.length < 3) { throw new AppError(ErrorCode.PARSE_ERROR,'包子分类条件缺失'); } this.filters = filters;
      const amp = this.select.select(root,'amp-list[src]')[0];
      const items = this.cards(root); if (items.length === 0 && amp) { throw new AppError(ErrorCode.PARSE_ERROR,'分类首页未返回可确认的漫画列表'); }
      return { items: items,filters: this.visibleFilters(query.feed),next: this.next(amp?.attribute('src') || '',binding,1) };
    }
    const root = await this.document(query.feed === 'latest' ? '/list/new' : '/',ctx);
    let sections: HtmlNode[];
    if (query.feed === 'latest') { sections = [root]; }
    else if (query.feed === 'popular') { sections = this.select.select(root,'.index-rank'); }
    else if (query.feed === 'recommended') { sections = this.select.select(root,'.category'); }
    else { sections = this.select.select(root,'.index-recommend-items').filter((node: HtmlNode) => nodeText(node).startsWith('最近更新')); }
    let items: SourceBrowseItem[] = []; sections.forEach((section: HtmlNode) => { items = items.concat(this.cards(section)); }); items = uniqueCards(items);
    if (!items.length) { throw new AppError(ErrorCode.PARSE_ERROR,'包子首页栏目结构变化，可打开网站首页查看'); }
    return { items: items,filters: [] };
  }
}
