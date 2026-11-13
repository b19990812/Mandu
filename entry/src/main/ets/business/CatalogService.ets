import { AppError, ErrorCode } from '../model/ErrorTypes';
import { MangaRecord } from '../model/LibraryTypes';
import { CallContext } from '../model/RequestTypes';
import { ChapterRef, PageToken, SourceBatch } from '../model/SourceTypes';
import { SourceRegistry, SourceHandle } from '../source/SourceRegistry';
import { checkCall } from '../source/SourceHttp';
import { CatalogRepository } from '../storage/CatalogRepository';
import { NetworkPerf } from '../diagnostic/NetworkPerf';

export interface MangaBatch { items: MangaRecord[]; next?: PageToken; }

export class CatalogService {
  private readonly registry: SourceRegistry;
  private readonly catalog: CatalogRepository;
  constructor(registry: SourceRegistry, catalog: CatalogRepository) { this.registry = registry; this.catalog = catalog; }
  open(sourceId: string): Promise<SourceHandle> { return this.registry.open(sourceId); }
  async search(handle: SourceHandle, query: string, token: PageToken | undefined, ctx: CallContext): Promise<MangaBatch> {
    const watch = this.registry.watch(handle, ctx);
    try {
    const batch = await handle.source.search(query, token, ctx); checkCall(ctx);
    const items = await this.catalog.saveSearch(batch.items, () => watch.check()); watch.check();
    return { items: items, next: batch.next };
    } finally { watch.release(); }
  }
  async refresh(mangaId: string, ctx: CallContext, queueNew: boolean = false): Promise<void> {
    const manga = await this.catalog.manga(mangaId); if (!manga) { throw new AppError(ErrorCode.NOT_FOUND, '本地漫画记录不存在'); }
    if (manga.detail.ref.sourceId === 'org.hsmihon.local') { return; }
    const handle = await this.registry.open(manga.detail.ref.sourceId);
    const call: CallContext = { callId: ctx.callId, deadlineMs: ctx.deadlineMs, cancel: ctx.cancel, ruleRevision: handle.source.version,priority: ctx.priority };
    const watch = this.registry.watch(handle, call);
    try {
    const started = Date.now();
    const snapshot = handle.source.catalog ? await handle.source.catalog.loadCatalog(manga.detail.ref,call) : undefined;
    if (snapshot && snapshot.chapters.length === 0) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'来源未返回完整目录，旧目录保留'); }
    const detail = snapshot ? snapshot.detail : await handle.source.details(manga.detail.ref, call);
    if (detail.ref.remoteId !== manga.detail.ref.remoteId) { throw new AppError(ErrorCode.CONTENT_CHANGED, '详情返回了不同漫画身份'); }
    const chapters: ChapterRef[] = []; const seen: Map<string, ChapterRef> = new Map(); const tokens: Set<string> = new Set();
    let token: PageToken | undefined = undefined; let complete = false;
    for (let count = 0; count < 100; count++) {
      checkCall(call);
      const batch: SourceBatch<ChapterRef> = snapshot ? { items: snapshot.chapters } : await handle.source.chapters(detail.ref, token, call);
      const before = chapters.length;
      batch.items.forEach((chapter: ChapterRef) => {
        const old = seen.get(chapter.ref.remoteId);
        if (old && old.ref.locator !== chapter.ref.locator) { throw new AppError(ErrorCode.CONTENT_CHANGED, '相同章节标识的地址发生冲突'); }
        if (!old) { seen.set(chapter.ref.remoteId, chapter); chapters.push(chapter); }
      });
      if (chapters.length > 10000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '目录超过10000章，旧目录保留'); }
      if (!batch.next) { complete = true; break; }
      const key = JSON.stringify([batch.next.kind, batch.next.value, batch.next.binding]);
      if (tokens.has(key) || chapters.length === before) { throw new AppError(ErrorCode.PARSE_ERROR, '章节分页重复或没有前进，旧目录保留'); }
      tokens.add(key); token = batch.next;
    }
    if (!complete) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '目录超过100批，旧目录保留'); }
    chapters.sort((a: ChapterRef, b: ChapterRef) => a.ordinal - b.ordinal);
    NetworkPerf.stage(handle.source.id,'catalog-load',started,chapters.length);
    checkCall(call); await this.registry.assertCurrent(manga.detail.ref.sourceId, handle.revision);
    const saving = Date.now();
    await this.catalog.saveDetail(mangaId, detail, chapters, () => watch.check(), queueNew); watch.check();
    NetworkPerf.stage(handle.source.id,'catalog-save',saving,chapters.length);
    } finally { watch.release(); }
  }
}
