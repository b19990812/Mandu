import { url } from '@kit.ArkTS';
import { Source, SourceDiscovery, SourceFeed, SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem, SourceRef, PageToken, SourceBatch, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { refreshPage } from '../RefreshPage';
import { HipFormat } from './HipFormat';
import { HipChapterId } from './HipChapterId';
import { SourceCatalog, SourceCatalogSnapshot } from '../../model/SourceTypes';

export const HIP_HOSTS: string[] = ['reader.hipmh.top','hipapi1.s3file.top','cover.s3imgs.top','hip-tx-1.s3imgs.top','hip-cf-1.s3imgs.top','hip-tx-s1.s3imgs.top','hip-cf-s1.s3imgs.top'];
export class HipSource implements Source, SourceDiscovery {
  readonly id: string = 'org.hsmihon.hipmh'; readonly version: number = 2;
  readonly discovery: SourceDiscovery = this;
  readonly catalog: SourceCatalog = this;
  readonly feeds: SourceFeed[] = [{ id: 'home',title: '首页' }];
  private readonly site: SourceSiteAccess; private readonly transport: Transport;
  private readonly policy: UrlPolicy; private readonly sitePolicy: UrlPolicy;
  private readonly select: SelectorSubset = new SelectorSubset();
  constructor(site: SourceSiteAccess,transport: Transport) { this.site = site; this.transport = transport; this.policy = new UrlPolicy(site.allowedHosts.concat(HIP_HOSTS)); this.sitePolicy = new UrlPolicy(site.allowedHosts); }
  private async get(address: string,ctx: CallContext): Promise<string> {
    checkCall(ctx); if (ctx.ruleRevision !== this.version) { throw new AppError(ErrorCode.CONTENT_CHANGED,'HIP适配器已改变'); }
    const response = await this.transport.send({ sourceId: this.id,url: this.policy.resolve(address,this.site.baseUrl),headers: [{ name: 'Referer',value: this.site.baseUrl }],maxBytes: 2097152 },ctx);
    requireHttpSuccess(response); checkCall(ctx); return response.body;
  }
  private value(node: JsonNode,key: string): string { const field = node.members.get(key); return field && (field.kind === 'string' || field.kind === 'number') ? field.scalar : ''; }
  private ref(path: string): SourceRef {
    const address = this.sitePolicy.validate(this.sitePolicy.resolve(path,this.site.baseUrl));
    if (!/^\/works\/[A-Za-z0-9_-]{1,512}$/.test(address.pathname) || address.search) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP作品标识无效'); }
    return { sourceId: this.id,remoteId: address.pathname.slice(7),locator: address.pathname };
  }
  private check(ref: SourceRef): void { const expected = this.ref(ref.locator); if (ref.sourceId !== this.id || ref.remoteId !== expected.remoteId) { throw new AppError(ErrorCode.RULE_INVALID,'HIP作品标识不符'); } }
  private chapterCheck(ref: SourceRef): string {
    if (ref.sourceId !== this.id || !/^[A-Za-z0-9_-]{1,512}\/[A-Za-z0-9_-]{1,512}$/.test(ref.remoteId)) { throw new AppError(ErrorCode.RULE_INVALID,'HIP章节标识无效'); }
    const hid = ref.remoteId.split('/')[1]; if (ref.locator !== 'https://reader.hipmh.top/chapter/' + hid) { throw new AppError(ErrorCode.RULE_INVALID,'HIP章节地址不符'); } return hid;
  }
  private text(root: HtmlNode,selector: string): string { return this.select.select(root,selector)[0]?.textContent().replace(/\s+/g,' ').trim() || ''; }
  private cover(root: HtmlNode): string | undefined {
    const meta = this.select.select(root,'meta[property="og:image"]')[0]; const img = this.select.select(root,'img')[0];
    const raw = meta ? meta.attribute('content') : img?.attribute('src') || '';
    try { return new UrlPolicy(['cover.s3imgs.top']).resolve(raw,'https://cover.s3imgs.top/'); } catch (_) { return undefined; }
  }
  private async listing(path: string,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    const root = new HtmlExtractor().parse(await this.get(path,ctx)); const items: MangaSummary[] = []; const seen: Set<string> = new Set();
    this.select.select(root,'a[href]').forEach((link: HtmlNode) => {
      if (!link.attribute('href').startsWith('/works/')) { return; } const ref = this.ref(link.attribute('href')); if (seen.has(ref.remoteId)) { return; }
      const image = this.select.select(link,'img')[0]; const title = link.attribute('title') || image?.attribute('alt') || link.textContent().replace(/\s+/g,' ').trim();
      if (!title || title.length > 1024) { return; } seen.add(ref.remoteId); items.push({ ref: ref,title: title,cover: this.cover(link) });
    });
    if (items.length > 500) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'HIP列表超过限额'); } return { items: items };
  }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (!query.trim() || query.length > 70) { throw new AppError(ErrorCode.CONFIG_INVALID,'HIP搜索支持1至70字关键词'); }
    const binding = JSON.stringify([this.id,this.version,this.site.revision,'search',query]);
    let page = 1; let previousTotal = -1; let previousPages = -1; let previousIds: string[] = [];
    if (token) {
      if (token.kind !== 'hip-search' || token.binding !== binding || token.value.length > 16384) { throw new AppError(ErrorCode.RULE_INVALID,'HIP搜索分页已失效'); }
      const cursor = new JsonExtractor().parse(token.value);
      if (cursor.kind !== 'array' || cursor.items.length !== 4 || cursor.items.slice(0,3).some((item: JsonNode) => item.kind !== 'number') || cursor.items[3].kind !== 'array' || cursor.items[3].items.length !== 20) { throw new AppError(ErrorCode.RULE_INVALID,'HIP搜索分页字段无效'); }
      page = Number(cursor.items[0].scalar); previousTotal = Number(cursor.items[1].scalar); previousPages = Number(cursor.items[2].scalar);
      previousIds = cursor.items[3].items.map((item: JsonNode): string => { if (item.kind !== 'string' || !/^[A-Za-z0-9_-]{1,512}$/.test(item.scalar)) { throw new AppError(ErrorCode.RULE_INVALID,'HIP分页作品标识无效'); } return item.scalar; });
      if (!Number.isSafeInteger(page) || page < 2 || page > 100 || !Number.isSafeInteger(previousTotal) || previousTotal < 1 || previousTotal > 100000 || previousPages !== Math.ceil(previousTotal / 20) || page > previousPages) { throw new AppError(ErrorCode.RULE_INVALID,'HIP搜索分页范围无效'); }
    }
    const root = new JsonExtractor().parse(await this.get('https://hipapi1.s3file.top/v1/search?q=' + encodeURIComponent(query) + '&page=' + page.toString() + '&page_size=20',ctx));
    const data = root.members.get('data');
    if (!data || data.kind !== 'object' || ['page','page_size','total','total_pages'].some((key: string) => data.members.get(key)?.kind !== 'number' || !/^(0|[1-9][0-9]{0,8})$/.test(this.value(data,key)))) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP搜索分页数字字段无效'); }
    const list = data.members.get('data'); const total = Number(this.value(data,'total')); const pages = Number(this.value(data,'total_pages'));
    if (this.value(root,'code') !== '200' || !list || list.kind !== 'array' || Number(this.value(data,'page')) !== page || Number(this.value(data,'page_size')) !== 20 || total > 100000 || pages !== Math.ceil(total / 20) && !(total === 0 && pages === 1)) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP搜索接口结构不符'); }
    if (token && (total !== previousTotal || pages !== previousPages)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'HIP搜索结果已变化，请重新搜索'); }
    if (list.items.length !== Math.min(20,Math.max(0,total - (page - 1) * 20))) { throw new AppError(ErrorCode.CONTENT_CHANGED,'HIP搜索分页不完整'); }
    const seen: Set<string> = new Set(); const items = list.items.map((node: JsonNode): MangaSummary => {
      const ref = this.ref('/works/' + this.value(node,'id')); const title = this.value(node,'title');
      if (!title.trim() || title.length > 1024 || seen.has(ref.remoteId) || previousIds.indexOf(ref.remoteId) >= 0) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP搜索作品重复或字段无效'); } seen.add(ref.remoteId);
      const raw = this.value(node,'vertical_image_url') || this.value(node,'cover_image_url'); let cover: string | undefined;
      if (raw) { try { cover = new UrlPolicy(['cover.s3imgs.top']).resolve(raw,'https://cover.s3imgs.top/'); } catch (_) { cover = undefined; } }
      return { ref: ref,title: title,cover: cover };
    });
    return { items: items,next: page < pages && page < 100 ? { kind: 'hip-search',binding: binding,value: JSON.stringify([page + 1,total,pages,items.map((item: MangaSummary) => item.ref.remoteId)]) } : undefined,label: page === 100 && page < pages ? '已达到站点搜索100页上限，请细化关键词' : undefined };
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (query.feed !== 'home' || query.filters.length || token) { throw new AppError(ErrorCode.CONFIG_INVALID,'HIP首页参数不受支持'); }
    const batch = await this.listing('/',ctx); if (!batch.items.length) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'HIP首页未返回作品'); }
    return { items: batch.items.map((item: MangaSummary): SourceBrowseItem => ({ manga: item,subtitle: '' })),filters: [] };
  }
  async details(ref: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    this.check(ref); return this.detailFrom(ref,new HtmlExtractor().parse(await this.get(ref.locator,ctx)));
  }
  private detailFrom(ref: SourceRef,root: HtmlNode): MangaDetail {
    const title = this.text(root,'h1');
    if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP详情结构不符'); }
    return { ref: ref,title: title,authors: [],description: this.select.select(root,'meta[name="description"]')[0]?.attribute('content') || '',tags: [],status: 'unknown',cover: this.cover(root) };
  }
  async chapters(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    this.check(ref); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'HIP目录使用完整分页读取'); }
    return { items: await this.chapterItems(ref,new HtmlExtractor().parse(await this.get(ref.locator,ctx)),ctx) };
  }
  async loadCatalog(ref: SourceRef,ctx: CallContext): Promise<SourceCatalogSnapshot> {
    this.check(ref); const root = new HtmlExtractor().parse(await this.get(ref.locator,ctx));
    return { detail: this.detailFrom(ref,root),chapters: await this.chapterItems(ref,root,ctx) };
  }
  private async chapterItems(ref: SourceRef,root: HtmlNode,ctx: CallContext): Promise<ChapterRef[]> {
    const config = this.select.select(root,'#chapters-config')[0];
    const mid = config?.attribute('data-manga-id') || ''; const expected = Number(config?.attribute('data-total-chapters'));
    if (!/^\d{1,12}$/.test(mid) || !Number.isSafeInteger(expected) || expected < 1 || expected > 10000) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP目录元数据不符'); }
    const items: ChapterRef[] = []; const seen: Set<string> = new Set(); let totalPages = 1;
    for (let page = 1; page <= totalPages; page++) {
      const result = new JsonExtractor().parse(await this.get('https://hipapi1.s3file.top/v1/manga/chapters?mid=' + mid + '&page=' + page.toString() + '&per_page=50&order=asc',ctx));
      const data = result.members.get('data'); const list = data?.members.get('items');
      if (this.value(result,'code') !== '200' || !data || !list || list.kind !== 'array' || list.items.length > 100 || Number(this.value(data,'page')) !== page || Number(this.value(data,'total')) !== expected) { throw new AppError(ErrorCode.CONTENT_CHANGED,'HIP目录分页不完整，请刷新'); }
      const pages = Number(this.value(data,'total_pages')); if (!Number.isInteger(pages) || pages < page || pages > 200 || page > 1 && pages !== totalPages) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP分页总数不符'); } totalPages = pages;
      list.items.forEach((node: JsonNode) => { const hid = this.value(node,'hid'); const title = this.value(node,'title'); if (!/^[A-Za-z0-9_-]{1,512}$/.test(hid) || !title || title.length > 1024 || seen.has(hid)) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP章节重复或字段无效'); } seen.add(hid);
        items.push({ ref: { sourceId: this.id,remoteId: ref.remoteId + '/' + hid,locator: 'https://reader.hipmh.top/chapter/' + hid },mangaRemoteId: ref.remoteId,title: title,ordinal: items.length }); });
    }
    if (items.length !== expected) { throw new AppError(ErrorCode.CONTENT_CHANGED,'HIP章节总数不符，保留旧目录'); } return items;
  }
  async pages(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    const hid = this.chapterCheck(ref); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'HIP图片清单不接受额外分页'); }
    const identity = new HipChapterId().parse(ref.remoteId.split('/')[0],hid);
    const result = new JsonExtractor().parse(await this.get('https://hipapi1.s3file.top/v2/chapter?hid=' + encodeURIComponent(identity.apiHid),ctx)); const data = result.members.get('data'); const images = data?.members.get('images');
    if (this.value(result,'code') !== '200' || !data || !images) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP图片接口结构不符'); }
    if (this.value(data,'manga_id') !== identity.mangaId || this.value(data,'chapter_id') !== identity.chapterId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'HIP图片清单不属于当前作品或章节'); }
    const imageBase = this.value(data,'line') === '9' ? 'https://hip-tx-s1.s3imgs.top/' : 'https://hip-tx-1.s3imgs.top/';
    const policy = new UrlPolicy(HIP_HOSTS.filter((host: string) => host.startsWith('hip-')));
    const addresses = new HipFormat().images(images,this.value(data,'order_id'),this.value(data,'sid')); checkCall(ctx);
    const seen: Set<string> = new Set();
    return { items: addresses.map((raw: string,index: number): PageRef => {
      const address = policy.resolve(raw,imageBase); const key = new url.URL(address).pathname;
      if (key === '/' || seen.has(key)) { throw new AppError(ErrorCode.PARSE_ERROR,'HIP页面路径重复或无效'); } seen.add(key);
      return { pageKey: key,ordinal: index,locator: key,imageUrl: address };
    }) };
  }
  async resolveImage(ref: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    this.chapterCheck(ref); checkCall(ctx); if (refresh) { return this.resolveImage(ref,await refreshPage(this,ref,page.pageKey,ctx),false,ctx); }
    const address = new UrlPolicy(HIP_HOSTS.filter((host: string) => host.startsWith('hip-'))).validate(page.imageUrl || '');
    if (address.pathname !== page.pageKey) { throw new AppError(ErrorCode.CONTENT_CHANGED,'HIP页面标识已变化'); }
    return { url: address.toString(),headers: [{ name: 'Referer',value: 'https://reader.hipmh.top/' }],contentRevision: this.version.toString() + ':' + this.site.revision.toString() };
  }
}
