import { SourceDiscovery, SourceFeed, SourceFilter, SourceFilterChoice, SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem, PageToken } from '../../model/SourceTypes';
import { CallContext } from '../../model/RequestTypes';
import { JsonNode } from '../../parsing/JsonExtractor';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { CopyApiClient } from '../adapters/CopyApiClient';
import { copySummary, copyObject, copyValue, copyTitle } from '../adapters/CopyApiFormat';
import { pageNumber, validateBrowse, filterValue } from './DiscoverySupport';

export class CopyApiDiscovery implements SourceDiscovery {
  readonly feeds: SourceFeed[] = [{ id: 'recommended',title: '推荐' },{ id: 'popular',title: '热门' },{ id: 'updates',title: '更新' },{ id: 'latest',title: '新上架' },{ id: 'completed',title: '完结' },{ id: 'rank',title: '排行榜' },{ id: 'category',title: '分类' }];
  private readonly client: CopyApiClient;
  private themes: SourceFilterChoice[] = [{ value: '',title: '全部' }];
  constructor(client: CopyApiClient) { this.client = client; }
  private filters(feed: string): SourceFilter[] {
    if (feed === 'rank') { return [{ id: 'date_type',title: '周期',choices: [{ value: 'day',title: '日榜' },{ value: 'week',title: '周榜' },{ value: 'month',title: '月榜' },{ value: 'total',title: '总榜' }] },
      { id: 'audience_type',title: '榜单',choices: [{ value: 'male',title: '男频' },{ value: 'female',title: '女频' }] }]; }
    if (['category','completed','popular','updates'].indexOf(feed) < 0) { return []; }
    const filters: SourceFilter[] = [{ id: 'theme',title: '题材',choices: this.themes },
      { id: 'free_type',title: '阅读类型',choices: [{ value: '',title: '全部' },{ value: '1',title: '免费' },{ value: '2',title: '付费' }] }];
    if (feed !== 'completed') { filters.push({ id: 'top',title: '地区',choices: [{ value: '',title: '全部' },{ value: 'japan',title: '日本' },{ value: 'korea',title: '韩国' },{ value: 'west',title: '欧美' },{ value: 'finish',title: '已完结' }] }); }
    if (feed === 'category' || feed === 'completed') { filters.push({ id: 'ordering',title: '排序',choices: [{ value: '-datetime_updated',title: '更新优先' },{ value: 'datetime_updated',title: '更新升序' },{ value: '-popular',title: '热门优先' },{ value: 'popular',title: '热度升序' }] }); }
    return filters;
  }
  private async loadThemes(ctx: CallContext): Promise<void> {
    const result = await this.client.get('/theme/comic/count?limit=100',ctx); const list = result.members.get('list');
    if (!list || list.kind !== 'array' || list.items.length > 100) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API题材清单无效'); }
    const seen: Set<string> = new Set();
    const choices = list.items.map((node: JsonNode): SourceFilterChoice => {
      const id = copyValue(node,'path_word');
      if (!/^[a-zA-Z0-9_-]{1,200}$/.test(id) || seen.has(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API题材标识无效或重复'); } seen.add(id);
      return { value: id,title: copyTitle(node) };
    });
    const all: SourceFilterChoice[] = [{ value: '',title: '全部' }];
    this.themes = all.concat(choices);
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (['category','completed','popular','updates'].indexOf(query.feed) >= 0 && this.themes.length === 1) { await this.loadThemes(ctx); }
    const filters = this.filters(query.feed); validateBrowse(query,this.feeds,filters);
    const binding = this.client.binding(JSON.stringify([query.feed,query.filters.slice().sort((a,b) => a.id.localeCompare(b.id))]));
    const page = pageNumber(token,binding); const offset = (page - 1) * 21;
    const wrapped = ['recommended','latest','rank'].indexOf(query.feed) >= 0;
    let path = query.feed === 'recommended' ? '/recs?pos=3200102' : query.feed === 'latest' ? '/update/newest?' : query.feed === 'rank' ? '/ranks?type=1' : '/comics?';
    path += '&limit=21&offset=' + offset.toString();
    if (query.feed === 'rank') { path += '&date_type=' + (filterValue(query,'date_type') || 'day') + '&audience_type=' + (filterValue(query,'audience_type') || 'male'); }
    if (!wrapped) {
      const ordering = query.feed === 'popular' ? '-popular' : query.feed === 'updates' ? '-datetime_updated' : filterValue(query,'ordering') || '-datetime_updated';
      path += '&ordering=' + ordering + '&_update=true';
      ['top','theme','free_type'].forEach((key: string) => {
        const value = query.feed === 'completed' && key === 'top' ? 'finish' : filterValue(query,key);
        if (value) { path += '&' + key + '=' + encodeURIComponent(value); }
      });
    }
    const result = this.client.list(await this.client.get(path,ctx),offset,21); const seen: Set<string> = new Set();
    const items = result.list.map((node: JsonNode,index: number): SourceBrowseItem => {
      const manga = copySummary(wrapped ? copyObject(node,'comic') : node);
      if (seen.has(manga.ref.remoteId)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API栏目返回重复漫画'); } seen.add(manga.ref.remoteId);
      return { manga: manga,subtitle: query.feed === 'rank' ? '第 ' + (offset + index + 1).toString() + ' 名' : '' };
    });
    return { items: items,filters: filters,next: offset + items.length < result.total ? { kind: 'source-home',value: (page + 1).toString(),binding: binding } : undefined };
  }
}
