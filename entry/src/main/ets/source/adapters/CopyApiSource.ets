import { Source, SourceRef, PageToken, SourceBatch, MangaSummary, MangaDetail, ChapterRef, PageRef, ImageRequest } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { JsonNode } from '../../parsing/JsonExtractor';
import { checkCall } from '../SourceHttp';
import { refreshPage } from '../RefreshPage';
import { CopyApiClient } from './CopyApiClient';
import { copyValue, copyObject, copyInteger, copyTitle, copyChapter, checkCopyRef, copySummary, copyDetail, copyPages, COPY_API_IMAGE_HOSTS } from './CopyApiFormat';
import { CopyApiDiscovery } from '../discovery/CopyApiDiscovery';

interface IndexedChapter { chapter: ChapterRef; index: number; }
export class CopyApiSource implements Source {
  readonly id: string = 'org.hsmihon.copy';
  readonly version: number = 2;
  readonly discovery: CopyApiDiscovery;
  private readonly client: CopyApiClient;
  private readonly images: UrlPolicy = new UrlPolicy(COPY_API_IMAGE_HOSTS);
  constructor(site: SourceSiteAccess,transport: Transport) { this.client = new CopyApiClient(site,transport); this.discovery = new CopyApiDiscovery(this.client); }
  async search(query: string,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    if (!query.trim() || query.length > 256) { throw new AppError(ErrorCode.CONFIG_INVALID,'COPY搜索需要输入漫画或作者关键词'); }
    const binding = this.client.binding('search:' + query); const page = token ? Number(token.value) : 1;
    if (token && (token.kind !== 'page' || token.binding !== binding) || !Number.isSafeInteger(page) || page < 1 || page > 10000) { throw new AppError(ErrorCode.RULE_INVALID,'COPY API搜索分页标记无效'); }
    const offset = (page - 1) * 21;
    const result = this.client.list(await this.client.get('/search/comic?limit=21&offset=' + offset.toString() + '&q=' + encodeURIComponent(query) + '&q_type=&_update=true',ctx),offset,21);
    const items = result.list.map((node: JsonNode): MangaSummary => copySummary(node)); const seen: Set<string> = new Set();
    items.forEach((item: MangaSummary) => { if (seen.has(item.ref.remoteId)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API搜索结果重复'); } seen.add(item.ref.remoteId); });
    return { items: items,next: offset + items.length < result.total ? { kind: 'page',value: (page + 1).toString(),binding: binding } : undefined };
  }
  async details(manga: SourceRef,ctx: CallContext): Promise<MangaDetail> {
    const ref = checkCopyRef(manga); return copyDetail(await this.client.get('/comic2/' + ref.remoteId,ctx),ref);
  }
  async chapters(manga: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    const ref = checkCopyRef(manga);
    if (token) { throw new AppError(ErrorCode.RULE_INVALID,'COPY API目录由适配器完整分页，不接受外部分页标记'); }
    const detail = await this.client.get('/comic2/' + ref.remoteId,ctx); copyDetail(detail,ref);
    const groups = copyObject(detail,'groups');
    if (groups.members.size < 1 || groups.members.size > 100) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API章节分组数量无效'); }
    const items: ChapterRef[] = []; const seen: Set<string> = new Set(); const groupIds: Set<string> = new Set();
    const groupList: JsonNode[] = []; groups.members.forEach((group: JsonNode) => groupList.push(group));
    let requests = 0;
    for (let groupIndex = 0; groupIndex < groupList.length; groupIndex++) {
      checkCall(ctx);
      const group = groupList[groupIndex]; const groupId = copyValue(group,'path_word');
      if (!/^[a-zA-Z0-9_-]{1,200}$/.test(groupId) || groupIds.has(groupId)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API章节分组标识无效或重复'); } groupIds.add(groupId);
      const count = copyInteger(group,'count',10000); const name = copyTitle(group);
      if (items.length + count > 10000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'COPY API目录超过10000章'); }
      const collected: IndexedChapter[] = []; const indices: Set<number> = new Set(); let offset = 0;
      do {
        if (++requests > 100) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'COPY API目录超过100批，旧目录保留'); }
        const response = await this.client.get('/comic/' + ref.remoteId + '/group/' + groupId + '/chapters?limit=100&offset=' + offset.toString() + '&_update=true',ctx);
        if (copyInteger(response,'total',10000) !== count) { throw new AppError(ErrorCode.CONTENT_CHANGED,'COPY API分组总数已变化，请重新加载；旧目录保留'); }
        const result = this.client.list(response,offset,100,10000);
        result.list.forEach((node: JsonNode) => {
          const chapter = copyChapter(ref.remoteId,copyValue(node,'uuid')); const index = copyInteger(node,'index',2147483647);
          if (copyValue(node,'comic_path_word') !== ref.remoteId || copyValue(node,'group_path_word') !== groupId || seen.has(chapter.remoteId) || indices.has(index)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API目录身份不符、重复章节或重复序号'); }
          seen.add(chapter.remoteId); indices.add(index); const title = copyTitle(node);
          collected.push({ chapter: { ref: chapter,mangaRemoteId: ref.remoteId,title: groupId === 'default' ? title : '[' + name + '] ' + title,ordinal: 0 },index: index });
        });
        offset += result.list.length;
      } while (offset < count);
      if (collected.length !== count) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API完整目录数量不符，旧目录保留'); }
      // The reader advances by ordinal. Keep groups together and read index in ascending order.
      collected.sort((a: IndexedChapter,b: IndexedChapter): number => a.index - b.index);
      collected.forEach((item: IndexedChapter) => { item.chapter.ordinal = items.length; items.push(item.chapter); });
    }
    if (!items.length) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'COPY API没有返回可确认的完整目录'); }
    return { items: items };
  }
  async pages(chapter: SourceRef,token: PageToken | undefined,ctx: CallContext): Promise<SourceBatch<PageRef>> {
    const ref = checkCopyRef(chapter,true);
    if (token) { throw new AppError(ErrorCode.RULE_INVALID,'COPY API图片清单不接受分页标记'); }
    const parts = ref.remoteId.split('/');
    return { items: copyPages(await this.client.get('/comic/' + parts[0] + '/chapter2/' + parts[1],ctx),ref) };
  }
  async resolveImage(chapter: SourceRef,page: PageRef,refresh: boolean,ctx: CallContext): Promise<ImageRequest> {
    checkCopyRef(chapter,true); checkCall(ctx);
    if (refresh) { return this.resolveImage(chapter,await refreshPage(this,chapter,page.pageKey,ctx),false,ctx); }
    if (!page.imageUrl) { throw new AppError(ErrorCode.RULE_INVALID,'COPY API图片地址缺失'); }
    const address = this.images.validate(page.imageUrl);
    if (address.pathname !== page.pageKey || page.locator !== page.pageKey) { throw new AppError(ErrorCode.RULE_INVALID,'COPY API图片身份与地址不符'); }
    // Preserve source resolution and signed query; image identity stays the full pathname.
    return { url: address.toString(),headers: [{ name: 'Referer',value: this.client.site.baseUrl }],contentRevision: this.client.binding('pages') };
  }
}
