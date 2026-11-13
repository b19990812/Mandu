import { url } from '@kit.ArkTS';
import { SourceRef, MangaSummary, MangaDetail, ChapterRef, PageRef } from '../../model/SourceTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { UrlPolicy } from '../../network/UrlPolicy';
import { HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { nodeText, firstText } from '../discovery/DiscoverySupport';

export const MYCOMIC_ASSET_HOSTS: string[] = ['biccam.com'];
const select: SelectorSubset = new SelectorSubset();
const policy: UrlPolicy = new UrlPolicy([]);

function text(value: string): string {
  const result = value.replace(/\s+/g,' ').trim();
  if (!result || result.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC名称缺失或超长'); }
  return result;
}
function id(value: string): string {
  if (!/^[1-9][0-9]{0,18}$/.test(value)) { throw new AppError(ErrorCode.RULE_INVALID,'MYCOMIC资源标识无效'); }
  return value;
}
export function myManga(mid: string): SourceRef {
  return { sourceId: 'org.hsmihon.mycomic',remoteId: id(mid),locator: '/cn/comics/' + mid };
}
export function myChapter(mid: string,cid: string): SourceRef {
  id(mid); id(cid);
  return { sourceId: 'org.hsmihon.mycomic',remoteId: mid + '/' + cid,locator: '/cn/chapters/' + cid };
}
export function checkMyRef(ref: SourceRef,chapter: boolean = false): void {
  const parts = ref.remoteId.split('/');
  if (ref.sourceId !== 'org.hsmihon.mycomic' || parts.length !== (chapter ? 2 : 1) ||
    (chapter ? myChapter(parts[0],parts[1]) : myManga(parts[0])).locator !== ref.locator) {
    throw new AppError(ErrorCode.RULE_INVALID,'MYCOMIC资源身份与地址不符');
  }
}
function meta(root: HtmlNode,name: string): string {
  return select.select(root,'meta[name="' + name + '"]')[0]?.attribute('content') ||
    select.select(root,'meta[property="' + name + '"]')[0]?.attribute('content') || '';
}
function identity(root: HtmlNode,ref: SourceRef,base: string): void {
  const addresses = [meta(root,'og:url'),select.select(root,'link[rel="canonical"]')[0]?.attribute('href') || ''];
  addresses.filter((value: string) => value !== '').forEach((value: string) => {
    const address = policy.validate(policy.resolve(value,base));
    if (address.pathname !== ref.locator || address.search) { throw new AppError(ErrorCode.CONTENT_CHANGED,'MYCOMIC返回了其他资源'); }
  });
}
function image(node: HtmlNode | undefined,base: string): string | undefined {
  const raw = node ? node.attribute('data-src') || node.attribute('src') : '';
  return raw ? policy.resolve(raw,base) : undefined;
}
export function myList(root: HtmlNode,base: string,search: boolean): MangaSummary[] {
  // Scope cards to the catalogue grid; sidebars also contain comic links.
  const grids = select.select(root,'div.grid');
  const cards = select.select(root,'div.grid > div.group');
  if (!grids.length || cards.length > 200) { throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC列表页面结构变化'); }
  if (!cards.length && !search) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'MYCOMIC栏目未返回作品'); }
  const seen: Set<string> = new Set();
  return cards.map((card: HtmlNode): MangaSummary => {
    const link = select.select(card,'a[href]').find((node: HtmlNode) => /\/cn\/comics\/[1-9][0-9]*$/.test(node.attribute('href')));
    const cover = select.select(card,'img')[0];
    const address = policy.validate(policy.resolve(link?.attribute('href') || '',base));
    const match = /^\/cn\/comics\/([1-9][0-9]{0,18})$/.exec(address.pathname);
    if (!link || !cover || !match || address.search || seen.has(match[1])) { throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC列表作品标识缺失或重复'); }
    seen.add(match[1]);
    return { ref: myManga(match[1]),title: text(cover.attribute('alt') || nodeText(link)),cover: image(cover,base) };
  });
}
export function myDetail(root: HtmlNode,ref: SourceRef,base: string): MangaDetail {
  checkMyRef(ref); identity(root,ref,base);
  const card = select.select(root,'div[data-flux-card]')[0];
  if (!card) { throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC作品资料卡缺失'); }
  const title = text((meta(root,'og:title') || firstText(card,'div[data-flux-heading]')).replace(/\s*-\s*MYCOMIC.*$/i,''));
  const tags: string[] = [];
  select.select(card,'a[href]').forEach((link: HtmlNode) => {
    if (!/filter(?:%5[bB]|\[)tag(?:%5[dD]|\])/.test(link.attribute('href'))) { return; }
    const address = policy.validate(policy.resolve(link.attribute('href'),base));
    if (address.pathname === '/cn/comics' && address.searchParams.has('filter[tag]')) {
      const name = text(nodeText(link)); if (tags.indexOf(name) < 0) { tags.push(name); }
    }
  });
  const author = meta(root,'author').trim(); const status = firstText(card,'div[data-flux-badge]');
  const cover = meta(root,'og:image');
  return { ref: ref,title: title,authors: author ? [text(author)] : [],tags: tags,
    description: firstText(card,'div[x-show="show"]') || meta(root,'description'),
    cover: cover ? policy.resolve(cover,base) : image(select.select(card,'img.object-cover')[0],base),
    status: /已完[结結]/.test(status) ? 'completed' : /[连連][载載]中/.test(status) ? 'ongoing' : 'unknown' };
}
function chapterData(raw: string): JsonNode | undefined {
  const match = /\bchapters\s*:\s*\[/.exec(raw);
  if (!match) { return undefined; }
  const begin = match.index + match[0].length - 1;
  let depth = 0; let quoted = false; let escaped = false;
  for (let i = begin; i < raw.length; i++) {
    const char = raw.charAt(i);
    if (quoted) {
      if (char === '"' && !escaped) { quoted = false; }
      escaped = char === '\\' && !escaped; continue;
    }
    if (char === '"') { quoted = true; }
    else if (char === '[') { depth++; }
    else if (char === ']' && --depth === 0) { return new JsonExtractor().parse(raw.substring(begin,i + 1)); }
  }
  throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC章节数据不完整');
}
function readingOrder(items: ChapterRef[]): ChapterRef[] {
  // Infer direction only from monotonic numbered titles, never from remote IDs.
  let previous = -1; let direction = 0;
  for (let i = 0; i < items.length; i++) {
    const match = /^(?:第\s*)?([0-9]+(?:\.[0-9]+)?)\s*[话話回卷章]/.exec(items[i].title);
    if (!match) { continue; }
    const position = Number(match[1]);
    if (previous >= 0 && position !== previous) {
      const step = position > previous ? 1 : -1;
      if (direction !== 0 && direction !== step) { return items; } direction = step;
    }
    previous = position;
  }
  return direction < 0 ? items.reverse() : items;
}
export function myChapters(root: HtmlNode,ref: SourceRef,base: string): ChapterRef[] {
  myDetail(root,ref,base);
  const groups = select.select(root,'div[x-data]').filter((node: HtmlNode) => /\bchapters\s*:/.test(node.attribute('x-data')));
  if (!groups.length || groups.length > 100) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'MYCOMIC未提供可用目录，旧目录保留'); }
  const seen: Set<string> = new Set(); const result: ChapterRef[] = [];
  groups.forEach((group: HtmlNode) => {
    const data = chapterData(group.attribute('x-data'));
    if (!data || data.kind !== 'array' || !data.items.length || data.items.length > 10000) { throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC目录分组为空或无效'); }
    const first = group.children.find((node: HtmlNode) => node.tag === 'div');
    const heading = first?.children.find((node: HtmlNode) => node.tag === 'div');
    const label = heading ? nodeText(heading) : '';
    const items = data.items.map((item: JsonNode): ChapterRef => {
      const cid = item.members.get('id'); const name = item.members.get('title');
      if (item.kind !== 'object' || !cid || ['number','string'].indexOf(cid.kind) < 0 || !name || name.kind !== 'string') { throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC章节字段无效'); }
      const chapter = myChapter(ref.remoteId,cid.scalar);
      if (seen.has(chapter.remoteId)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'MYCOMIC目录出现重复章节'); } seen.add(chapter.remoteId);
      return { ref: chapter,mangaRemoteId: ref.remoteId,title: text(name.scalar),ordinal: 0 };
    });
    readingOrder(items).forEach((chapter: ChapterRef) => {
      if (groups.length > 1 && label && label.length <= 80) { chapter.title = '[' + label + '] ' + chapter.title; }
      chapter.ordinal = result.length; result.push(chapter);
      if (result.length > 10000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'MYCOMIC目录超过10000章'); }
    });
  });
  const card = select.select(root,'div[data-flux-card]')[0]; const declared = card ? /共\s*([0-9]+)\s*[话話章]/.exec(nodeText(card)) : null;
  if (declared && Number(declared[1]) !== result.length) { throw new AppError(ErrorCode.CONTENT_CHANGED,'MYCOMIC目录与声明章节数不符，旧目录保留'); }
  return result;
}
export function myPages(root: HtmlNode,ref: SourceRef,base: string): PageRef[] {
  checkMyRef(ref,true); identity(root,ref,base);
  const manga = myManga(ref.remoteId.split('/')[0]);
  const belongs = select.select(root,'a[data-flux-button]').some((link: HtmlNode) => {
    const address = policy.validate(policy.resolve(link.attribute('href'),base));
    return address.pathname === manga.locator && !address.search;
  });
  if (!belongs) { throw new AppError(ErrorCode.CONTENT_CHANGED,'MYCOMIC阅读页未确认所属作品'); }
  let nodes = select.select(root,'img[x-ref]');
  if (!nodes.length) { nodes = select.select(root,'img.page'); }
  if (!nodes.length || nodes.length > 2000) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'MYCOMIC未提供完整页清单，请检查站点会话'); }
  const seen: Set<string> = new Set();
  return nodes.map((node: HtmlNode,index: number): PageRef => {
    const address = policy.validate(image(node,base) || '');
    if (!address.pathname.startsWith('/chapters/') || address.pathname === '/chapters/' || seen.has(address.pathname)) { throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC图片清单路径缺失或重复'); }
    seen.add(address.pathname);
    return { pageKey: address.pathname,locator: address.pathname,ordinal: index,imageUrl: address.toString() };
  });
}
