import { url } from '@kit.ArkTS';
import { SourceBrowseItem, SourceBrowseQuery, SourceFeed, SourceFilter, SourceFilterValue, PageToken } from '../../model/SourceTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { UrlPolicy } from '../../network/UrlPolicy';

export function nodeText(node: HtmlNode): string { return node.textContent().replace(/\s+/g,' ').trim(); }
export function firstText(root: HtmlNode,selector: string): string { const node = new SelectorSubset().select(root,selector)[0]; return node ? nodeText(node) : ''; }
export function queryBinding(source: string,revision: number,query: SourceBrowseQuery): string {
  return JSON.stringify([source,revision,query.feed,query.filters.slice().sort((a: SourceFilterValue,b: SourceFilterValue) => a.id.localeCompare(b.id))]);
}
export function pageNumber(token: PageToken | undefined,binding: string): number {
  if (!token) { return 1; }
  const page = Number(token.value);
  if (token.kind !== 'source-home' || token.binding !== binding || !Number.isSafeInteger(page) || page < 2 || page > 10000) { throw new AppError(ErrorCode.CONFIG_INVALID,'首页分页已失效，请重新加载当前栏目'); }
  return page;
}
export function validateBrowse(query: SourceBrowseQuery,feeds: SourceFeed[],filters: SourceFilter[]): void {
  if (!feeds.some((feed: SourceFeed) => feed.id === query.feed) || query.filters.length > 8) { throw new AppError(ErrorCode.CONFIG_INVALID,'该源不支持此栏目'); }
  const seen: Set<string> = new Set();
  query.filters.forEach((selection) => {
    const group = filters.find((item: SourceFilter) => item.id === selection.id);
    if (seen.has(selection.id) || !group || !group.choices.some((choice) => choice.value === selection.value)) { throw new AppError(ErrorCode.CONFIG_INVALID,'筛选条件已变化，请重新加载栏目'); }
    seen.add(selection.id);
  });
}
export function filterValue(query: SourceBrowseQuery,id: string): string { return query.filters.find((item) => item.id === id)?.value || ''; }
export function readFilters(root: HtmlNode,base: string,path: string,definitions: SourceFilter[]): SourceFilter[] {
  const links = new SelectorSubset().select(root,'a[href]');
  const current = new url.URL(base);
  const policy = new UrlPolicy([]);
  return definitions.map((definition: SourceFilter): SourceFilter => {
    const choices = definition.choices.slice();
    links.forEach((link: HtmlNode) => {
      let parsed: url.URL;
      try { parsed = policy.validate(new url.URL(link.attribute('href'),base).toString()); } catch (_) { return; }
      if (parsed.pathname !== path) { return; }
      if (definitions.some((other: SourceFilter) => other.id !== definition.id &&
        (parsed.searchParams.get(other.id) || other.choices[0].value) !== (current.searchParams.get(other.id) || other.choices[0].value))) { return; }
      const value = parsed.searchParams.get(definition.id); const title = nodeText(link);
      if (value && /^[a-zA-Z0-9_-]{1,80}$/.test(value) && title && title.length <= 40 && !choices.some((choice) => choice.value === value)) { choices.push({ value: value,title: title }); }
    });
    return { id: definition.id,title: definition.title,choices: choices };
  }).filter((group: SourceFilter) => group.choices.length > 1);
}
export function uniqueCards(items: SourceBrowseItem[]): SourceBrowseItem[] {
  const seen: Set<string> = new Set();
  return items.filter((item: SourceBrowseItem) => { if (seen.has(item.manga.ref.remoteId)) { return false; } seen.add(item.manga.ref.remoteId); return true; });
}
export function discoveryColumns(width: number): number { return Number.isFinite(width) ? Math.max(2,Math.min(8,Math.floor((width + 12) / 144))) : 2; }
