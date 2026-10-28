import { url } from '@kit.ArkTS';
import { Source, SourceDiscovery, SourceFeed, SourceBrowseQuery, SourceBrowseItem, SourceBrowseBatch, SourceRef, PageToken, SourceBatch, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { refreshPage } from '../RefreshPage';
import { guiHtmlList, guiHtmlDetail, guiHtmlChapters, checkGuiRef } from './ManhuaguiHtmlFormat';
import { manhuaguiPages } from './ManhuaguiReaderData';

const USER_AGENT: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

export class ManhuaguiSource implements Source,SourceDiscovery {
  readonly id: string = 'org.hsmihon.manhuagui'; readonly version: number = 2;
  readonly discovery: SourceDiscovery = this;
  readonly feeds: SourceFeed[] = [{ id: 'popular',title: '热门' },{ id: 'updates',title: '更新' },{ id: 'latest',title: '新上架' },{ id: 'completed',title: '完结' }];
  private readonly site: SourceSiteAccess;
  private readonly transport: Transport;
  private readonly policy: UrlPolicy = new UrlPolicy([]);
  private readonly select: SelectorSubset = new SelectorSubset();
  constructor(site: SourceSiteAccess,transport: Transport) { this.site = site; this.transport = transport; }
  private check(ctx: CallContext): void {
    checkCall(ctx); if (ctx.ruleRevision !== this.version) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画柜适配器已更新，请重新加载'); }
  }
  private binding(operation: string): string { return JSON.stringify([this.id,this.version,this.site.revision,this.site.baseUrl,operation]); }
  private page(token: PageToken | undefined,binding: string): number {
    if (!token) { return 1; } const page = Number(token.value);
    if (token.kind !== 'manhuagui-html-page' || token.binding !== binding || !Number.isSafeInteger(page) || page < 2 || page > 10000) { throw new AppError(ErrorCode.RULE_INVALID,'漫画柜分页标记已失效'); } return page;
  }
  private async read(path: string,ctx: CallContext): Promise<string> {
    this.check(ctx); const address = this.policy.resolve(path,this.site.baseUrl);
    const response = await this.transport.send({ sourceId: this.id,url: address,responseKind: 'metadata',maxBytes: 2097152,
      headers: [{ name: 'Accept',value: 'text/html' },{ name: 'Referer',value: this.site.baseUrl },{ name: 'User-Agent',value: USER_AGENT }] },ctx);
    requireHttpSuccess(response); this.check(ctx);
    if (this.policy.validate(response.finalUrl).pathname !== new url.URL(address).pathname) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画柜跳转到其他页面，请检查网址或网站会话'); }
    return response.body;
  }
  private next(root: HtmlNode,path: string,binding: string,page: number): PageToken | undefined {
    const current = this.select.select(root,'div.pager span.current')[0];
    if (current && Number(current.textContent()) !== page || !current && page > 1) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜分页位置不符'); }
    const links = this.select.select(root,'div.pager a[href]');
    const expected = path.replace(/_p[0-9]+\.html$/,'_p' + (page + 1).toString() + '.html');
    const hasNext = links.some((link: HtmlNode) => {
      const target = this.policy.validate(this.policy.resolve(link.attribute('href'),this.site.baseUrl));
      return target.origin === new url.URL(this.site.baseUrl).origin && target.pathname === expected && !target.search;
    });
    return hasNext ? { kind: 'manhuagui-html-page',value: (page + 1).toString(),binding: binding } : undefined;
  }
  private async list(path: string,search: boolean,binding: string,page: number,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    const root = new HtmlExtractor().parse(await this.read(path,ctx)); const items = guiHtmlList(root,this.site.baseUrl,search);
    return { items: items,next: this.next(root,path,binding,page) };
  }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (!query.trim() || query.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'漫画柜搜索需要1至256字关键词'); }
    const binding = this.binding('search:' + query); const page = this.page(token,binding);
    return this.list('/s/' + encodeURIComponent(query) + '_p' + page.toString() + '.html',true,binding,page,ctx);
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (!this.feeds.some((feed: SourceFeed) => feed.id === query.feed) || query.filters.length) { throw new AppError(ErrorCode.CONFIG_INVALID,'漫画柜栏目参数无效'); }
    const binding = this.binding('browse:' + query.feed); const page = this.page(token,binding);
    const prefix = query.feed === 'updates' ? '/list/update' : query.feed === 'latest' ? '/list/index' : query.feed === 'completed' ? '/list/wanjie/view' : '/list/view';
    const batch = await this.list(prefix + '_p' + page.toString() + '.html',false,binding,page,ctx);
    return { items: batch.items.map((manga: MangaSummary): SourceBrowseItem => { return { manga: manga,subtitle: '' }; }),filters: [],next: batch.next };
  }
  async details(ref: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    checkGuiRef(ref); const root = new HtmlExtractor().parse(await this.read(ref.locator,ctx)); return guiHtmlDetail(root,ref,this.site.baseUrl);
  }
  async chapters(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    checkGuiRef(ref); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'漫画柜目录不接受分页标记'); }
    const root = new HtmlExtractor().parse(await this.read(ref.locator,ctx)); guiHtmlDetail(root,ref,this.site.baseUrl);
    return { items: guiHtmlChapters(root,ref,this.site.baseUrl) };
  }
  async pages(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    checkGuiRef(ref,true); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'漫画柜图片清单不接受分页标记'); }
    return { items: manhuaguiPages(await this.read(ref.locator,ctx),ref) };
  }
  async resolveImage(ref: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    checkGuiRef(ref,true); this.check(ctx);
    if (refresh) { return this.resolveImage(ref,await refreshPage(this,ref,page.pageKey,ctx),false,ctx); }
    if (!page.imageUrl) { throw new AppError(ErrorCode.RULE_INVALID,'漫画柜图片地址缺失'); }
    const address = this.policy.validate(page.imageUrl);
    if (page.pageKey !== address.pathname || page.locator !== page.pageKey) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画柜图片身份与地址不符'); }
    return { url: address.toString(),headers: [{ name: 'Referer',value: this.site.baseUrl },{ name: 'User-Agent',value: USER_AGENT }],contentRevision: this.binding('pages') };
  }
}
