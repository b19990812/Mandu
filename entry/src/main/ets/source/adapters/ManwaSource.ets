import { Source, SourceDiscovery, SourceFeed, SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem, SourceRef, SourceBatch, PageToken, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { JsonNode } from '../../parsing/JsonExtractor';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { refreshPage } from '../RefreshPage';
import { checkCall } from '../SourceHttp';
import { SiteJsonClient, siteScalar, siteNumber } from './SiteJsonClient';

// Exact hosts observed in public 2026-10-28 metadata. IP/port and VIP-only lines are not selected.
export const MANWA_IMAGE_HOSTS: string[] = ['mwtuwu.cc'];
export const MANWA_COVER_HOSTS: string[] = ['ce.mwzu.cc'];
interface ManwaChapter { ref: ChapterRef; sort: number; position: number; }
export class ManwaSource implements Source,SourceDiscovery {
  readonly id: string = 'org.hsmihon.manwa'; readonly version: number = 1;
  readonly discovery: SourceDiscovery = this;
  readonly feeds: SourceFeed[] = [{ id: 'home',title: '首页' },{ id: 'rank',title: '热门' },{ id: 'gufeng',title: '古风' },{ id: 'xuanhuan',title: '玄幻' },{ id: 'xiaoyuan',title: '校园' }];
  private readonly client: SiteJsonClient; private readonly select: SelectorSubset = new SelectorSubset();
  private readonly images: UrlPolicy = new UrlPolicy(MANWA_IMAGE_HOSTS); private readonly covers: UrlPolicy = new UrlPolicy(MANWA_COVER_HOSTS);
  constructor(site: SourceSiteAccess,transport: Transport) { this.client = new SiteJsonClient(site,transport,this.version); }
  private manga(id: string): SourceRef { if (!/^[1-9][0-9]{0,14}$/.test(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙作品ID无效'); } return { sourceId: this.id,remoteId: id,locator: '/comic/' + id }; }
  private check(ref: SourceRef,chapter: boolean = false): string[] {
    const parts = ref.remoteId.split('/');
    if (ref.sourceId !== this.id || parts.length !== (chapter ? 2 : 1) || parts.some((part: string) => !/^[1-9][0-9]{0,14}$/.test(part)) || ref.locator !== '/comic/' + ref.remoteId) { throw new AppError(ErrorCode.RULE_INVALID,'漫蛙资源身份与地址不符'); } return parts;
  }
  private title(node: JsonNode): string { const value = siteScalar(node,'title'); if (!value.trim() || value.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙标题无效'); } return value; }
  private summary(node: JsonNode): MangaSummary {
    const ref = this.manga(siteScalar(node,'id')); let cover: string | undefined;
    const raw = siteScalar(node,'cover') || siteScalar(node,'pic'); if (raw) { try { cover = this.covers.validate(raw).toString(); } catch (_) {} }
    const locator = siteScalar(node,'url'); if (locator && locator !== ref.locator) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙返回了其他类型的资源'); }
    return { ref: ref,title: this.title(node),cover: cover };
  }
  private page(token: PageToken | undefined,binding: string): number {
    const page = token ? Number(token.value) : 1;
    if (token && (token.kind !== 'manwa-page' || token.binding !== binding) || !Number.isSafeInteger(page) || page < 1 || page > 1000) { throw new AppError(ErrorCode.RULE_INVALID,'漫蛙分页参数已失效'); } return page;
  }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (!query.trim() || query.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'漫蛙搜索需要1至256字关键词'); }
    const binding = this.client.binding('search:' + query); const page = this.page(token,binding);
    const data = await this.client.data('/api/search?type=mh&keyword=' + encodeURIComponent(query) + '&page=' + page.toString() + '&pageSize=20',ctx);
    const total = siteNumber(data,'total',20000); const list = data.members.get('list');
    if (!list || list.kind !== 'array' || list.items.length !== Math.min(20,Math.max(0,total - (page - 1) * 20))) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙搜索分页缺项'); }
    const seen: Set<string> = new Set(); const items = list.items.map((node: JsonNode): MangaSummary => { const item = this.summary(node); if (seen.has(item.ref.remoteId)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙搜索结果重复'); } seen.add(item.ref.remoteId); return item; });
    return { items: items,next: page * 20 < total ? { kind: 'manwa-page',value: (page + 1).toString(),binding: binding } : undefined };
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (!this.feeds.some((feed: SourceFeed) => feed.id === query.feed) || query.filters.length) { throw new AppError(ErrorCode.CONFIG_INVALID,'漫蛙栏目参数无效'); }
    const binding = this.client.binding('browse:' + query.feed); const page = this.page(token,binding); const type = ['home','rank'].indexOf(query.feed) >= 0 ? 'comic' : query.feed;
    const data = await this.client.data('/api/home?page=' + page.toString() + '&pageSize=12&type=' + type + '&rankType=' + (query.feed === 'rank' ? '1' : '0') + '&flag=true',ctx);
    const list = data.members.get(type + 'List');
    if (!list || list.kind !== 'array' || list.items.length > 12) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙首页清单结构无效'); }
    const seen: Set<string> = new Set(); const items = list.items.map((node: JsonNode): SourceBrowseItem => {
      const kind = siteScalar(node,'type'); if (kind && kind !== 'comic') { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙栏目含非漫画资源'); }
      const manga = this.summary(node); if (seen.has(manga.ref.remoteId)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙首页返回重复作品'); } seen.add(manga.ref.remoteId); return { manga: manga,subtitle: '' };
    });
    return { items: items,filters: [],next: items.length === 12 && page < 1000 ? { kind: 'manwa-page',value: (page + 1).toString(),binding: binding } : undefined };
  }
  private text(root: HtmlNode,selector: string): string { return this.select.select(root,selector)[0]?.textContent().replace(/\s+/g,' ').trim() || ''; }
  async details(ref: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    this.check(ref); const root = new HtmlExtractor().parse(await this.client.text(ref.locator,ctx)); const title = this.text(root,'#page-title');
    if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙详情标题缺失'); }
    const image = this.select.select(root,'.comic-cover')[0]; let cover: string | undefined;
    if (image) { try { cover = this.covers.validate(image.attribute('data-src') || image.attribute('data-original-cover')).toString(); } catch (_) {} }
    const state = this.text(root,'#status');
    return { ref: ref,title: title,cover: cover,authors: this.select.select(root,'#author-container a').map((node: HtmlNode) => node.textContent().trim()),
      description: this.text(root,'.comic-desc'),tags: this.select.select(root,'#tagsContainer a').map((node: HtmlNode) => node.textContent().trim()),status: state === '已完结' ? 'completed' : state === '连载中' ? 'ongoing' : 'unknown' };
  }
  async chapters(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    this.check(ref); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'漫蛙目录不接受外部分页'); }
    const root = new HtmlExtractor().parse(await this.client.text(ref.locator,ctx));
    const htmlChapters = this.select.select(root,'#chapter-grid-container .chapter-item');
    const data = await this.client.data('/api/comic/' + ref.remoteId + '/chapters',ctx); const list = data.members.get('list');
    if (!list || list.kind !== 'array' || list.items.length < 1 || list.items.length > 10000 || list.items.length !== htmlChapters.length) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫蛙完整目录数量不符，旧目录保留'); }
    const expected: Map<string,number> = new Map(); htmlChapters.forEach((node: HtmlNode,index: number) => { const id = node.attribute('data-id'); if (expected.has(id) || node.attribute('href') !== ref.locator + '/' + id) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙网页目录身份异常'); } expected.set(id,index); });
    const seen: Set<string> = new Set();
    const ordered = list.items.map((node: JsonNode): ManwaChapter => {
      const id = siteScalar(node,'id'); this.manga(id); const sort = Number(siteScalar(node,'sortId'));
      if (siteScalar(node,'comicId') !== ref.remoteId || !expected.has(id) || seen.has(id) || node.members.get('sortId')?.kind !== 'number' || !Number.isFinite(sort) || sort < 0) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫蛙目录作品身份或顺序不符'); } seen.add(id);
      return { ref: { ref: { sourceId: this.id,remoteId: ref.remoteId + '/' + id,locator: ref.locator + '/' + id },mangaRemoteId: ref.remoteId,title: this.title(node),ordinal: 0 },sort: sort,position: expected.get(id)! };
    });
    // Special episodes can share sortId. The verified full HTML directory supplies a stable tie order.
    ordered.sort((a: ManwaChapter,b: ManwaChapter) => a.sort - b.sort || a.position - b.position);
    return { items: ordered.map((item: ManwaChapter,index: number): ChapterRef => { item.ref.ordinal = index; return item.ref; }) };
  }
  async pages(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    const parts = this.check(ref,true); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'漫蛙页清单由适配器完整读取'); }
    const info = await this.client.data('/api/comic/chapter/info/' + parts[1],ctx); const current = info.members.get('current');
    if (!current || siteScalar(current,'id') !== parts[1] || siteScalar(current,'comicId') !== parts[0]) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫蛙返回其他章节'); }
    const items: PageRef[] = []; const seen: Set<string> = new Set(); let total = -1; let batches = 1;
    for (let page = 1; page <= batches; page++) {
      const data = await this.client.data('/api/comic/image/' + parts[1] + '?page=' + page.toString() + '&page_size=50&image_source=' + encodeURIComponent('https://mwtuwu.cc'),ctx);
      const pagination = data.members.get('pagination'); const list = data.members.get('images');
      if (!pagination || !list || list.kind !== 'array') { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙图片分页缺失'); }
      const count = siteNumber(pagination,'total',2000); const pages = siteNumber(pagination,'total_pages',40);
      if (count < 1 || pages !== Math.ceil(count / 50) || siteNumber(pagination,'current_page',40) !== page || siteNumber(pagination,'page_size',50) !== 50 || total >= 0 && total !== count || list.items.length !== Math.min(50,count - items.length)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫蛙图片分页不完整或总数已改变'); }
      total = count; batches = pages;
      list.items.forEach((node: JsonNode) => {
        const address = this.images.validate(siteScalar(node,'url')); const key = address.pathname;
        if (!key.includes('/' + parts[0] + '/' + parts[1] + '/') || seen.has(key)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫蛙图片不属于本章或出现重复'); } seen.add(key);
        items.push({ pageKey: key,ordinal: items.length,locator: key,imageUrl: address.toString() });
      });
    }
    checkCall(ctx); return { items: items };
  }
  async resolveImage(ref: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    const parts = this.check(ref,true); checkCall(ctx); if (refresh) { return this.resolveImage(ref,await refreshPage(this,ref,page.pageKey,ctx),false,ctx); }
    const address = this.images.validate(page.imageUrl || '');
    if (address.pathname !== page.pageKey || page.locator !== page.pageKey || !page.pageKey.includes('/' + parts[0] + '/' + parts[1] + '/')) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫蛙页面身份不符'); }
    return { url: address.toString(),headers: [{ name: 'Referer',value: this.client.site.baseUrl }],contentRevision: this.client.binding('image-aes256-v1'),encoding: 'manwa-aes256-v1' };
  }
}
