import { url } from '@kit.ArkTS';
import { Source, SourceDiscovery, SourceFeed, SourceFilter, SourceFilterValue, SourceRef, PageToken, SourceBatch, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest, SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem } from '../../model/SourceTypes';
import { CallContext } from '../../model/RequestTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { Transport } from '../../network/Transport';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { UrlPolicy } from '../../network/UrlPolicy';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { readFilters, validateBrowse } from '../discovery/DiscoverySupport';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { refreshPage } from '../RefreshPage';
import { MYCOMIC_USER_AGENT } from '../MyComicAccess';
import { checkMyRef, myList, myDetail, myChapters, myPages } from './MyComicFormat';
import { SourceCatalog, SourceCatalogSnapshot } from '../../model/SourceTypes';

const FILTERS: SourceFilter[] = [
  { id: 'filter[tag]',title: '题材',choices: [{ value: '',title: '全部' }] },
  { id: 'filter[country]',title: '地区',choices: [{ value: '',title: '全部' }] },
  { id: 'filter[audience]',title: '受众',choices: [{ value: '',title: '全部' }] },
  { id: 'filter[year]',title: '年份',choices: [{ value: '',title: '全部' }] },
  { id: 'filter[end]',title: '状态',choices: [{ value: '',title: '全部' }] }
];
export class MyComicSource implements Source,SourceDiscovery {
  readonly id: string = 'org.hsmihon.mycomic'; readonly version: number = 1;
  readonly discovery: SourceDiscovery = this;
  readonly catalog: SourceCatalog = this;
  readonly feeds: SourceFeed[] = [{ id: 'latest',title: '最新上架' },{ id: 'updates',title: '最近更新' },{ id: 'popular',title: '最高人气' },{ id: 'category',title: '分类' }];
  private readonly site: SourceSiteAccess; private readonly transport: Transport;
  private readonly policy: UrlPolicy = new UrlPolicy([]); private readonly select: SelectorSubset = new SelectorSubset();
  constructor(site: SourceSiteAccess,transport: Transport) { this.site = site; this.transport = transport; }
  private check(ctx: CallContext): void {
    checkCall(ctx);
    if (ctx.ruleRevision !== this.version) { throw new AppError(ErrorCode.CONTENT_CHANGED,'MYCOMIC适配器已更新，请重新加载'); }
  }
  private binding(operation: string): string { return JSON.stringify([this.id,this.version,this.site.revision,this.site.baseUrl,operation]); }
  private page(token: PageToken | undefined,binding: string): number {
    if (!token) { return 1; } const value = Number(token.value);
    if (token.kind !== 'mycomic-html-page' || token.binding !== binding || !/^[1-9][0-9]*$/.test(token.value) || !Number.isSafeInteger(value) || value < 2 || value > 10000) { throw new AppError(ErrorCode.RULE_INVALID,'MYCOMIC分页标记已失效'); }
    return value;
  }
  private listIdentity(address: url.URL): string {
    return JSON.stringify([address.pathname,address.searchParams.get('q') || '',address.searchParams.get('sort') || '-id',
      address.searchParams.get('page') || '1',...FILTERS.map((filter: SourceFilter) => address.searchParams.get(filter.id) || '')]);
  }
  private async read(path: string,ctx: CallContext): Promise<HtmlNode> {
    this.check(ctx); const address = this.policy.validate(this.policy.resolve(path,this.site.baseUrl));
    const response = await this.transport.send({ sourceId: this.id,url: address.toString(),responseKind: 'metadata',maxBytes: 2097152,
      headers: [{ name: 'Accept',value: 'text/html,application/xhtml+xml' },{ name: 'Accept-Language',value: 'zh-CN,zh;q=0.9' },{ name: 'Referer',value: this.site.baseUrl },{ name: 'User-Agent',value: MYCOMIC_USER_AGENT }] },ctx);
    this.check(ctx);
    if ([200,403,503].indexOf(response.statusCode) >= 0 && /Sorry, you have been blocked/i.test(response.body)) {
      throw new AppError(ErrorCode.ACCESS_DENIED,'MYCOMIC已通过Cloudflare拒绝当前访问，保存站点会话也可能无法解除，请稍后再试');
    }
    if ([200,403,503].indexOf(response.statusCode) >= 0 && (response.headers.some((header) => header.name.toLowerCase() === 'cf-mitigated' && header.value.toLowerCase() === 'challenge') || /challenge-platform|cf-browser-verification|__cf_chl_|Just a moment/i.test(response.body))) {
      throw new AppError(ErrorCode.AUTH_REQUIRED,'MYCOMIC触发网站验证，请在来源网站完成验证并保存当前站点会话后重试；仍被拦截时请稍后再试');
    }
    requireHttpSuccess(response);
    const final = this.policy.validate(response.finalUrl);
    if (final.pathname !== address.pathname || address.pathname === '/cn/comics' && this.listIdentity(final) !== this.listIdentity(address)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'MYCOMIC返回了其他页面或查询，旧结果保留'); }
    return new HtmlExtractor().parse(response.body);
  }
  private listUrl(page: number,sort: string,query: string,filters: SourceFilterValue[]): string {
    const address = new url.URL('/cn/comics',this.site.baseUrl);
    address.searchParams.set('sort',sort);
    if (query) { address.searchParams.set('q',query); }
    if (page > 1) { address.searchParams.set('page',page.toString()); }
    filters.forEach((filter: SourceFilterValue) => { if (filter.value) { address.searchParams.set(filter.id,filter.value); } });
    return address.toString();
  }
  private next(root: HtmlNode,address: string,page: number,binding: string,empty: boolean): PageToken | undefined {
    const links = this.select.select(root,'nav[role="navigation"] a[rel="next"]');
    if (!links.length) { return undefined; }
    const expected = new url.URL(address); expected.searchParams.set('page',(page + 1).toString());
    const invalid = links.some((link: HtmlNode) => this.listIdentity(this.policy.validate(this.policy.resolve(link.attribute('href'),address))) !== this.listIdentity(expected));
    if (empty || page >= 10000 || invalid) { throw new AppError(ErrorCode.CONTENT_CHANGED,'MYCOMIC下一页位置或查询不符'); }
    return { kind: 'mycomic-html-page',value: (page + 1).toString(),binding: binding };
  }
  private filters(root: HtmlNode,address: string): SourceFilter[] {
    const scope = new HtmlNode('div');
    // Pagination URLs carry the current selection too; they are not filter choices.
    scope.children = this.select.select(root,'a[href]').filter((link: HtmlNode) => {
      try {
        const target = this.policy.validate(this.policy.resolve(link.attribute('href'),address));
        return target.pathname === '/cn/comics' && !target.searchParams.has('page') && !target.searchParams.has('q') &&
          FILTERS.some((filter: SourceFilter) => target.searchParams.has(filter.id));
      } catch (_) { return false; }
    });
    return readFilters(scope,address,'/cn/comics',FILTERS);
  }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    const keyword = query.trim();
    if (!keyword || keyword.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'MYCOMIC搜索需要1至256字关键词'); }
    const binding = this.binding('search:' + keyword); const page = this.page(token,binding); const address = this.listUrl(page,'-id',keyword,[]);
    const root = await this.read(address,ctx); const items = myList(root,this.site.baseUrl,true);
    return { items: items,next: this.next(root,address,page,binding,!items.length) };
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (!this.feeds.some((feed: SourceFeed) => feed.id === query.feed) || query.filters.length > 5 || query.feed !== 'category' && query.filters.length) { throw new AppError(ErrorCode.CONFIG_INVALID,'MYCOMIC栏目参数无效'); }
    const seen: Set<string> = new Set();
    query.filters.forEach((filter: SourceFilterValue) => {
      if (seen.has(filter.id) || !FILTERS.some((definition: SourceFilter) => definition.id === filter.id) || !/^[a-zA-Z0-9_-]{0,80}$/.test(filter.value)) { throw new AppError(ErrorCode.CONFIG_INVALID,'MYCOMIC筛选参数无效'); } seen.add(filter.id);
    });
    const operation = JSON.stringify([query.feed,query.filters.slice().sort((a: SourceFilterValue,b: SourceFilterValue) => a.id.localeCompare(b.id))]);
    const binding = this.binding('browse:' + operation); const page = this.page(token,binding);
    const sort = query.feed === 'updates' ? '-update' : query.feed === 'popular' ? '-views' : '-id';
    const address = this.listUrl(page,sort,'',query.filters); const root = await this.read(address,ctx);
    const filters = query.feed === 'category' ? this.filters(root,address) : [];
    validateBrowse(query,this.feeds,filters); const items = myList(root,this.site.baseUrl,query.feed === 'category');
    return { items: items.map((manga: MangaSummary): SourceBrowseItem => ({ manga: manga,subtitle: '' })),filters: filters,
      next: this.next(root,address,page,binding,!items.length) };
  }
  async details(ref: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    checkMyRef(ref); return myDetail(await this.read(ref.locator,ctx),ref,this.site.baseUrl);
  }
  async loadCatalog(ref: SourceRef,ctx: CallContext): Promise<SourceCatalogSnapshot> {
    checkMyRef(ref); const root = await this.read(ref.locator,ctx);
    return { detail: myDetail(root,ref,this.site.baseUrl),chapters: myChapters(root,ref,this.site.baseUrl) };
  }
  async chapters(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    checkMyRef(ref); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'MYCOMIC完整目录不接受分页标记'); }
    return { items: myChapters(await this.read(ref.locator,ctx),ref,this.site.baseUrl) };
  }
  async pages(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    checkMyRef(ref,true); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'MYCOMIC完整页清单不接受分页标记'); }
    return { items: myPages(await this.read(ref.locator,ctx),ref,this.site.baseUrl) };
  }
  async resolveImage(ref: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    checkMyRef(ref,true); this.check(ctx);
    if (refresh) { return this.resolveImage(ref,await refreshPage(this,ref,page.pageKey,ctx),false,ctx); }
    const address = this.policy.validate(page.imageUrl || '');
    if (!address.pathname.startsWith('/chapters/') || page.pageKey !== address.pathname || page.locator !== page.pageKey || !Number.isSafeInteger(page.ordinal) || page.ordinal < 0) { throw new AppError(ErrorCode.CONTENT_CHANGED,'MYCOMIC图片身份与地址不符'); }
    return { url: address.toString(),headers: [{ name: 'Referer',value: this.site.baseUrl },{ name: 'User-Agent',value: MYCOMIC_USER_AGENT }],contentRevision: this.binding('pages') };
  }
}
