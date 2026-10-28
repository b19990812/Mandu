import { url } from '@kit.ArkTS';
import { SourceRef, ChapterRef, MangaDetail, SourceBrowseItem, SourceFilter, SourceFilterChoice, PageRef } from '../../model/SourceTypes';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { JsonNode } from '../../parsing/JsonExtractor';
import { UrlPolicy } from '../../network/UrlPolicy';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { parseSiteLiteral } from '../discovery/SiteLiteral';
import { siteNumber, siteScalar } from './SiteJsonClient';

export const MANHUAKU_ASSET_HOSTS: string[] = ['image1.manhuaku.com.cn','us1.manhuaku.com.cn','us2.manhuaku.com.cn'];
const select: SelectorSubset = new SelectorSubset();
const policy: UrlPolicy = new UrlPolicy([]);
export interface ManhuakuDetail { detail: MangaDetail; chapterCount: number; visible: string[]; }
export interface ManhuakuChapter { chapter: ChapterRef; pages: number; path: string; }
export interface ManhuakuList { items: SourceBrowseItem[]; pages: number; filters: SourceFilter[]; }
export function kuManga(id: string): SourceRef {
  if (!/^[1-9][0-9]{0,18}$/.test(id)) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库作品标识无效'); }
  return { sourceId: 'org.hsmihon.manhuaku',remoteId: id,locator: '/comic/' + id + '.html' };
}
export function kuChapter(mid: string,id: string): SourceRef {
  kuManga(mid);
  if (!/^[1-9][0-9]{0,18}$/.test(id)) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库章节标识无效'); }
  return { sourceId: 'org.hsmihon.manhuaku',remoteId: mid + '/' + id,locator: '/chapter/' + mid + '-' + id + '.html' };
}
export function checkKuRef(ref: SourceRef,chapter: boolean = false): string[] {
  const parts = ref.remoteId.split('/');
  if (ref.sourceId !== 'org.hsmihon.manhuaku' || parts.length !== (chapter ? 2 : 1)) { throw new AppError(ErrorCode.RULE_INVALID,'资源不属于漫画库'); }
  const expected = chapter ? kuChapter(parts[0],parts[1]) : kuManga(parts[0]);
  if (expected.locator !== ref.locator) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库资源身份与地址不符'); } return parts;
}
function one(root: HtmlNode,selector: string): HtmlNode {
  const nodes = select.select(root,selector);
  if (nodes.length !== 1) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库页面字段缺失或重复：' + selector); } return nodes[0];
}
function text(root: HtmlNode,selector: string): string { return one(root,selector).textContent().trim(); }
function title(value: string): string {
  if (!value.trim() || value.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库标题缺失或超限'); } return value.trim();
}
function image(node: HtmlNode,site: string): string {
  const style = node.attribute('style'); const match = /background-image\s*:\s*url\(\s*(['"])(.*?)\1\s*\)/i.exec(style);
  if (!match) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库封面地址缺失'); } return policy.resolve(match[2],site);
}
function canonical(root: HtmlNode,locator: string,site: string): void {
  const address = policy.validate(policy.resolve(one(root,'link[rel="canonical"]').attribute('href'),site));
  if (address.pathname !== locator) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库返回了其他作品或章节页面'); }
}
function filterDefinitions(root: HtmlNode,site: string): SourceFilter[] {
  const ids: string[] = ['category','tag','status']; const names: string[] = ['地区','题材','状态'];
  return ids.map((id: string,index: number): SourceFilter => {
    const choices: SourceFilterChoice[] = [{ value: 'all',title: '全部' }]; const seen: Set<string> = new Set();
    select.select(root,'.comic-filter .filter-options a').forEach((link: HtmlNode) => {
      const address = new url.URL(policy.resolve(link.attribute('href'),site)); const value = address.searchParams.get(id);
      if (address.pathname === '/categories' && value && /^[1-9][0-9]{0,8}$/.test(value) && !seen.has(value)) { seen.add(value); choices.push({ value: value,title: title(link.textContent()) }); }
    });
    if (choices.length > 201) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画库筛选项超过200项'); }
    return { id: id,title: names[index],choices: choices };
  }).filter((filter: SourceFilter) => filter.choices.length > 1);
}
export function kuList(html: string,site: string,page: number,updates: boolean = false): ManhuakuList {
  const root = new HtmlExtractor().parse(html); const container = one(root,updates ? '.update-timeline .timeline' : '.catalog');
  const nodes = select.select(container,updates ? 'a.timeline-item' : 'a.book'); const seen: Set<string> = new Set();
  if (nodes.length > 200) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画库单页作品超过200项'); }
  const items = nodes.map((node: HtmlNode): SourceBrowseItem => {
    const address = policy.validate(policy.resolve(node.attribute('href'),site)); const match = /^\/comic\/([1-9][0-9]{0,18})\.html$/.exec(address.pathname);
    if (!match || seen.has(match[1])) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库列表作品身份无效或重复'); } seen.add(match[1]);
    const cover = one(node,updates ? '.mini' : '.thumb');
    return { manga: { ref: kuManga(match[1]),title: title(text(node,'h3')),cover: image(cover,site) },subtitle: updates ? text(node,'time') : cover.attribute('data-title') };
  });
  const pager = select.select(root,'input.pager-input'); let pages = 1;
  if (pager.length === 1) {
    pages = Number(pager[0].attribute('max')); const current = Number(pager[0].attribute('value'));
    if (!Number.isSafeInteger(pages) || pages < 1 || pages > 10000 || current !== page || current > pages) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库分页位置或总页数无效'); }
  } else if (pager.length > 1 || page !== 1 || items.length > 0) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库分页信息缺失'); }
  if (!items.length && pages > 1) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库返回了空的中间分页'); }
  return { items: items,pages: pages,filters: filterDefinitions(root,site) };
}
export function kuDetail(html: string,ref: SourceRef,site: string): ManhuakuDetail {
  checkKuRef(ref); const root = new HtmlExtractor().parse(html); canonical(root,ref.locator,site);
  const profile = one(root,'.comic-profile'); const author = select.select(profile,'.profile-meta p').find((node: HtmlNode) => node.textContent().trim().startsWith('作者：'));
  if (!author) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库作者字段缺失'); }
  const description = one(root,'meta[property="og:description"]').attribute('content'); const count = /^共\s*([0-9]+)\s*话$/.exec(text(root,'#chapterCount'));
  const chapterCount = count ? Number(count[1]) : -1;
  if (!Number.isSafeInteger(chapterCount) || chapterCount < 1 || chapterCount > 10000) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'漫画库目录总数为空或超限'); }
  const visible = select.select(root,'#chaptersList a').map((link: HtmlNode): string => {
    const match = /^\/chapter\/([1-9][0-9]{0,18})-([1-9][0-9]{0,18})\.html$/.exec(new url.URL(policy.resolve(link.attribute('href'),site)).pathname);
    if (!match || match[1] !== ref.remoteId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库网页目录包含其他作品章节'); } return match[2];
  });
  const state = text(profile,'.profile-title span');
  return { detail: { ref: ref,title: title(text(profile,'h1')),authors: [author.textContent().trim().substring(3).trim()],description: description,
    tags: select.select(profile,'.profile-tags a').map((node: HtmlNode) => title(node.textContent())),cover: image(one(profile,'.cover'),site),status: state === '已完结' ? 'completed' : state === '连载中' ? 'ongoing' : 'unknown' },chapterCount: chapterCount,visible: visible };
}
export function kuChapters(data: JsonNode,ref: SourceRef,expected?: ManhuakuDetail): ManhuakuChapter[] {
  checkKuRef(ref); const list = data.members.get('chapters');
  if (list?.kind !== 'array' || list.items.length < 1 || list.items.length > 10000 || expected && expected.chapterCount !== list.items.length) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库完整目录数量不符，旧目录保留'); }
  const seen: Set<string> = new Set();
  const items = list.items.map((node: JsonNode,index: number): ManhuakuChapter => {
    const id = siteScalar(node,'id'); const chapter = kuChapter(ref.remoteId,id);
    if (siteScalar(node,'contentId') !== ref.remoteId || seen.has(id)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库目录身份不符或章节重复'); } seen.add(id);
    const name = title(siteScalar(node,'chapterName')); const pages = siteNumber(node,'chapterNum',2000); const path = siteScalar(node,'chapterPath');
    if (!pages || path.length > 256 || /[\\/\u0000-\u001f?#]/.test(path) || path === '.' || path === '..') { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库章节图片目录或页数无效'); }
    return { chapter: { ref: chapter,mangaRemoteId: ref.remoteId,title: name,ordinal: index },pages: pages,path: path || name };
  });
  if (expected && expected.visible.some((id: string) => !seen.has(id))) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库 API 目录缺少网页已显示章节'); }
  return items;
}
function literal(raw: string): string {
  const value = parseSiteLiteral(raw); if (value.kind !== 'string' || value.scalar.length > 2048) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库图片数据不是字符串字面量'); } return value.scalar;
}
export function kuImageSource(html: string): string {
  const root = new HtmlExtractor().parse(html); const source = one(root,'.source-line-picker').attribute('data-source-id');
  if (!/^[1-9][0-9]{0,18}$/.test(source)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库图片源标识缺失'); } return source;
}
export function kuPages(html: string,ref: SourceRef,chapter: ManhuakuChapter,lines: JsonNode,site: string): PageRef[] {
  const parts = checkKuRef(ref,true); const root = new HtmlExtractor().parse(html); canonical(root,ref.locator,site);
  const mid = /var\s+contentId\s*=\s*'([1-9][0-9]*)'\s*;/.exec(html); const cid = /var\s+chapterId\s*=\s*'([1-9][0-9]*)'\s*;/.exec(html);
  const count = /var\s+totalPages\s*=\s*parseInt\('([0-9]+)'\)\s*;/.exec(html);
  if (!mid || !cid || mid[1] !== parts[0] || cid[1] !== parts[1] || chapter.chapter.ref.remoteId !== ref.remoteId || !count || Number(count[1]) !== chapter.pages) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库章节身份或图片页数不一致'); }
  // Read only the three literal operands from the site's fixed URL template. No eval.
  const expression = /var\s+imgBaseUrl\s*=\s*('(?:\\.|[^'\\])*')\s*\+\s*\(\s*('(?:\\.|[^'\\])*')\s*\|\|\s*('(?:\\.|[^'\\])*')\s*\)\s*\+\s*'\/'\s*;/.exec(html);
  if (!expression) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库图片地址模板已变化'); }
  const base = policy.validate(literal(expression[1])); const chapterPath = literal(expression[2]) || literal(expression[3]);
  if (base.search || !/^\/mh\/[a-zA-Z0-9_-]+\/$/.test(base.pathname) || chapterPath !== chapter.path) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库图片目录与 API 章节路径不符'); }
  const list = lines.members.get('lines');
  if (list?.kind !== 'array' || !list.items.length || list.items.length > 32) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库图片线路清单无效'); }
  const enabled = list.items.filter((line: JsonNode) => line.members.get('enabled')?.scalar === 'true');
  const defaults = enabled.filter((line: JsonNode) => line.members.get('isDefault')?.scalar === 'true');
  if (!enabled.length || defaults.length > 1) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库默认图片线路无效'); }
  const selected = defaults.length ? defaults[0] : enabled[0]; const line = policy.validate(siteScalar(selected,'url'));
  if (line.pathname !== '/' || line.search) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库图片线路必须是 HTTPS 根网址'); }
  const prefix = base.pathname + encodeURIComponent(chapterPath) + '/';
  const pages: PageRef[] = [];
  for (let i = 1; i <= chapter.pages; i++) {
    const address = policy.validate(policy.resolve(prefix + i.toString() + '.webp',line.origin + '/'));
    pages.push({ pageKey: address.pathname,locator: address.pathname,ordinal: i - 1,imageUrl: address.toString() });
  }
  return pages;
}
