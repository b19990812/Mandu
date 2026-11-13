import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { CallContext } from '../../model/RequestTypes';
import { ChapterRef, ImageRequest, MangaDetail, MangaSummary, PageRef, PageToken, Source, SourceBatch,
  SourceBrowseBatch, SourceBrowseItem, SourceBrowseQuery, SourceCatalog, SourceCatalogSnapshot, SourceDiscovery,
  SourceFeed, SourceRef } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { EHENTAI_API, EHENTAI_BASE, EHENTAI_ID } from '../../network/EhentaiAccess';
import { Transport } from '../../network/Transport';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { ehApiDetail, ehGalleryKey, ehGallerySize, ehHtmlDetail, ehList,
  ehNextGalleryBatch, ehPageRef, ehThumbnailPages } from './EhentaiFormat';

export class EhentaiSource implements Source, SourceDiscovery, SourceCatalog {
  readonly id: string = EHENTAI_ID;
  readonly version: number = 1;
  readonly discovery: SourceDiscovery = this;
  readonly catalog: SourceCatalog = this;
  readonly feeds: SourceFeed[] = [{ id: 'latest',title: '最新画廊' },{ id: 'popular',title: '热门画廊' }];
  private readonly site: SourceSiteAccess;
  private readonly transport: Transport;
  private readonly select: SelectorSubset = new SelectorSubset();

  constructor(site: SourceSiteAccess,transport: Transport) {
    this.site = site;
    this.transport = transport;
  }

  private check(ctx: CallContext): void {
    checkCall(ctx);
    if (this.site.baseUrl !== EHENTAI_BASE) { throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 使用公开站点 e-hentai.org'); }
    if (ctx.ruleRevision !== this.version) { throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 适配器已更新，请重新加载'); }
  }

  private binding(key: string): string { return JSON.stringify([this.id,this.version,this.site.revision,key]); }

  private async html(address: url.URL,ctx: CallContext): Promise<HtmlNode> {
    this.check(ctx);
    const response = await this.transport.send({ sourceId: this.id,url: address.toString(),headers: [
      { name: 'Accept',value: 'text/html' },{ name: 'Referer',value: EHENTAI_BASE }
    ],maxBytes: 2097152,responseKind: 'metadata' },ctx);
    requireHttpSuccess(response);
    checkCall(ctx);
    if (response.finalUrl !== address.toString()) {
      throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 返回了其他画廊、页面或查询');
    }
    if (/this gallery (?:is unavailable|has been removed)|content warning\s*[-–]/i.test(response.body)) {
      throw new AppError(ErrorCode.ACCESS_DENIED,'该 E-Hentai 画廊受限或已移除');
    }
    return new HtmlExtractor().parse(response.body);
  }

  private async list(address: url.URL,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    const binding = this.binding(address.toString());
    if (token) {
      if (address.pathname !== '/' || token.kind !== 'ehentai-next' || token.binding !== binding ||
        !/^[1-9][0-9]{0,14}$/.test(token.value)) {
        throw new AppError(ErrorCode.RULE_INVALID,'E-Hentai 列表游标无效');
      }
      address.searchParams.set('next',token.value);
    }
    const root = await this.html(address,ctx);
    const items = ehList(root);
    const nextLink = this.select.select(root,'a#unext[href]')[0];
    if (!nextLink || address.pathname !== '/') { return { items: items }; }
    const next = new url.URL(nextLink.attribute('href'),EHENTAI_BASE);
    const cursor = next.searchParams.get('next') || '';
    const expected = new url.URL(address.toString());
    expected.searchParams.set('next',cursor);
    if (!items.length || !/^[1-9][0-9]{0,14}$/.test(cursor) || cursor === token?.value ||
      next.origin !== expected.origin || next.pathname !== '/' || next.hash || next.username || next.password ||
      next.searchParams.get('f_search') !== expected.searchParams.get('f_search') ||
      next.searchParams.get('f_cats') !== expected.searchParams.get('f_cats')) {
      throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 下一页与当前列表不符');
    }
    return { items: items,next: { kind: 'ehentai-next',value: cursor,binding: binding } };
  }

  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    const keyword = query.trim();
    if (!keyword || keyword.length > 200) { throw new AppError(ErrorCode.CONFIG_INVALID,'E-Hentai 搜索需要 1 至 200 字关键词'); }
    const address = new url.URL(EHENTAI_BASE);
    address.searchParams.set('f_search',keyword);
    return this.list(address,token,ctx);
  }

  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    const filter = query.filters[0];
    if (query.feed !== 'latest' && query.feed !== 'popular' || query.filters.length > 1 ||
      filter && (query.feed !== 'latest' || filter.id !== 'category' || filter.value !== '' && filter.value !== 'non-h')) {
      throw new AppError(ErrorCode.CONFIG_INVALID,'E-Hentai 栏目或筛选无效');
    }
    const address = new url.URL(query.feed === 'popular' ? 'popular' : '',EHENTAI_BASE);
    if (filter?.value === 'non-h') { address.searchParams.set('f_cats','767'); }
    const batch = await this.list(address,token,ctx);
    return { items: batch.items.map((manga: MangaSummary): SourceBrowseItem => ({ manga: manga,subtitle: '' })),
      next: batch.next,filters: query.feed === 'popular' ? [] :
        [{ id: 'category',title: '分类',choices: [{ value: '',title: '全部' },{ value: 'non-h',title: 'Non-H' }] }] };
  }

  async details(ref: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    this.check(ctx);
    const key = ehGalleryKey(ref);
    try {
      const response = await this.transport.send({ sourceId: this.id,url: EHENTAI_API,method: 'POST',
        galleryMetadata: { gid: key[0],token: key[1] },headers: [{ name: 'Accept',value: 'application/json' }],
        maxBytes: 524288,responseKind: 'metadata' },ctx);
      requireHttpSuccess(response);
      checkCall(ctx);
      if (response.finalUrl !== EHENTAI_API) { throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai API 响应地址无效'); }
      return ehApiDetail(response.body,ref);
    } catch (error) {
      if (!(error instanceof AppError) ||
        [ErrorCode.NETWORK_ERROR,ErrorCode.HTTP_SERVER,ErrorCode.PARSE_ERROR].indexOf(error.code) < 0) { throw error as Error; }
      return ehHtmlDetail(await this.html(new url.URL(ref.locator,EHENTAI_BASE),ctx),ref);
    }
  }

  private chapter(ref: SourceRef): ChapterRef {
    return { ref: { sourceId: this.id,remoteId: ref.remoteId + '/book',locator: ref.locator },
      mangaRemoteId: ref.remoteId,title: '整本',ordinal: 0 };
  }

  async loadCatalog(ref: SourceRef,ctx: CallContext): Promise<SourceCatalogSnapshot> {
    return { detail: await this.details(ref,ctx),chapters: [this.chapter(ref)] };
  }

  async chapters(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    this.check(ctx);
    ehGalleryKey(ref);
    if (token) { throw new AppError(ErrorCode.RULE_INVALID,'E-Hentai 画廊目录只有一个整本章节'); }
    return { items: [this.chapter(ref)] };
  }

  async pages(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    const gid = ehGalleryKey(ref,true)[0];
    const binding = this.binding(ref.locator);
    const parts = token ? /^([1-9][0-9]?):([1-9][0-9]{0,3}):([1-9][0-9]{0,3})$/.exec(token.value) : undefined;
    if (token && (token.kind !== 'ehentai-thumbs' || token.binding !== binding || !parts)) {
      throw new AppError(ErrorCode.RULE_INVALID,'E-Hentai 画廊缩略图分页标记无效');
    }
    const index = parts ? Number(parts[1]) : 0;
    const offset = parts ? Number(parts[2]) : 0;
    const address = new url.URL(ref.locator,EHENTAI_BASE);
    if (index) { address.searchParams.set('p',index.toString()); }
    const root = await this.html(address,ctx);
    const count = Number(ehGallerySize(root));
    if (count > 2000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'E-Hentai 画廊超过阅读器的 2000 页上限'); }
    const items = ehThumbnailPages(root,gid,offset);
    const seen = offset + items.length;
    if (parts && count !== Number(parts[3]) || seen > count || seen < count && !ehNextGalleryBatch(root,ref.locator,index + 1)) {
      throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 画廊页数与分页不一致');
    }
    return { items: items,label: '整本',next: seen === count ? undefined :
      { kind: 'ehentai-thumbs',value: [index + 1,seen,count].join(':'),binding: binding } };
  }

  async resolveImage(ref: SourceRef,page: PageRef,_refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    this.check(ctx);
    const gid = ehGalleryKey(ref,true)[0];
    const expected = ehPageRef(page.locator,gid);
    if (expected.pageKey !== page.pageKey || expected.ordinal !== page.ordinal || expected.locator !== page.locator) {
      throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 图片页身份不一致');
    }
    // Resolve the image in ArkWeb so the URL comes from the same session that reads it.
    const address = new url.URL(expected.locator,EHENTAI_BASE).toString();
    return { url: address,headers: [{ name: 'Referer',value: address }],contentRevision: this.binding(page.pageKey) };
  }
}
