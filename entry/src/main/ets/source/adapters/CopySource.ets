import { url } from '@kit.ArkTS';
import { Source, SourceRef, PageToken, SourceBatch, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { Transport, TransportResponse } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { refreshPage } from '../RefreshPage';
import { CopyFormat } from './CopyFormat';
import { CopyDiscovery, COPY_COVER_HOSTS } from '../discovery/CopyDiscovery';

export const COPY_IMAGE_HOSTS: string[] = ['sn.mangafunb.fun','sc.mangafunb.fun','sz.mangafunb.fun','sj.mangafunb.fun','sd.mangafunb.fun','sl.mangafunb.fun','sq.mangafunb.fun'];
export class CopySource implements Source {
  readonly discovery: CopyDiscovery;
  readonly id: string = 'org.hsmihon.copy'; readonly version: number = 1;
  private readonly site: SourceSiteAccess; private readonly transport: Transport;
  private readonly policy: UrlPolicy; private readonly images: UrlPolicy = new UrlPolicy(COPY_IMAGE_HOSTS);
  private readonly covers: UrlPolicy = new UrlPolicy(COPY_COVER_HOSTS);
  private readonly select: SelectorSubset = new SelectorSubset(); private readonly format: CopyFormat = new CopyFormat();
  private readonly keys: Map<string,string> = new Map();
  constructor(site: SourceSiteAccess,transport: Transport) { this.site = site; this.transport = transport; this.policy = new UrlPolicy(site.allowedHosts); this.discovery = new CopyDiscovery(site,transport); }
  private async request(path: string,ctx: CallContext,accept: string = 'text/html'): Promise<TransportResponse> {
    checkCall(ctx); if (ctx.ruleRevision !== this.version) { throw new AppError(ErrorCode.CONTENT_CHANGED,'COPY适配器版本已改变'); }
    const response = await this.transport.send({ sourceId: this.id,url: this.policy.resolve(path,this.site.baseUrl),maxBytes: 2097152,headers: [{ name: 'Accept',value: accept },{ name: 'Referer',value: this.site.baseUrl }] },ctx);
    requireHttpSuccess(response); checkCall(ctx); return response;
  }
  private value(node: JsonNode,name: string): string { const field = node.members.get(name); return field && (field.kind === 'string' || field.kind === 'number') ? field.scalar : ''; }
  private manga(id: string): SourceRef {
    if (!/^[a-zA-Z0-9_-]{1,200}$/.test(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY漫画标识无效'); }
    return { sourceId: this.id,remoteId: id,locator: '/comic/' + id };
  }
  private chapter(manga: string,id: string): SourceRef {
    this.manga(manga); if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY章节标识无效'); }
    return { sourceId: this.id,remoteId: manga + '/' + id,locator: '/comic/' + manga + '/chapter/' + id };
  }
  private check(ref: SourceRef,chapter: boolean = false): SourceRef {
    if (ref.sourceId !== this.id) { throw new AppError(ErrorCode.RULE_INVALID,'资源不属于COPY源'); }
    const parts = ref.remoteId.split('/'); const expected = chapter ? this.chapter(parts[0],parts[1] || '') : this.manga(ref.remoteId);
    if (ref.locator !== expected.locator) { throw new AppError(ErrorCode.RULE_INVALID,'COPY资源标识与地址不符'); } return expected;
  }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (!query.trim() || query.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'COPY搜索需要输入漫画或作者关键词'); }
    const binding = JSON.stringify([this.id,this.version,this.site.revision,'search',query]); const page = token ? Number(token.value) : 1;
    if (token && (token.kind !== 'page' || token.binding !== binding) || !Number.isSafeInteger(page) || page < 1 || page > 10000) { throw new AppError(ErrorCode.RULE_INVALID,'COPY搜索分页参数无效'); }
    const response = await this.request('/api/kb/web/searchcl/comics?offset=' + ((page - 1) * 12).toString() + '&platform=2&limit=12&q=' + encodeURIComponent(query) + '&q_type=',ctx,'application/json');
    const parser = new JsonExtractor(); const root = parser.parse(response.body); const results = root.members.get('results');
    if (this.value(root,'code') !== '200' || !results || results.kind !== 'object') { throw new AppError(ErrorCode.PARSE_ERROR,'COPY搜索返回结构不符'); }
    const list = results.members.get('list'); const total = Number(this.value(results,'total'));
    if (!list || list.kind !== 'array' || list.items.length > 100 || !Number.isSafeInteger(total) || total < 0) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY搜索分页字段无效'); }
    const items = list.items.map((node: JsonNode): MangaSummary => {
      const ref = this.manga(this.value(node,'path_word')); const title = this.value(node,'name'); if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY搜索标题缺失'); }
      let cover: string | undefined = undefined; try { cover = this.covers.validate(this.value(node,'cover')).toString(); } catch (_) {}
      return { ref: ref,title: title,cover: cover };
    });
    return { items: items,next: page * 12 < total ? { kind: 'page',value: (page + 1).toString(),binding: binding } : undefined };
  }
  private text(root: HtmlNode,selector: string): string { return this.select.select(root,selector)[0]?.textContent().replace(/\s+/g,' ').trim() || ''; }
  async details(manga: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    const ref = this.check(manga); const response = await this.request(ref.locator,ctx); const root = new HtmlExtractor().parse(response.body);
    const title = this.text(root,'.comicParticulars-title-right h6'); if (!title) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY详情页标题缺失或页面不可用'); }
    const key = this.format.literal(response.body,'ccz'); if (this.keys.size >= 32 && !this.keys.has(ref.remoteId)) { this.keys.clear(); } this.keys.set(ref.remoteId,key);
    const authorLinks = this.select.select(root,'.comicParticulars-title-right a[href]').filter((node: HtmlNode) => node.attribute('href').startsWith('/author/'));
    const tags = this.select.select(root,'.comicParticulars-tag a').map((node: HtmlNode) => node.textContent().trim().replace(/^#/,''));
    const image = this.select.select(root,'.comicParticulars-left-img img')[0]; let cover: string | undefined = undefined;
    if (image) { try { cover = this.covers.validate(image.attribute('data-src') || image.attribute('src')).toString(); } catch (_) {} }
    return { ref: ref,title: title,authors: authorLinks.map((node: HtmlNode) => node.textContent().trim()),description: this.text(root,'.comicParticulars-synopsis'),tags: tags,status: 'unknown',cover: cover };
  }
  async chapters(manga: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    const ref = this.check(manga); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'COPY目录不接受额外分页标记'); }
    if (!this.keys.has(ref.remoteId)) { await this.details(ref,ctx); }
    const response = await this.request(ref.locator + '/chapters',ctx,'application/json'); const root = new JsonExtractor().parse(response.body);
    if (this.value(root,'code') !== '200') { throw new AppError(ErrorCode.PARSE_ERROR,'COPY章节接口未返回成功'); }
    const decoded = await this.format.decode(this.value(root,'results'),this.keys.get(ref.remoteId)!); checkCall(ctx);
    const groups = decoded.members.get('groups'); if (!groups || groups.kind !== 'object') { throw new AppError(ErrorCode.PARSE_ERROR,'COPY完整章节分组缺失'); }
    const items: ChapterRef[] = []; const seen: Set<string> = new Set();
    groups.members.forEach((group: JsonNode) => {
      const chapters = group.members.get('chapters'); const count = Number(this.value(group,'count'));
      if (!chapters || chapters.kind !== 'array' || !Number.isSafeInteger(count) || count !== chapters.items.length) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY章节数量不完整，旧目录保留'); }
      chapters.items.forEach((node: JsonNode) => {
        const chapter = this.chapter(ref.remoteId,this.value(node,'id')); if (seen.has(chapter.remoteId)) { return; } seen.add(chapter.remoteId);
        const title = this.value(node,'name'); if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY章节标题无效'); }
        items.push({ ref: chapter,mangaRemoteId: ref.remoteId,title: title,ordinal: items.length }); if (items.length > 10000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'COPY目录超过10000章'); }
      });
    });
    if (items.length === 0) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'COPY未返回可确认的完整章节'); }
    return { items: items };
  }
  async pages(chapter: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    const ref = this.check(chapter,true); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'COPY图片清单不接受额外分页标记'); }
    const response = await this.request(ref.locator,ctx); const decoded = await this.format.decode(this.format.literal(response.body,'contentKey'),this.format.literal(response.body,'cct')); checkCall(ctx);
    if (decoded.kind !== 'array' || decoded.items.length < 1 || decoded.items.length > 2000) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY图像数量为空或超过支持范围'); }
    const items = decoded.items.map((node: JsonNode,index: number): PageRef => {
      const address = this.images.validate(this.value(node,'url')); return { pageKey: address.pathname,ordinal: index,locator: address.pathname,imageUrl: address.toString() };
    });
    return { items: items };
  }
  async resolveImage(chapter: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    this.check(chapter,true); checkCall(ctx);
    if (refresh) { return this.resolveImage(chapter,await refreshPage(this,chapter,page.pageKey,ctx),false,ctx); }
    if (!page.imageUrl || new url.URL(page.imageUrl).pathname !== page.pageKey) { throw new AppError(ErrorCode.RULE_INVALID,'COPY图像标识与地址不符'); }
    return { url: this.images.validate(page.imageUrl).toString(),headers: [{ name: 'Referer',value: this.site.baseUrl }],contentRevision: this.version.toString() + ':' + this.site.revision.toString() };
  }
}
