import { Source, SourceDiscovery, SourceFeed, SourceBrowseQuery, SourceBrowseBatch, SourceRef, PageToken, SourceBatch, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { checkCall } from '../SourceHttp';
import { refreshPage } from '../RefreshPage';
import { ManhuakuClient } from './ManhuakuClient';
import { kuList, kuDetail, kuChapters, kuPages, kuManga, checkKuRef, kuImageSource } from './ManhuakuFormat';

export class ManhuakuSource implements Source,SourceDiscovery {
  readonly id: string = 'org.hsmihon.manhuaku'; readonly version: number = 1;
  readonly discovery: SourceDiscovery = this;
  readonly feeds: SourceFeed[] = [{ id: 'category',title: '分类' },{ id: 'updates',title: '更新' },{ id: 'completed',title: '完结' }];
  private readonly client: ManhuakuClient;
  constructor(site: SourceSiteAccess,transport: Transport) { this.client = new ManhuakuClient(site,transport); }
  private page(token: PageToken | undefined,binding: string): number {
    const page = token ? Number(token.value) : 1;
    if (token && (token.kind !== 'manhuaku-page' || token.binding !== binding) || !Number.isSafeInteger(page) || page < 1 || page > 10000) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库分页标记已失效'); } return page;
  }
  private next(page: number,total: number,binding: string): PageToken | undefined { return page < total ? { kind: 'manhuaku-page',value: (page + 1).toString(),binding: binding } : undefined; }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (!query.trim() || query.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'漫画库搜索需要1至256字关键词'); }
    const binding = this.client.binding('search:' + query); const page = this.page(token,binding);
    const result = kuList(await this.client.text('/search?query=' + encodeURIComponent(query) + '&page=' + page.toString(),ctx),this.client.site.baseUrl,page);
    return { items: result.items.map((item) => item.manga),next: this.next(page,result.pages,binding) };
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (!this.feeds.some((feed: SourceFeed) => feed.id === query.feed) || query.feed === 'updates' && query.filters.length) { throw new AppError(ErrorCode.CONFIG_INVALID,'漫画库栏目参数无效'); }
    const filters: Map<string,string> = new Map();
    query.filters.forEach((filter) => {
      if (['category','tag','status'].indexOf(filter.id) < 0 || filters.has(filter.id) || filter.value !== 'all' && !/^[1-9][0-9]{0,8}$/.test(filter.value) || query.feed === 'completed' && filter.id === 'status') { throw new AppError(ErrorCode.CONFIG_INVALID,'漫画库筛选参数无效'); } filters.set(filter.id,filter.value);
    });
    let path = query.feed === 'updates' ? '/updates?' : '/categories?';
    ['category','tag','status'].forEach((id: string) => { const value = filters.get(id); if (value && value !== 'all') { path += id + '=' + value + '&'; } });
    if (query.feed === 'completed') { path += 'status=2&'; }
    const binding = this.client.binding('browse:' + path); const page = this.page(token,binding);
    const result = kuList(await this.client.text(path + 'page=' + page.toString(),ctx),this.client.site.baseUrl,page,query.feed === 'updates');
    return { items: result.items,filters: result.filters.filter((filter) => query.feed !== 'completed' || filter.id !== 'status'),next: this.next(page,result.pages,binding) };
  }
  async details(ref: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    checkKuRef(ref); return kuDetail(await this.client.text(ref.locator,ctx),ref,this.client.site.baseUrl).detail;
  }
  async chapters(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    checkKuRef(ref); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库目录由 API 一次完整读取'); }
    const detail = kuDetail(await this.client.text(ref.locator,ctx),ref,this.client.site.baseUrl);
    return { items: kuChapters(await this.client.data('/comic/' + ref.remoteId,true,ctx),ref,detail).map((item) => item.chapter) };
  }
  async pages(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    const parts = checkKuRef(ref,true); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库图片清单不接受分页标记'); }
    const chapters = kuChapters(await this.client.data('/comic/' + parts[0],true,ctx),kuManga(parts[0]));
    const chapter = chapters.find((item) => item.chapter.ref.remoteId === ref.remoteId);
    if (!chapter) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库目录中已没有该章节'); }
    const html = await this.client.text(ref.locator,ctx);
    const lines = await this.client.data('/api/source-lines/' + kuImageSource(html),false,ctx);
    return { items: kuPages(html,ref,chapter,lines,this.client.site.baseUrl) };
  }
  async resolveImage(ref: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    checkKuRef(ref,true); checkCall(ctx);
    if (refresh) { return this.resolveImage(ref,await refreshPage(this,ref,page.pageKey,ctx),false,ctx); }
    if (!page.imageUrl) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库图片地址缺失'); }
    const address = new UrlPolicy([]).validate(page.imageUrl);
    if (page.pageKey !== address.pathname || page.locator !== page.pageKey || !/^\/mh\/[^/]+\/[^/]+\/[1-9][0-9]*\.webp$/.test(address.pathname)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库图片身份与地址不符'); }
    return { url: address.toString(),headers: [{ name: 'Referer',value: this.client.site.baseUrl }],contentRevision: this.client.binding('pages') };
  }
}
