import { url } from '@kit.ArkTS';
import { SourceDiscovery, SourceFeed, SourceFilter, SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem, PageToken } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { Transport } from '../../network/Transport';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { DiscoveryBase } from './DiscoveryBase';
import { queryBinding, pageNumber, validateBrowse, filterValue, readFilters, uniqueCards, nodeText } from './DiscoverySupport';
import { parseSiteLiteral } from './SiteLiteral';

// Exact cover origins observed in the site's own public home/list pages.
export const COPY_COVER_HOSTS: string[] = ['s0.mangafunb.fun','s3.mangafunb.fun','sa.mangafunb.fun','sb.mangafunb.fun','sc.mangafunb.fun','sd.mangafunb.fun','se.mangafunb.fun','sf.mangafunb.fun','sg.mangafunb.fun','sh.mangafunb.fun','sj.mangafunb.fun','sk.mangafunb.fun','sl.mangafunb.fun','sm.mangafunb.fun','sn.mangafunb.fun','sq.mangafunb.fun','sr.mangafunb.fun','ss.mangafunb.fun','st.mangafunb.fun','sw.mangafunb.fun','sx.mangafunb.fun','sy.mangafunb.fun','sz.mangafunb.fun'];
export class CopyDiscovery extends DiscoveryBase implements SourceDiscovery {
  readonly feeds: SourceFeed[] = [{ id: 'recommended',title: '推荐' },{ id: 'popular',title: '热门' },{ id: 'updates',title: '更新' },{ id: 'latest',title: '新上架' },{ id: 'completed',title: '完结' },{ id: 'rank',title: '排行榜' },{ id: 'category',title: '分类' }];
  private filters: SourceFilter[] = [];
  private rankingFilters: SourceFilter[] = [];
  constructor(site: SourceSiteAccess,transport: Transport) { super('org.hsmihon.copy',site,transport,COPY_COVER_HOSTS); }
  private definitions(): SourceFilter[] {
    return [{ id: 'theme',title: '题材',choices: [{ value: '',title: '全部' }] },{ id: 'region',title: '地区',choices: [{ value: '',title: '全部' }] },
      { id: 'status',title: '状态',choices: [{ value: '',title: '全部' },{ value: '0',title: '连载中' },{ value: '1',title: '已完结' },{ value: '2',title: '短篇' }] },{ id: 'ordering',title: '排序',choices: [{ value: '-datetime_updated',title: '更新优先' },{ value: 'datetime_updated',title: '更新升序' },{ value: '-popular',title: '热门优先' }] }];
  }
  private visibleFilters(feed: string): SourceFilter[] {
    return this.filters.filter((group: SourceFilter) => (feed !== 'completed' || group.id !== 'status') && (feed === 'category' || feed === 'completed' || group.id !== 'ordering'));
  }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    const listed = ['category','popular','updates','completed'].indexOf(query.feed) >= 0;
    validateBrowse(query,this.feeds,listed ? this.visibleFilters(query.feed) : query.feed === 'rank' ? this.rankingFilters : []);
    const binding = queryBinding(this.id,this.site.revision,query); const page = pageNumber(token,binding);
    if (listed) {
      const address = new url.URL('/comics',this.site.baseUrl);
      const ordering = query.feed === 'popular' ? '-popular' : query.feed === 'updates' ? '-datetime_updated' : filterValue(query,'ordering') || '-datetime_updated';
      address.searchParams.set('ordering',ordering); address.searchParams.set('offset',((page - 1) * 50).toString()); address.searchParams.set('limit','50');
      ['theme','region','status'].forEach((key: string) => { const value = query.feed === 'completed' && key === 'status' ? '1' : filterValue(query,key); if (value !== '') { address.searchParams.set(key,value); } });
      const root = await this.document(address.toString(),ctx); const box = this.select.select(root,'.exemptComic-box')[0];
      if (!box) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY分类页面结构变化'); }
      const total = Number(box.attribute('total')); const list = parseSiteLiteral(box.attribute('list'));
      if (!Number.isSafeInteger(total) || total < 0 || list.kind !== 'array' || list.items.length > 50 || (page - 1) * 50 < total && !list.items.length) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY分类分页数量无效'); }
      const items = list.items.map((item): SourceBrowseItem => {
        const title = this.scalar(item,'name'); const ref = this.ref('/comic/' + this.scalar(item,'path_word')); const state = this.scalar(item,'status');
        if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY分类漫画标题无效'); }
        return { manga: { ref: ref,title: title,cover: this.cover(this.scalar(item,'cover')) },subtitle: state === '1' ? '已完结' : state === '0' ? '连载中' : state === '2' ? '短篇' : '' };
      });
      const definitions = this.filters.length ? this.filters : this.definitions(); this.filters = readFilters(root,address.toString(),'/comics',definitions);
      if (this.filters.length < 3) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY分类选项缺失'); }
      return { items: uniqueCards(items),filters: this.visibleFilters(query.feed),next: page * 50 < total ? { kind: 'source-home',value: (page + 1).toString(),binding: binding } : undefined };
    }
    if (token && query.feed !== 'latest') { throw new AppError(ErrorCode.CONFIG_INVALID,'该栏目没有更多分页'); }
    const address = new url.URL(query.feed === 'rank' ? '/rank' : query.feed === 'latest' ? '/newest' : '/',this.site.baseUrl);
    if (query.feed === 'rank') { address.searchParams.set('type',filterValue(query,'type') || 'male'); address.searchParams.set('table',filterValue(query,'table') || 'day'); }
    if (query.feed === 'latest') { address.searchParams.set('offset',((page - 1) * 60).toString()); address.searchParams.set('limit','60'); }
    const root = await this.document(address.toString(),ctx);
    let items: SourceBrowseItem[] = [];
    if (query.feed === 'rank') {
      items = this.copyCards(root,'.ranking-all-box'); items.forEach((item: SourceBrowseItem,index: number) => { item.subtitle = '第 ' + (index + 1).toString() + ' 名'; });
      const definitions: SourceFilter[] = [{ id: 'type',title: '榜单',choices: [{ value: 'male',title: '男频' }] },{ id: 'table',title: '周期',choices: [{ value: 'day',title: '日榜' }] }];
      this.rankingFilters = readFilters(root,address.toString(),'/rank',this.rankingFilters.length ? this.rankingFilters : definitions);
    }
    else if (query.feed === 'latest') { items = this.copyCards(root,'.col-auto'); }
    else {
      const section = this.select.select(root,'.container').find((node) => this.select.select(node,'h4').some((head) => nodeText(head) === '漫畫推薦'));
      if (section) { items = this.copyCards(section,'.col-auto'); }
    }
    items = uniqueCards(items); if (!items.length) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY首页栏目结构变化，可打开网站首页查看'); }
    let next: PageToken | undefined;
    if (query.feed === 'latest' && this.select.select(root,'a[href]').some((node) => {
      try { const target = this.policy.validate(this.policy.resolve(node.attribute('href'),this.site.baseUrl)); return target.pathname === '/newest' && Number(target.searchParams.get('offset')) === page * 60 && target.searchParams.get('limit') === '60'; } catch (_) { return false; }
    })) { next = { kind: 'source-home',value: (page + 1).toString(),binding: binding }; }
    return { items: items,filters: query.feed === 'rank' ? this.rankingFilters : [],next: next };
  }
}
