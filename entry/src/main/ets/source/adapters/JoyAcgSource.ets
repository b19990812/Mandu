import { url } from '@kit.ArkTS';
import { Source, SourceDiscovery, SourceFeed, SourceRef, PageToken, SourceBatch, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest, SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { SiteJsonClient } from './SiteJsonClient';
import { refreshPage } from '../RefreshPage';
import { checkCall } from '../SourceHttp';

export const JOY_IMAGE_HOSTS: string[] = ['supercdn.site'];
export const JOY_COVER_HOSTS: string[] = ['i0.wp.com','supercdn.site'];
interface JoyBook { root: HtmlNode; detail: MangaDetail; pages: PageRef[]; }
export class JoyAcgSource implements Source,SourceDiscovery {
  readonly id: string = 'org.hsmihon.joyacg'; readonly version: number = 1;
  readonly discovery: SourceDiscovery = this;
  readonly feeds: SourceFeed[] = [{ id: 'latest',title: '最新漫画' },{ id: 'popular',title: '热门漫画' }];
  private readonly client: SiteJsonClient; private readonly select: SelectorSubset = new SelectorSubset();
  private readonly sites: UrlPolicy; private readonly images: UrlPolicy = new UrlPolicy(JOY_IMAGE_HOSTS); private readonly covers: UrlPolicy = new UrlPolicy(JOY_COVER_HOSTS);
  constructor(site: SourceSiteAccess,transport: Transport) { this.client = new SiteJsonClient(site,transport,this.version); this.sites = new UrlPolicy(site.allowedHosts); }
  private ref(id: string): SourceRef { if (!/^[0-9]{1,10}$/.test(id) || Number(id) < 1) { throw new AppError(ErrorCode.PARSE_ERROR,'JoyACG作品标识无效'); } return { sourceId: this.id,remoteId: id,locator: '/' + id + '/' }; }
  private check(ref: SourceRef,chapter: boolean = false): SourceRef {
    const parts = ref.remoteId.split('/'); const expected = this.ref(parts[0]);
    if (ref.sourceId !== this.id || parts.length !== (chapter ? 2 : 1) || chapter && parts[1] !== 'book' || ref.locator !== expected.locator) { throw new AppError(ErrorCode.RULE_INVALID,'JoyACG作品身份与地址不符'); } return expected;
  }
  private page(token: PageToken | undefined,binding: string): number { const page = token ? Number(token.value) : 1; if (token && (token.kind !== 'joy-page' || token.binding !== binding) || !Number.isSafeInteger(page) || page < 1 || page > 1000) { throw new AppError(ErrorCode.RULE_INVALID,'JoyACG分页标记已失效'); } return page; }
  private cover(raw: string): string | undefined {
    try { const address = this.covers.validate(raw); const path = address.pathname;
      if (!/^\/galleries\/[0-9]+\//.test(path)) {
        const proxy = /^\/([^/]+)\/galleries\/[0-9]+\//.exec(path);
        if (!proxy) { return undefined; }
        this.images.validate('https://' + proxy[1] + '/');
      }
      return address.toString();
    } catch (_) { return undefined; }
  }
  private cards(root: HtmlNode): MangaSummary[] {
    const items: MangaSummary[] = []; const seen: Set<string> = new Set();
    this.select.select(root,'.card a[href]').forEach((link: HtmlNode) => {
      let address: url.URL; try { address = this.sites.validate(this.sites.resolve(link.attribute('href'),this.client.site.baseUrl)); } catch (_) { return; }
      const match = /^\/([0-9]{1,10})\/$/.exec(address.pathname); if (!match || address.search || seen.has(match[1])) { return; }
      const picture = this.select.select(link,'[data-bg]')[0]; const cover = this.cover(picture?.attribute('data-bg') || '');
      // Comic gallery cover paths distinguish comic cards from animation, news and advertisements.
      if (!cover) { return; }
      const title = link.attribute('title').trim(); if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'JoyACG漫画卡片标题无效'); }
      seen.add(match[1]); items.push({ ref: this.ref(match[1]),title: title,cover: cover });
    });
    if (items.length > 100) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'JoyACG列表超过限额'); } return items;
  }
  private hasNext(root: HtmlNode,nextPath: string): boolean {
    return this.select.select(root,'a[href]').some((link: HtmlNode) => { try { const address = this.sites.validate(this.sites.resolve(link.attribute('href'),this.client.site.baseUrl)); return address.pathname === nextPath && !address.search; } catch (_) { return false; } });
  }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (!query.trim() || query.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'JoyACG搜索需要1至256字关键词'); }
    const binding = this.client.binding('search:' + query); const page = this.page(token,binding); const prefix = '/search/' + encodeURIComponent(query) + '/';
    const root = new HtmlExtractor().parse(await this.client.text(prefix + (page > 1 ? 'page/' + page.toString() + '/' : ''),ctx));
    if (!this.select.select(root,'.main-content').length) { throw new AppError(ErrorCode.PARSE_ERROR,'JoyACG搜索页面结构变化'); }
    const items = this.cards(root); const next = this.hasNext(root,prefix + 'page/' + (page + 1).toString() + '/');
    if (next && !items.length) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'JoyACG本页没有可识别漫画，请收窄关键词'); }
    return { items: items,next: next ? { kind: 'joy-page',value: (page + 1).toString(),binding: binding } : undefined };
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (!this.feeds.some((feed: SourceFeed) => feed.id === query.feed) || query.filters.length || query.feed === 'popular' && token) { throw new AppError(ErrorCode.CONFIG_INVALID,'JoyACG栏目参数无效'); }
    const binding = this.client.binding('browse:' + query.feed); const page = this.page(token,binding);
    const path = query.feed === 'popular' ? '/' : '/comic/' + (page > 1 ? 'page/' + page.toString() + '/' : '');
    const root = new HtmlExtractor().parse(await this.client.text(path,ctx)); const section = query.feed === 'popular' ? this.select.select(root,'#hotc')[0] : root;
    if (!section) { throw new AppError(ErrorCode.PARSE_ERROR,'JoyACG漫画栏目缺失'); }
    const items = this.cards(section); if (!items.length) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'JoyACG栏目未返回漫画'); }
    return { items: items.map((manga: MangaSummary): SourceBrowseItem => ({ manga: manga,subtitle: '' })),filters: [],
      next: query.feed === 'latest' && this.hasNext(root,'/comic/page/' + (page + 1).toString() + '/') ? { kind: 'joy-page',value: (page + 1).toString(),binding: binding } : undefined };
  }
  private async book(ref: SourceRef,ctx: CallContext): Promise<JoyBook> {
    this.check(ref); const root = new HtmlExtractor().parse(await this.client.text(ref.locator,ctx));
    const canonical = this.select.select(root,'meta[property="og:url"]')[0]?.attribute('content') || '';
    if (this.sites.validate(canonical).pathname !== ref.locator) { throw new AppError(ErrorCode.CONTENT_CHANGED,'JoyACG返回其他作品'); }
    const title = this.select.select(root,'meta[property="og:title"]')[0]?.attribute('content') || '';
    const labels = this.select.select(root,'.card-body a[href]');
    if (!labels.some((link: HtmlNode) => { try { return this.sites.validate(this.sites.resolve(link.attribute('href'),this.client.site.baseUrl)).pathname === '/comic/'; } catch (_) { return false; } })) { throw new AppError(ErrorCode.UNSUPPORTED,'JoyACG此条目属于非漫画内容'); }
    const countMatch = /頁數[：:]\s*([0-9]{1,4})p/.exec(root.textContent()); const count = Number(countMatch?.[1]);
    const content = this.select.select(root,'#content')[0]; const nodes = content ? this.select.select(content,'img') : [];
    if (!title.trim() || title.length > 1024 || !Number.isSafeInteger(count) || count < 1 || count > 2000 || nodes.length !== count) { throw new AppError(ErrorCode.PARSE_ERROR,'JoyACG标题或整本页数不完整'); }
    let gallery = ''; const seen: Set<string> = new Set();
    const pages = nodes.map((image: HtmlNode,index: number): PageRef => {
      const address = this.images.validate(image.attribute('data-src') || image.attribute('src')); const match = /^\/galleries\/([0-9]+)\/([0-9]+)\.(?:jpe?g|webp|png)$/.exec(address.pathname);
      if (!match || Number(match[2]) !== index + 1 || gallery && gallery !== match[1] || seen.has(address.pathname)) { throw new AppError(ErrorCode.PARSE_ERROR,'JoyACG页序、画廊身份或图片路径不符'); }
      gallery = match[1]; seen.add(address.pathname); return { pageKey: address.pathname,ordinal: index,locator: address.pathname,imageUrl: address.toString() };
    });
    const tags = labels.filter((link: HtmlNode) => link.attribute('href').includes('/tag/')).map((link: HtmlNode) => link.textContent().trim());
    const cover = this.cover(this.select.select(root,'meta[property="og:image"]')[0]?.attribute('content') || '');
    return { root: root,detail: { ref: ref,title: title,cover: cover,authors: [],description: '',tags: tags,status: 'unknown' },pages: pages };
  }
  async details(ref: SourceRef,ctx: CallContext): Promise<MangaDetail> { return (await this.book(this.check(ref),ctx)).detail; }
  async chapters(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    this.check(ref); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'JoyACG整本书不分页目录'); } const book = await this.book(ref,ctx);
    return { items: [{ ref: { sourceId: this.id,remoteId: ref.remoteId + '/book',locator: ref.locator },mangaRemoteId: ref.remoteId,title: '整本 · ' + book.pages.length.toString() + ' 页',ordinal: 0 }] };
  }
  async pages(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> { const manga = this.check(ref,true); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'JoyACG整本页清单不分页'); } return { items: (await this.book(manga,ctx)).pages }; }
  async resolveImage(ref: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    this.check(ref,true); checkCall(ctx); if (refresh) { return this.resolveImage(ref,await refreshPage(this,ref,page.pageKey,ctx),false,ctx); }
    const address = this.images.validate(page.imageUrl || ''); if (address.pathname !== page.pageKey || page.locator !== page.pageKey) { throw new AppError(ErrorCode.CONTENT_CHANGED,'JoyACG页面身份不符'); }
    return { url: address.toString(),headers: [{ name: 'Referer',value: this.client.site.baseUrl }],contentRevision: this.client.binding('pages') };
  }
}
