import { JsonNode } from '../../parsing/JsonExtractor';
import { MangaSummary, MangaDetail, SourceRef, PageRef } from '../../model/SourceTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { UrlPolicy } from '../../network/UrlPolicy';
import { COPY_IMAGE_HOSTS } from './CopySource';
import { COPY_COVER_HOSTS } from '../discovery/CopyDiscovery';

// sy was returned by the 2026-10-28 chapter2 metadata probe; no wildcard CDN trust.
export const COPY_API_IMAGE_HOSTS: string[] = COPY_IMAGE_HOSTS.concat(['sy.mangafunb.fun']);

export function copyValue(node: JsonNode,key: string): string {
  const field = node.members.get(key);
  return field && (field.kind === 'string' || field.kind === 'number') ? field.scalar : '';
}
export function copyObject(node: JsonNode,key: string): JsonNode {
  const field = node.members.get(key);
  if (!field || field.kind !== 'object') { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API缺少对象字段：' + key); }
  return field;
}
export function copyInteger(node: JsonNode,key: string,maximum: number): number {
  const field = node.members.get(key); const value = Number(field?.scalar);
  if (!field || field.kind !== 'number' || !Number.isSafeInteger(value) || value < 0 || value > maximum) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API整数字段无效：' + key); }
  return value;
}
export function copyTitle(node: JsonNode,key: string = 'name'): string {
  const field = node.members.get(key);
  if (!field || field.kind !== 'string' || !field.scalar.trim() || field.scalar.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API标题缺失或无效'); }
  return field.scalar;
}
export function copyManga(id: string): SourceRef {
  if (!/^[a-zA-Z0-9_-]{1,200}$/.test(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY漫画标识无效'); }
  return { sourceId: 'org.hsmihon.copy',remoteId: id,locator: '/comic/' + id };
}
export function copyChapter(manga: string,id: string): SourceRef {
  copyManga(manga);
  if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY章节UUID无效'); }
  return { sourceId: 'org.hsmihon.copy',remoteId: manga + '/' + id,locator: '/comic/' + manga + '/chapter/' + id };
}
export function checkCopyRef(ref: SourceRef,chapter: boolean = false): SourceRef {
  const parts = ref.remoteId.split('/');
  if (ref.sourceId !== 'org.hsmihon.copy' || parts.length !== (chapter ? 2 : 1)) { throw new AppError(ErrorCode.RULE_INVALID,'资源不属于COPY或标识无效'); }
  const expected = chapter ? copyChapter(parts[0],parts[1]) : copyManga(ref.remoteId);
  if (ref.locator !== expected.locator) { throw new AppError(ErrorCode.RULE_INVALID,'COPY资源标识与地址不符'); }
  return expected;
}
export function copySummary(node: JsonNode): MangaSummary {
  const ref = copyManga(copyValue(node,'path_word')); const title = copyTitle(node);
  let cover: string | undefined = undefined;
  const raw = copyValue(node,'cover');
  if (raw) { try { cover = new UrlPolicy(COPY_COVER_HOSTS).validate(raw).toString(); } catch (_) {} }
  return { ref: ref,title: title,cover: cover };
}
function names(node: JsonNode,key: string): string[] {
  const field = node.members.get(key);
  if (!field || field.kind === 'null') { return []; }
  if (field.kind !== 'array' || field.items.length > 200) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API作者或题材字段无效'); }
  return field.items.map((item: JsonNode): string => copyTitle(item));
}
export function copyDetail(results: JsonNode,ref: SourceRef): MangaDetail {
  const comic = copyObject(results,'comic'); const summary = copySummary(comic);
  if (summary.ref.remoteId !== ref.remoteId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'COPY API返回了其他漫画，旧数据保留'); }
  const statusNode = comic.members.get('status'); const status = statusNode?.kind === 'object' ? copyValue(statusNode,'value') : '';
  const description = copyValue(comic,'brief');
  return { ref: summary.ref,title: summary.title,cover: summary.cover,authors: names(comic,'author'),tags: names(comic,'theme'),
    description: description,status: status === '1' ? 'completed' : status === '0' ? 'ongoing' : 'unknown' };
}
interface WeightedPage { page: PageRef; weight: number; }
export function copyPages(results: JsonNode,ref: SourceRef): PageRef[] {
  const chapter = copyObject(results,'chapter'); const parts = ref.remoteId.split('/');
  if (copyValue(chapter,'uuid') !== parts[1] || copyValue(chapter,'comic_path_word') !== parts[0]) { throw new AppError(ErrorCode.CONTENT_CHANGED,'COPY API章节身份不符，拒绝替换旧清单'); }
  const contents = chapter.members.get('contents'); const words = chapter.members.get('words');
  if (!contents || contents.kind !== 'array' || contents.items.length < 1 || contents.items.length > 2000) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'COPY API图片清单为空或超过2000页'); }
  // In live responses count is the group's chapter count; size is this chapter's page count.
  if (chapter.members.has('size') && copyInteger(chapter,'size',2000) !== contents.items.length) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API图片数量不完整'); }
  if (words && words.kind !== 'null' && (words.kind !== 'array' || words.items.length > 0 && words.items.length !== contents.items.length)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API页序权重与图片数量不匹配'); }
  const weighted = words?.kind === 'array' && words.items.length > 0;
  const images = new UrlPolicy(COPY_API_IMAGE_HOSTS); const seenPages: Set<string> = new Set(); const seenWeights: Set<number> = new Set();
  const pages = contents.items.map((item: JsonNode,index: number): WeightedPage => {
    const address = images.validate(copyValue(item,'url'));
    if (seenPages.has(address.pathname)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API包含重复图片身份'); } seenPages.add(address.pathname);
    const word = weighted ? words!.items[index] : undefined; const weight = word ? Number(word.scalar) : index;
    if (word && word.kind !== 'number' || !Number.isSafeInteger(weight) || seenWeights.has(weight)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API页序权重无效或重复'); } seenWeights.add(weight);
    return { page: { pageKey: address.pathname,ordinal: index,locator: address.pathname,imageUrl: address.toString() },weight: weight };
  });
  pages.sort((a: WeightedPage,b: WeightedPage): number => a.weight - b.weight);
  return pages.map((item: WeightedPage,index: number): PageRef => { item.page.ordinal = index; return item.page; });
}
