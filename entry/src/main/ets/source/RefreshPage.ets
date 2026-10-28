import { ChapterPageSource, PageRef, PageToken, SourceRef, SourceBatch } from '../model/SourceTypes';
import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkCall } from './SourceHttp';

export async function refreshPage(source: ChapterPageSource,chapter: SourceRef,pageKey: string,ctx: CallContext): Promise<PageRef> {
  let token: PageToken | undefined = undefined; const seen: Set<string> = new Set(); let count = 0;
  for (let batch = 0; batch < 100; batch++) {
    checkCall(ctx); const result: SourceBatch<PageRef> = await source.pages(chapter,token,ctx); count += result.items.length;
    if (count > 2000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'刷新图像清单超过2000项'); }
    const match: PageRef | undefined = result.items.find((page: PageRef) => page.pageKey === pageKey); if (match) { return match; }
    if (!result.next) { throw new AppError(ErrorCode.CONTENT_CHANGED,'图像标识已不在章节中，请重新打开章节'); }
    const key = JSON.stringify([result.next.kind,result.next.value,result.next.binding]); if (seen.has(key) || result.items.length === 0) { throw new AppError(ErrorCode.PARSE_ERROR,'刷新分页重复或没有进展'); }
    seen.add(key); token = result.next;
  }
  throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'刷新图像分页超过100批');
}
