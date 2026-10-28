import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { ChapterRef, MangaSummary, PageToken, Source, SourceBatch } from '../model/SourceTypes';
import { collectChapterManifest } from '../business/ChapterManifest';

export async function runSourceScenario(source: Source, ctx: CallContext): Promise<string> {
  const manga: MangaSummary[] = [];
  let token: PageToken | undefined = undefined;
  for (let count = 0; count < 10; count++) {
    const batch: SourceBatch<MangaSummary> = await source.search('', token, ctx);
    batch.items.forEach((item: MangaSummary) => manga.push(item));
    token = batch.next;
    if (!token) { break; }
  }
  if (token || manga.length !== 2 || manga[0].ref.remoteId !== 'm1') {
    throw new AppError(ErrorCode.PARSE_ERROR, '自有搜索分页样本不符');
  }
  const detail = await source.details(manga[0].ref, ctx);
  if (detail.title !== '星海旅人 & 归途') { throw new AppError(ErrorCode.PARSE_ERROR, '自有详情或中文实体不符'); }
  const chapters: ChapterRef[] = [];
  for (let count = 0; count < 10; count++) {
    const batch: SourceBatch<ChapterRef> = await source.chapters(detail.ref, token, ctx);
    batch.items.forEach((item: ChapterRef) => chapters.push(item));
    token = batch.next;
    if (!token) { break; }
  }
  if (token || chapters.length !== 3 || chapters[0].ref.remoteId !== 'c1') {
    throw new AppError(ErrorCode.PARSE_ERROR, '自有章节分页样本不符');
  }
  const manifest = await collectChapterManifest(source, chapters[0].ref, ctx);
  if (manifest.pages.length !== 2 || manifest.pages[0].pageKey !== 'c1-p1' || manifest.pages[1].pageKey !== 'c1-p2') {
    throw new AppError(ErrorCode.PARSE_ERROR, '自有图像清单或顺序不符');
  }
  await source.resolveImage(chapters[0].ref, manifest.pages[0], false, ctx);
  const empty = await source.search('missing', undefined, ctx);
  if (empty.items.length !== 0 || empty.next) { throw new AppError(ErrorCode.PARSE_ERROR, '明确空结果样本不符'); }
  return '搜索2项/章节3项/图像2项';
}
