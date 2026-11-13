import { url } from '@kit.ArkTS';
import { Source, MangaSummary, MangaDetail, ChapterRef, PageToken, SourceBatch, SourceRef } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { BaoziChapterSource, baoziPageHosts } from './BaoziChapterSource';
import { BaoziDiscovery } from '../discovery/BaoziDiscovery';
import { SourceCatalog, SourceCatalogSnapshot } from '../../model/SourceTypes';

export const BAOZI_COVER_HOSTS: string[] = ['static-tw.baozimh.com'];
export class BaoziSource extends BaoziChapterSource implements Source {
  readonly discovery: BaoziDiscovery;
  readonly catalog: SourceCatalog = this;
  private readonly currentSite: SourceSiteAccess;
  private readonly http: Transport;
  private readonly policy: UrlPolicy;
  private readonly coverPolicy: UrlPolicy;
  private readonly select: SelectorSubset = new SelectorSubset();
  constructor(site: SourceSiteAccess,transport: Transport) {
    super(site,transport); this.currentSite = site; this.http = transport; this.policy = new UrlPolicy(baoziPageHosts(site)); this.coverPolicy = new UrlPolicy(BAOZI_COVER_HOSTS); this.discovery = new BaoziDiscovery(site,transport,BAOZI_COVER_HOSTS);
  }
  private text(root: HtmlNode,selector: string,required: boolean = false): string {
    const value = this.select.select(root,selector)[0]?.textContent().replace(/\s+/g,' ').trim() || '';
    if (required && !value) { throw new AppError(ErrorCode.PARSE_ERROR,'包子页面缺少必要字段'); } return value;
  }
  private async document(path: string,ctx: CallContext): Promise<HtmlNode> {
    checkCall(ctx); const response = await this.http.send({ sourceId: this.id,url: this.policy.resolve(path,this.currentSite.baseUrl),headers: [{ name: 'Accept',value: 'text/html' },{ name: 'Referer',value: this.currentSite.baseUrl }],maxBytes: 2097152 },ctx);
    requireHttpSuccess(response); checkCall(ctx); return new HtmlExtractor().parse(response.body);
  }
  private mangaRef(path: string): SourceRef {
    const parsed = this.policy.validate(this.policy.resolve(path,this.currentSite.baseUrl));
    if (!/^\/comic\/[a-zA-Z0-9_-]{1,256}$/.test(parsed.pathname)) { throw new AppError(ErrorCode.PARSE_ERROR,'包子漫画标识格式不受支持'); }
    return { sourceId: this.id,remoteId: parsed.pathname.substring(7),locator: parsed.pathname };
  }
  private cover(root: HtmlNode): string | undefined {
    const node = this.select.select(root,'amp-img[src]')[0]; if (!node) { return undefined; }
    try { return this.coverPolicy.validate(node.attribute('src')).toString(); } catch (_) { return undefined; }
  }
  private canonical(root: HtmlNode,manga: SourceRef): SourceRef {
    const link = this.select.select(root,'link[rel="canonical"]')[0];
    if (!link) { return manga; }
    const canonical = this.mangaRef(link.attribute('href'));
    if (canonical.remoteId !== manga.remoteId && !(canonical.remoteId.startsWith(manga.remoteId + '_') && /^[a-z0-9]{6}$/.test(canonical.remoteId.substring(manga.remoteId.length + 1)))) {
      throw new AppError(ErrorCode.CONTENT_CHANGED,'包子详情指向了其他漫画');
    }
    return canonical;
  }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (query.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'搜索关键词过长'); }
    const binding = JSON.stringify([this.id,this.version,this.currentSite.revision,'search',query]);
    if (token && (token.kind !== 'url' || token.binding !== binding)) { throw new AppError(ErrorCode.RULE_INVALID,'包子搜索分页标记不匹配'); }
    const path = token ? token.value : query ? '/search?q=' + encodeURIComponent(query) : '/';
    const root = await this.document(path,ctx); const cards = this.select.select(root,'div.comics-card'); const items: MangaSummary[] = [];
    cards.forEach((card: HtmlNode) => {
      const link = this.select.select(card,'a.comics-card__poster')[0]; if (!link) { return; }
      const ref = this.mangaRef(link.attribute('href')); const title = link.attribute('title') || this.text(card,'h3');
      if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'包子搜索标题无效'); }
      if (!items.some((item: MangaSummary) => item.ref.remoteId === ref.remoteId)) { items.push({ ref: ref,title: title,cover: this.cover(card) }); }
    });
    if (cards.length === 0 && (!query || this.select.select(root,'div.l-content.search').length === 0)) { throw new AppError(ErrorCode.PARSE_ERROR,'包子搜索页面结构不符'); }
    const next = this.select.select(root,'a[rel="next"]')[0];
    return { items: items,next: next ? { kind: 'url',value: this.policy.resolve(next.attribute('href'),this.currentSite.baseUrl),binding: binding } : undefined };
  }
  async details(manga: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    if (manga.sourceId !== this.id) { throw new AppError(ErrorCode.RULE_INVALID,'漫画不属于包子源'); }
    const ref = this.mangaRef(manga.locator); if (ref.remoteId !== manga.remoteId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画地址与标识不一致'); }
    return this.detailFrom(await this.document(ref.locator,ctx),ref);
  }
  private detailFrom(root: HtmlNode,ref: SourceRef): MangaDetail {
    this.canonical(root,ref); const author = this.text(root,'h2.comics-detail__author');
    return { ref: ref,title: this.text(root,'h1.comics-detail__title',true),description: this.text(root,'p.comics-detail__desc'),authors: author ? [author] : [],tags: [],status: 'unknown',cover: this.cover(this.select.select(root,'div.comics-detail')[0] || root) };
  }
  async chapters(manga: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    if (token || manga.sourceId !== this.id) { throw new AppError(ErrorCode.RULE_INVALID,'包子目录参数无效'); }
    const ref = this.mangaRef(manga.locator); if (ref.remoteId !== manga.remoteId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'包子漫画身份与目录地址不一致'); }
    return { items: this.chaptersFrom(await this.document(ref.locator,ctx),manga) };
  }
  async loadCatalog(manga: SourceRef,ctx: CallContext): Promise<SourceCatalogSnapshot> {
    if (manga.sourceId !== this.id) { throw new AppError(ErrorCode.RULE_INVALID,'漫画不属于包子源'); }
    const ref = this.mangaRef(manga.locator); if (ref.remoteId !== manga.remoteId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'包子漫画身份与目录地址不一致'); }
    const root = await this.document(ref.locator,ctx); return { detail: this.detailFrom(root,ref),chapters: this.chaptersFrom(root,manga) };
  }
  private chaptersFrom(root: HtmlNode,manga: SourceRef): ChapterRef[] {
    const canonical = this.canonical(root,manga); const links = this.select.select(root,'a.comics-chapters__item');
    if (links.length === 0) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'包子目录未返回章节，旧目录保留'); }
    const items: ChapterRef[] = [];
    links.forEach((link: HtmlNode) => {
      const target = new url.URL(this.policy.resolve(link.attribute('href'),this.currentSite.baseUrl));
      const comic = target.searchParams.get('comic_id') || ''; const section = target.searchParams.get('section_slot') || ''; const slot = target.searchParams.get('chapter_slot') || '';
      if ([manga.remoteId,canonical.remoteId].indexOf(comic) < 0 || !/^[0-9]{1,5}$/.test(section) || !/^[0-9]{1,6}$/.test(slot)) { throw new AppError(ErrorCode.PARSE_ERROR,'包子章节字段与漫画不匹配'); }
      const ref = this.chapter('/comic/chapter/' + canonical.remoteId + '/' + section + '_' + slot + '.html');
      if (!items.some((item: ChapterRef) => item.ref.remoteId === ref.remoteId)) { items.push({ ref: ref,mangaRemoteId: manga.remoteId,title: link.textContent().replace(/\s+/g,' ').trim(),ordinal: Number(section) * 1000000 + Number(slot) }); }
    });
    if (items.length > 10000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'包子目录超过10000章'); }
    return items;
  }
}
