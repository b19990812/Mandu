import { url } from '@kit.ArkTS';
import { SourceRef, MangaSummary, MangaDetail, ChapterRef } from '../../model/SourceTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { UrlPolicy } from '../../network/UrlPolicy';
import { decompressLzBase64 } from '../../parsing/LzString';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { firstText, nodeText } from '../discovery/DiscoverySupport';

const select: SelectorSubset = new SelectorSubset();

export function guiManga(mid: string): SourceRef {
  if (!/^[1-9][0-9]{0,18}$/.test(mid)) { throw new AppError(ErrorCode.RULE_INVALID,'漫画柜作品标识无效'); }
  return { sourceId: 'org.hsmihon.manhuagui',remoteId: mid,locator: '/comic/' + mid + '/' };
}
export function guiChapter(mid: string,cid: string): SourceRef {
  guiManga(mid);
  if (!/^[1-9][0-9]{0,18}$/.test(cid)) { throw new AppError(ErrorCode.RULE_INVALID,'漫画柜章节标识无效'); }
  return { sourceId: 'org.hsmihon.manhuagui',remoteId: mid + '/' + cid,locator: '/comic/' + mid + '/' + cid + '.html' };
}
export function checkGuiRef(ref: SourceRef,chapter: boolean = false): void {
  const parts = ref.remoteId.split('/');
  if (ref.sourceId !== 'org.hsmihon.manhuagui' || parts.length !== (chapter ? 2 : 1)) { throw new AppError(ErrorCode.RULE_INVALID,'资源不属于漫画柜'); }
  if ((chapter ? guiChapter(parts[0],parts[1]) : guiManga(parts[0])).locator !== ref.locator) { throw new AppError(ErrorCode.RULE_INVALID,'漫画柜资源身份与地址不符'); }
}
function title(value: string): string {
  const text = value.replace(/\s+/g,' ').trim();
  if (!text || text.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜标题或名称缺失'); } return text;
}
function image(root: HtmlNode,selector: string,base: string): string | undefined {
  const img = select.select(root,selector)[0]; const raw = img ? img.attribute('data-src') || img.attribute('src') : '';
  return raw ? new UrlPolicy([]).resolve(raw,base) : undefined;
}
export function guiHtmlList(root: HtmlNode,base: string,search: boolean): MangaSummary[] {
  const cards = select.select(root,search ? 'div.book-result > ul > li' : 'ul#contList > li');
  if (!cards.length) {
    const empty = firstText(root,'div.book-result');
    if (search && /[没沒]有查找到/.test(empty)) { return []; }
    throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜列表页面结构变化，请检查网站会话');
  }
  if (cards.length > 200) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画柜列表数量超限'); }
  const items: MangaSummary[] = []; const seen: Set<string> = new Set();
  cards.forEach((card: HtmlNode) => {
    const link = select.select(card,search ? 'div.book-detail dl > dt > a' : 'a.bcover')[0];
    if (!link) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜列表作品链接缺失'); }
    const parsed = new url.URL(new UrlPolicy([]).resolve(link.attribute('href'),base));
    const match = /^\/comic\/([1-9][0-9]{0,18})\/$/.exec(parsed.pathname);
    if (!match || parsed.search) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜作品链接格式变化'); }
    const ref = guiManga(match[1]);
    if (seen.has(ref.remoteId)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜列表包含重复作品'); } seen.add(ref.remoteId);
    items.push({ ref: ref,title: title(link.attribute('title') || nodeText(link)),cover: image(card,'a.bcover img',base) });
  });
  return items;
}
function labeledLinks(root: HtmlNode,label: RegExp): string[] {
  const output: string[] = [];
  select.select(root,'ul.detail-list > li > span').filter((span: HtmlNode) => label.test(nodeText(span))).forEach((span: HtmlNode) => {
    select.select(span,'a').forEach((link: HtmlNode) => { const text = title(nodeText(link)); if (output.indexOf(text) < 0) { output.push(text); } });
  });
  if (output.length > 200) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画柜详情字段数量超限'); } return output;
}
export function guiHtmlDetail(root: HtmlNode,ref: SourceRef,base: string): MangaDetail {
  const canonical = select.select(root,'link[rel="canonical"]')[0];
  if (canonical && new url.URL(new UrlPolicy([]).resolve(canonical.attribute('href'),base)).pathname !== ref.locator) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画柜详情指向其他作品'); }
  const status = firstText(root,'ul.detail-list li.status');
  return { ref: ref,title: title(firstText(root,'div.book-title h1')),authors: labeledLinks(root,/漫[画畫]作者[：:]/),
    tags: labeledLinks(root,/漫[画畫][剧劇]情[：:]/),description: firstText(root,'#intro-all') || firstText(root,'#intro-cut'),
    cover: image(root,'p.hcover img',base),status: /已完[结結]/.test(status) ? 'completed' : /[连連][载載]中/.test(status) ? 'ongoing' : 'unknown' };
}
function groupTitle(group: HtmlNode): string {
  const siblings = group.parent?.children || []; const position = siblings.indexOf(group);
  for (let i = position - 1; i >= 0; i--) {
    if (siblings[i].tag === 'h4' || siblings[i].tag === 'h3') { return nodeText(siblings[i]); }
    if (siblings[i].attribute('class').split(/\s+/).indexOf('chapter-list') >= 0) { break; }
  }
  return '';
}
export function guiHtmlChapters(root: HtmlNode,ref: SourceRef,base: string): ChapterRef[] {
  const roots = [root]; const hidden = select.select(root,'input#__VIEWSTATE')[0];
  if (hidden) { roots.push(new HtmlExtractor().parse(decompressLzBase64(hidden.attribute('value')))); }
  const groups: HtmlNode[] = [];
  roots.forEach((document: HtmlNode) => { groups.push(...select.select(document,'div[id]').filter((node: HtmlNode) => node.attribute('id').startsWith('chapter-list-'))); });
  if (groups.length > 100) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画柜目录分组超限'); }
  const items: ChapterRef[] = []; const seen: Map<string,string> = new Map();
  groups.forEach((group: HtmlNode) => {
    const label = groupTitle(group);
    // Each UL is a descending chunk; chunks themselves already follow reading order.
    select.select(group,'ul').forEach((list: HtmlNode) => {
      select.select(list,'li > a.status0').reverse().forEach((link: HtmlNode) => {
        const address = new url.URL(new UrlPolicy([]).resolve(link.attribute('href'),base));
        const match = /^\/comic\/([1-9][0-9]{0,18})\/([1-9][0-9]{0,18})\.html$/.exec(address.pathname);
        if (!match || address.search || match[1] !== ref.remoteId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画柜目录包含其他作品或无效章节'); }
        const chapter = guiChapter(match[1],match[2]); const name = title(link.attribute('title') || firstText(link,'span'));
        if (seen.has(chapter.remoteId)) {
          if (seen.get(chapter.remoteId) !== name) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画柜同一章节出现冲突标题'); } return;
        }
        seen.set(chapter.remoteId,name);
        items.push({ ref: chapter,mangaRemoteId: ref.remoteId,title: groups.length > 1 && label ? '[' + label + '] ' + name : name,ordinal: items.length });
        if (items.length > 10000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画柜目录超过10000章'); }
      });
    });
  });
  if (!items.length) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'漫画柜页面未提供可用目录，旧目录保留'); } return items;
}
