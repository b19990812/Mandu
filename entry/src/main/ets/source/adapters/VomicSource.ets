import { url } from '@kit.ArkTS';
import { Source, SourceDiscovery, SourceFeed, SourceFilter, SourceFilterChoice, SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem, SourceRef, PageToken, SourceBatch, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest } from '../../model/SourceTypes';
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
import { VomicFormat } from './VomicFormat';
import { filterValue, validateBrowse } from '../discovery/DiscoverySupport';

export const VOMIC_HOSTS: string[] = ['api.vomicmh.com','cdm.vomicer.com'];
const VOMIC_IMAGES: string[] = ['cdm.vomicer.com'];

export class VomicSource implements Source, SourceDiscovery {
  readonly id: string = 'org.hsmihon.vomic'; readonly version: number = 1;
  readonly discovery: SourceDiscovery = this;
  readonly feeds: SourceFeed[] = [{ id: 'home',title: '首页' },{ id: 'updates',title: '最近更新' },{ id: 'category',title: '分类' },{ id: 'completed',title: '完结' }];
  private categories: SourceFilterChoice[] = [{ value: '',title: '全部' }];
  private readonly site: SourceSiteAccess; private readonly transport: Transport;
  private readonly policy: UrlPolicy; private readonly images: UrlPolicy = new UrlPolicy(VOMIC_IMAGES);
  private readonly select: SelectorSubset = new SelectorSubset();

  constructor(site: SourceSiteAccess,transport: Transport) {
    this.site = site; this.transport = transport; this.policy = new UrlPolicy(site.allowedHosts.concat(VOMIC_HOSTS));
  }
  private async get(path: string,ctx: CallContext): Promise<string> {
    checkCall(ctx);
    if (ctx.ruleRevision !== this.version) { throw new AppError(ErrorCode.CONTENT_CHANGED,'Vomic适配器已改变'); }
    const address = this.policy.resolve(path,this.site.baseUrl);
    const response = await this.transport.send({ sourceId: this.id,url: address,headers: [{ name: 'Referer',value: this.site.baseUrl }],maxBytes: 2097152,responseKind: 'metadata' },ctx);
    requireHttpSuccess(response); checkCall(ctx);
    if (new url.URL(response.finalUrl).pathname !== new url.URL(address).pathname) { throw new AppError(ErrorCode.CONTENT_CHANGED,'Vomic返回了其他页面，请重新登录或刷新'); }
    return response.body;
  }
  private scalar(node: JsonNode,key: string): string {
    const field = node.members.get(key); return field && (field.kind === 'string' || field.kind === 'number') ? field.scalar : '';
  }
  private async api(path: string,ctx: CallContext): Promise<JsonNode> {
    const root = new JsonExtractor().parse(await this.get('https://api.vomicmh.com/pics/c/' + path,ctx));
    const code = this.scalar(root,'code');
    if (code === '401') { throw new AppError(ErrorCode.AUTH_REQUIRED,'Vomic会话已失效，请重新登录'); }
    if (code === '429') { throw new AppError(ErrorCode.RATE_LIMITED,'Vomic请求过于频繁，请稍后重试'); }
    const data = root.members.get('data');
    if (code !== '200' || !data) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic元数据接口结构不符'); }
    return data;
  }
  private manga(id: string): SourceRef {
    if (!/^[1-9][0-9]{0,15}$/.test(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic作品标识无效'); }
    return { sourceId: this.id,remoteId: id,locator: '/detail/' + id };
  }
  private checkManga(ref: SourceRef): void {
    if (ref.sourceId !== this.id || ref.locator !== this.manga(ref.remoteId).locator) { throw new AppError(ErrorCode.RULE_INVALID,'Vomic作品地址与标识不符'); }
  }
  private checkChapter(ref: SourceRef): string[] {
    if (ref.sourceId !== this.id || !/^[1-9][0-9]{0,15}\/[1-9][0-9]{0,15}$/.test(ref.remoteId) || ref.locator !== '/chapter/' + ref.remoteId) { throw new AppError(ErrorCode.RULE_INVALID,'Vomic章节地址与标识不符'); }
    return ref.remoteId.split('/');
  }
  private title(node: JsonNode): string {
    const title = this.scalar(node,'name').trim(); if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic标题字段无效'); } return title;
  }
  private cover(raw: string): string | undefined {
    if (!raw) { return undefined; } try { return this.images.resolve(raw,this.site.baseUrl); } catch (_) { return undefined; }
  }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (!query.trim() || query.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'请输入1至256字搜索关键词'); }
    const binding = JSON.stringify([this.id,this.version,this.site.revision,'search',query]); const page = token ? Number(token.value) : 1;
    if (token && (token.kind !== 'vomic-search' || token.binding !== binding || !/^[1-9][0-9]*$/.test(token.value) || !Number.isSafeInteger(page) || page < 2 || page > 1000)) { throw new AppError(ErrorCode.RULE_INVALID,'Vomic搜索分页已失效'); }
    const data = await this.api('getCartoonList?page=' + page.toString() + '&limit=12&keyword=' + encodeURIComponent(query),ctx);
    if (data.kind !== 'array' || data.items.length > 12) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic搜索分页结构不符'); }
    const seen: Set<string> = new Set();
    const items = data.items.map((node: JsonNode): MangaSummary => {
      const ref = this.manga(this.scalar(node,'id')); if (seen.has(ref.remoteId)) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic搜索结果重复'); } seen.add(ref.remoteId);
      return { ref: ref,title: this.title(node),cover: this.cover(this.scalar(node,'cover')) };
    });
    return { items: items,next: items.length === 12 && page < 1000 ? { kind: 'vomic-search',value: (page + 1).toString(),binding: binding } : undefined };
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (query.feed !== 'home') { return this.browseApi(query,token,ctx); }
    if (query.feed !== 'home' || query.filters.length || token) { throw new AppError(ErrorCode.CONFIG_INVALID,'Vomic首页参数不受支持'); }
    const root = new HtmlExtractor().parse(await this.get('/',ctx)); const seen: Set<string> = new Set(); const items: SourceBrowseItem[] = [];
    this.select.select(root,'a[href]').forEach((link: HtmlNode) => {
      const match = /^\/detail\/([1-9][0-9]{0,15})$/.exec(link.attribute('href')); if (!match || seen.has(match[1])) { return; }
      const image = this.select.select(link,'img')[0]; const title = (link.attribute('title') || image?.attribute('alt') || link.textContent()).replace(/\s+/g,' ').trim();
      if (!title || title.length > 1024) { return; } seen.add(match[1]);
      items.push({ manga: { ref: this.manga(match[1]),title: title,cover: this.cover(image?.attribute('src') || '') },subtitle: '' });
    });
    if (!items.length || items.length > 500) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic首页结构不符'); }
    return { items: items,filters: [] };
  }
  private async browseApi(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (['category','completed'].indexOf(query.feed) >= 0 && this.categories.length === 1) {
      const data = await this.api('getCatList',ctx); const seen: Set<string> = new Set();
      if (data.kind !== 'array' || data.items.length > 200) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic题材清单无效'); }
      const choices = data.items.map((node: JsonNode): SourceFilterChoice => {
        const id = this.scalar(node,'id'); if (!/^[1-9][0-9]{0,8}$/.test(id) || seen.has(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic题材ID无效或重复'); } seen.add(id);
        return { value: id,title: this.title(node) };
      }); const initial: SourceFilterChoice[] = [{ value: '',title: '全部' }]; this.categories = initial.concat(choices);
    }
    const filters: SourceFilter[] = ['category','completed'].indexOf(query.feed) >= 0 ? [{ id: 'cat_id',title: '题材',choices: this.categories }] : [];
    validateBrowse(query,this.feeds,filters);
    const binding = JSON.stringify([this.id,this.version,this.site.revision,'browse',query.feed,query.filters]); const page = token ? Number(token.value) : 1;
    if (token && (token.kind !== 'vomic-browse' || token.binding !== binding) || !Number.isSafeInteger(page) || page < 1 || page > 1000) { throw new AppError(ErrorCode.RULE_INVALID,'Vomic栏目分页已失效'); }
    let path = (query.feed === 'updates' ? 'getUpdateBook' : 'getCartoonList') + '?page=' + page.toString() + '&limit=12';
    const category = filterValue(query,'cat_id'); if (category) { path += '&cat_id=' + category; }
    if (query.feed === 'completed') { path += '&process=' + encodeURIComponent('已完结'); }
    const data = await this.api(path,ctx); if (data.kind !== 'array' || data.items.length > 12) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic栏目分页结构无效'); }
    const seen: Set<string> = new Set(); const items = data.items.map((node: JsonNode): SourceBrowseItem => {
      const ref = this.manga(this.scalar(node,'id')); if (seen.has(ref.remoteId)) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic栏目返回重复漫画'); } seen.add(ref.remoteId);
      if (query.feed === 'completed' && this.scalar(node,'process') !== '已完结') { throw new AppError(ErrorCode.CONTENT_CHANGED,'Vomic完结筛选未被服务端应用'); }
      return { manga: { ref: ref,title: this.title(node),cover: this.cover(this.scalar(node,'cover')) },subtitle: this.scalar(node,'process') };
    });
    return { items: items,filters: filters,next: items.length === 12 && page < 1000 ? { kind: 'vomic-browse',value: (page + 1).toString(),binding: binding } : undefined };
  }
  private async info(ref: SourceRef,ctx: CallContext): Promise<JsonNode> {
    this.checkManga(ref); const node = await this.api('getCartoonInfoV1?car_id=' + ref.remoteId,ctx);
    if (node.kind !== 'object' || this.scalar(node,'id') !== ref.remoteId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'Vomic返回了其他作品的元数据'); } return node;
  }
  async details(ref: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    const data = await this.info(ref,ctx); const author = this.scalar(data,'author'); const process = this.scalar(data,'process');
    return { ref: ref,title: this.title(data),authors: author ? [author] : [],description: this.scalar(data,'intro'),tags: this.scalar(data,'tags').split(/\s+/).filter((tag: string) => tag !== ''),status: process === '已完结' ? 'completed' : process === '连载中' ? 'ongoing' : 'unknown',cover: this.cover(this.scalar(data,'cover')) };
  }
  async chapters(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    if (token) { throw new AppError(ErrorCode.RULE_INVALID,'Vomic目录不接受分页标记'); }
    const data = await this.info(ref,ctx); const groups = data.members.get('chapter_list'); const expected = Number(this.scalar(data,'chapter_num'));
    if (!groups || groups.kind !== 'array' || groups.items.length > 100 || !Number.isSafeInteger(expected) || expected < 1 || expected > 10000) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'Vomic目录为空或结构改变，保留旧目录'); }
    const items: ChapterRef[] = []; const seen: Set<string> = new Set();
    groups.items.forEach((group: JsonNode) => {
      const values = group.members.get('values'); if (!values || values.kind !== 'array') { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic章节分组无效'); }
      const ordered: ChapterRef[] = [];
      values.items.forEach((node: JsonNode) => {
        const id = this.scalar(node,'id'); const sort = this.scalar(node,'sort');
        if (!/^[1-9][0-9]{0,15}$/.test(id) || this.scalar(node,'car_id') !== ref.remoteId || seen.has(id) || !/^[0-9]{1,10}(?:\.[0-9]{1,6})?$/.test(sort)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'Vomic章节重复、顺序或作品身份不符'); }
        seen.add(id); const remote = ref.remoteId + '/' + id;
        ordered.push({ ref: { sourceId: this.id,remoteId: remote,locator: '/chapter/' + remote },mangaRemoteId: ref.remoteId,title: this.title(node),ordinal: Number(sort) });
      });
      ordered.sort((left: ChapterRef,right: ChapterRef) => left.ordinal - right.ordinal || left.ref.remoteId.localeCompare(right.ref.remoteId));
      ordered.forEach((chapter: ChapterRef) => { chapter.ordinal = items.length; items.push(chapter); });
    });
    if (items.length !== expected) { throw new AppError(ErrorCode.CONTENT_CHANGED,'Vomic章节总数不符，保留旧目录'); }
    return { items: items };
  }
  async pages(ref: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    const parts = this.checkChapter(ref); if (token) { throw new AppError(ErrorCode.RULE_INVALID,'Vomic清单不接受分页标记'); }
    const format = new VomicFormat(); const data = format.reader(await this.get(ref.locator,ctx));
    if (this.scalar(data,'id') !== parts[1] || this.scalar(data,'car_id') !== parts[0]) { throw new AppError(ErrorCode.CONTENT_CHANGED,'Vomic清单不属于当前章节'); }
    const images = format.resolve(data.members.get('img_list')); const expected = Number(this.scalar(data,'img_num'));
    if (images.kind !== 'array' || !images.items.length || images.items.length > 2000 || !Number.isSafeInteger(expected) || expected !== images.items.length) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic图片清单为空或不完整'); }
    const seen: Set<string> = new Set(); const items = images.items.map((item: JsonNode,index: number): PageRef => {
      const node = format.resolve(item); const raw = format.resolve(node.members.get('url'));
      if (raw.kind !== 'string' || !raw.scalar) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic页面地址缺失'); }
      const address = this.images.validate(this.images.resolve(raw.scalar,this.site.baseUrl)); const key = address.pathname;
      if (key === '/' || seen.has(key)) { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic页面地址重复或无效'); } seen.add(key);
      return { pageKey: key,ordinal: index,locator: key,imageUrl: address.toString() };
    }); checkCall(ctx); return { items: items };
  }
  async resolveImage(ref: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    this.checkChapter(ref); checkCall(ctx); if (refresh) { return this.resolveImage(ref,await refreshPage(this,ref,page.pageKey,ctx),false,ctx); }
    const address = this.images.validate(page.imageUrl || '');
    if (page.pageKey !== address.pathname || page.locator !== page.pageKey) { throw new AppError(ErrorCode.CONTENT_CHANGED,'Vomic页面标识不符'); }
    return { url: address.toString(),headers: [{ name: 'Referer',value: this.site.baseUrl }],contentRevision: this.version.toString() + ':' + this.site.revision.toString() };
  }
}
