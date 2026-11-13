import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { MangaDetail, MangaSummary, PageRef, SourceRef } from '../../model/SourceTypes';
import { EHENTAI_BASE, EHENTAI_ID, ehentaiAddress } from '../../network/EhentaiAccess';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';

const GALLERY: RegExp = /^\/g\/([1-9][0-9]{0,14})\/([a-f0-9]{10})\/$/;
const IMAGE_PAGE: RegExp = /^\/s\/([a-f0-9]{10})\/([1-9][0-9]{0,14})-([1-9][0-9]{0,3})$/;
const select: SelectorSubset = new SelectorSubset();

export function ehGalleryKey(ref: SourceRef, chapter: boolean = false): string[] {
  const match = GALLERY.exec(ref.locator);
  if (!match || ref.sourceId !== EHENTAI_ID || ref.remoteId !== (chapter ? match[1] + '/book' : match[1])) {
    throw new AppError(ErrorCode.RULE_INVALID,'E-Hentai 画廊身份与地址不符');
  }
  return [match[1],match[2]];
}

function coverAddress(raw: string): string | undefined {
  if (!raw) { return undefined; }
  try {
    const address = ehentaiAddress(new url.URL(raw,EHENTAI_BASE).toString(),true);
    return /^(?:\/[a-f0-9]{2}\/[a-f0-9]{2}\/|\/w\/)/i.test(address.pathname) ? address.toString() : undefined;
  } catch (_) { return undefined; }
}

function text(node?: HtmlNode): string { return node?.textContent().trim() || ''; }

export function ehList(root: HtmlNode): MangaSummary[] {
  const section = select.select(root,'.itg')[0];
  const items: MangaSummary[] = [];
  const seen: Set<string> = new Set();
  if (section) {
    select.select(section,'a[href] .glink').forEach((name: HtmlNode) => {
      const link = name.parent;
      if (!link || link.tag !== 'a') { return; }
      const address = new url.URL(link.attribute('href'),EHENTAI_BASE);
      const match = GALLERY.exec(address.pathname);
      if (!match || address.origin !== 'https://e-hentai.org' || address.search || address.hash ||
        address.username || address.password || seen.has(match[1])) { return; }
      const title = text(name);
      if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'E-Hentai 列表标题无效'); }
      let card = link;
      while (card.parent && card.parent !== section && card.tag !== 'tr') { card = card.parent; }
      let cover: string | undefined;
      for (const img of select.select(card,'img')) {
        cover = coverAddress(img.attribute('data-src')) || coverAddress(img.attribute('src'));
        if (cover) { break; }
      }
      seen.add(match[1]);
      items.push({ ref: { sourceId: EHENTAI_ID,remoteId: match[1],locator: address.pathname },title: title,cover: cover });
    });
  }
  if (items.length > 100) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'E-Hentai 列表超过限额'); }
  if (!items.length && !select.select(root,'.nop').length && !/\bno hits found\b/i.test(root.textContent())) {
    throw new AppError(ErrorCode.PARSE_ERROR,'E-Hentai 列表结构变化或站点拒绝访问');
  }
  return items;
}

function scalar(node: JsonNode, key: string): string { return node.members.get(key)?.scalar || ''; }

function makeDetail(ref: SourceRef,title: string,category: string,count: string,tags: string[],cover?: string): MangaDetail {
  if (!title || title.length > 1024 || !/^[1-9][0-9]{0,4}$/.test(count) || tags.length > 1024 ||
    tags.some((tag: string) => !tag || tag.length > 256)) {
    throw new AppError(ErrorCode.PARSE_ERROR,'E-Hentai 画廊元数据无效');
  }
  return { ref: ref,title: title,authors: tags.filter((tag: string) => tag.startsWith('artist:')).map((tag: string) => tag.substring(7)),
    description: (category ? category + ' · ' : '') + count + ' 页',tags: tags,cover: cover,status: 'unknown' };
}

export function ehApiDetail(body: string,ref: SourceRef): MangaDetail {
  const key = ehGalleryKey(ref);
  const rows = new JsonExtractor().parse(body).members.get('gmetadata');
  if (rows?.kind !== 'array' || rows.items.length !== 1 || rows.items[0].kind !== 'object') {
    throw new AppError(ErrorCode.PARSE_ERROR,'E-Hentai API 未返回对应画廊元数据');
  }
  const item = rows.items[0];
  if (scalar(item,'gid') !== key[0]) { throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai API 返回了其他画廊'); }
  if (scalar(item,'error')) { throw new AppError(ErrorCode.NOT_FOUND,'E-Hentai 画廊已失效或当前不可访问'); }
  if (scalar(item,'token') !== key[1]) { throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai API 画廊令牌不一致'); }
  const tags = item.members.get('tags');
  if (tags?.kind !== 'array' || tags.items.some((tag: JsonNode) => tag.kind !== 'string')) {
    throw new AppError(ErrorCode.PARSE_ERROR,'E-Hentai API 标签格式无效');
  }
  return makeDetail(ref,scalar(item,'title').trim() || scalar(item,'title_jpn').trim(),scalar(item,'category'),
    scalar(item,'filecount'),tags.items.map((tag: JsonNode) => tag.scalar),coverAddress(scalar(item,'thumb')));
}

export function ehGallerySize(root: HtmlNode): string {
  for (const row of select.select(root,'#gdd tr')) {
    if (text(select.select(row,'.gdt1')[0]) === 'Length:') {
      const match = /^([1-9][0-9]{0,4}) pages?$/i.exec(text(select.select(row,'.gdt2')[0]));
      if (match) { return match[1]; }
    }
  }
  throw new AppError(ErrorCode.PARSE_ERROR,'E-Hentai 画廊页数缺失');
}

export function ehHtmlDetail(root: HtmlNode,ref: SourceRef): MangaDetail {
  const tags: string[] = [];
  for (const row of select.select(root,'#taglist tr')) {
    const prefix = text(select.select(row,'.tc')[0]);
    select.select(row,'a[id]').forEach((node: HtmlNode) => { const label = text(node); if (label && prefix) { tags.push(prefix + label); } });
  }
  const coverNode = select.select(root,'#gd1 div[style]')[0];
  const background = /url\(["']?([^"')]+)["']?\)/.exec(coverNode?.attribute('style') || '');
  return makeDetail(ref,text(select.select(root,'#gn')[0]) || text(select.select(root,'#gj')[0]),
    text(select.select(root,'#gdc')[0]),ehGallerySize(root),tags,coverAddress(background?.[1] || ''));
}

export function ehPageRef(raw: string,gid: string): PageRef {
  const address = ehentaiAddress(new url.URL(raw,EHENTAI_BASE).toString(),false);
  const match = IMAGE_PAGE.exec(address.pathname);
  if (!match || address.search || match[2] !== gid) { throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 图片页与画廊不符'); }
  return { pageKey: gid + '-' + match[3] + ':' + match[1],ordinal: Number(match[3]) - 1,locator: address.pathname };
}

export function ehThumbnailPages(root: HtmlNode,gid: string,offset: number): PageRef[] {
  const pages = select.select(root,'#gdt a[href]').map((link: HtmlNode) => ehPageRef(link.attribute('href'),gid));
  if (!pages.length || pages.some((page: PageRef,index: number) => page.ordinal !== offset + index)) {
    throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 页清单缺页、重复或顺序不符');
  }
  return pages;
}

export function ehNextGalleryBatch(root: HtmlNode,locator: string,index: number): boolean {
  return select.select(root,'.ptt a[href]').some((link: HtmlNode) => {
    const address = new url.URL(link.attribute('href'),EHENTAI_BASE);
    return address.toString() === EHENTAI_BASE + locator.substring(1) + '?p=' + index.toString();
  });
}

export function ehImageAddress(root: HtmlNode): string {
  const images = select.select(root,'img#img[src]');
  if (images.length !== 1) { throw new AppError(ErrorCode.PARSE_ERROR,'E-Hentai 图片页未返回可读图片'); }
  const address = ehentaiAddress(new url.URL(images[0].attribute('src'),EHENTAI_BASE).toString(),true);
  if (/\/(?:509|imglimit)\.gif$/i.test(address.pathname)) {
    throw new AppError(ErrorCode.SOURCE_QUOTA,'E-Hentai 图片配额已用尽，请稍后重试');
  }
  if (address.pathname.startsWith('/om/') && address.pathname.indexOf('/x/0/') >= 0) {
    throw new AppError(ErrorCode.ACCESS_DENIED,'E-Hentai 未向当前客户端提供可读取的图片，请在来源网站查看');
  }
  return address.toString();
}
