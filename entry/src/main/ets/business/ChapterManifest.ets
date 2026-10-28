import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { ChapterPageSource, PageRef, PageToken, SourceRef, SourceBatch } from '../model/SourceTypes';
import { checkCall } from '../source/SourceHttp';

export interface ChapterManifest { chapter: SourceRef; label: string; pages: PageRef[]; }

export async function collectChapterManifest(source: ChapterPageSource, chapter: SourceRef,
  ctx: CallContext): Promise<ChapterManifest> {
  const pages: PageRef[] = [];
  const existing: Map<string, PageRef> = new Map();
  const tokens: Set<string> = new Set();
  let token: PageToken | undefined = undefined;
  let label = '';
  for (let batchIndex = 0; batchIndex < 100; batchIndex++) {
    checkCall(ctx);
    const batch: SourceBatch<PageRef> = await source.pages(chapter, token, ctx);
    if (batchIndex === 0) { label = batch.label || chapter.remoteId; }
    const before = pages.length;
    batch.items.forEach((page: PageRef) => {
      if (!page.pageKey || page.pageKey.length > 2048 || page.locator.length > 8192 || page.imageUrl && page.imageUrl.length > 8192) {
        throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '图像标识或地址超过限额');
      }
      const previous = existing.get(page.pageKey);
      if (previous && previous.imageUrl !== page.imageUrl) {
        throw new AppError(ErrorCode.CONTENT_CHANGED, '同一图像标识返回了不同资源');
      }
      if (!previous) {
        const item: PageRef = { pageKey: page.pageKey, ordinal: pages.length, locator: page.locator,
          imageUrl: page.imageUrl, width: page.width, height: page.height };
        existing.set(item.pageKey, item); pages.push(item);
      }
      if (pages.length > 2000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '章节图像数量超过2000'); }
    });
    if (!batch.next) {
      if (pages.length === 0) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED, '章节没有可读取的图像'); }
      return { chapter: chapter, label: label, pages: pages };
    }
    const key = JSON.stringify([batch.next.kind, batch.next.value, batch.next.binding]);
    if (tokens.has(key) || before === pages.length) { throw new AppError(ErrorCode.PARSE_ERROR, '章节分页重复或没有前进'); }
    tokens.add(key);
    token = batch.next;
  }
  throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '章节分页超过100批，未提交不完整清单');
}
