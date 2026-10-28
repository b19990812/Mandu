import { MangaRecord } from '../model/LibraryTypes';
import { CallContext } from '../model/RequestTypes';
import { PageToken } from '../model/SourceTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { SourceHandle } from '../source/SourceRegistry';
import { checkCall } from '../source/SourceHttp';
import { CatalogService } from './CatalogService';

export interface SearchGroup { sourceId: string; items: MangaRecord[]; state: string; hasNext: boolean; error: string; }
interface SearchCursor { id: string; handle?: SourceHandle; next?: PageToken; tokens: Set<string>; items: MangaRecord[]; state: string; error: string; }
export class GlobalCatalogSearch {
  private readonly catalog: CatalogService;
  private cursors: SearchCursor[] = [];
  private generation: number = 0;
  private query: string = '';
  constructor(catalog: CatalogService) { this.catalog = catalog; }
  clear(): void { this.generation++; this.cursors = []; this.query = ''; }
  cancel(): void {
    this.generation++;
    this.cursors.forEach((cursor: SearchCursor) => { if (cursor.state === 'pending' || cursor.state === 'loading') { cursor.state = 'cancelled'; } });
  }
  groups(): SearchGroup[] {
    return this.cursors.map((cursor: SearchCursor): SearchGroup => ({ sourceId: cursor.id,items: cursor.items.slice(),state: cursor.state,hasNext: cursor.next !== undefined,error: cursor.error }));
  }
  items(): MangaRecord[] { const items: MangaRecord[] = []; this.cursors.forEach((cursor: SearchCursor) => items.push(...cursor.items)); return items; }
  hasNext(): boolean { return this.cursors.some((cursor: SearchCursor) => cursor.next !== undefined); }
  errors(): string[] { return this.cursors.filter((cursor: SearchCursor) => cursor.error !== '').map((cursor: SearchCursor) => cursor.id + '：' + cursor.error); }
  async search(ids: string[], query: string, more: boolean, ctx: CallContext, changed: () => void): Promise<void> {
    checkCall(ctx);
    if (!more) {
      this.clear(); this.query = query;
      this.cursors = ids.filter((id: string,index: number,all: string[]) => all.indexOf(id) === index)
        .map((id: string): SearchCursor => ({ id: id,tokens: new Set(),items: [],state: 'pending',error: '' }));
    } else if (query !== this.query) { throw new AppError(ErrorCode.CONTENT_CHANGED,'关键词已改变，请重新搜索'); }
    changed();
    await this.run(this.cursors.filter((cursor: SearchCursor) => more ? cursor.next !== undefined : cursor.state === 'pending'),query,ctx,changed);
  }
  async loadSource(id: string,query: string,ctx: CallContext,changed: () => void): Promise<void> {
    checkCall(ctx);
    if (query !== this.query) { throw new AppError(ErrorCode.CONTENT_CHANGED,'关键词已改变，请重新搜索'); }
    const cursor = this.cursors.find((item: SearchCursor) => item.id === id);
    if (!cursor) { throw new AppError(ErrorCode.NOT_FOUND,'该漫画源不在本次搜索中'); }
    if (cursor.state === 'loading' || cursor.state === 'success' && !cursor.next) { return; }
    await this.run([cursor],query,ctx,changed);
  }
  private async run(work: SearchCursor[],query: string,ctx: CallContext,changed: () => void): Promise<void> {
    const generation = this.generation; let index = 0;
    const worker = async (): Promise<void> => {
      while (index < work.length && generation === this.generation) {
        checkCall(ctx); const cursor = work[index++];
        cursor.state = 'loading'; cursor.error = ''; changed();
        try {
          const handle = cursor.handle || await this.catalog.open(cursor.id);
          checkCall(ctx); if (generation !== this.generation) { return; }
          const call: CallContext = { callId: ctx.callId + '-global-' + cursor.id,deadlineMs: Math.min(ctx.deadlineMs,Date.now() + 30000),cancel: ctx.cancel,ruleRevision: handle.source.version };
          const batch = await this.catalog.search(handle,query,cursor.next,call); checkCall(call);
          if (generation !== this.generation) { return; }
          const seen = new Set(cursor.items.map((item: MangaRecord) => item.id)); const additions = batch.items.filter((item: MangaRecord) => { if (seen.has(item.id)) { return false; } seen.add(item.id); return true; });
          let token = '';
          if (batch.next) {
            token = JSON.stringify([batch.next.kind,batch.next.value,batch.next.binding]);
            if (cursor.tokens.has(token) || cursor.handle && additions.length === 0) { throw new AppError(ErrorCode.PARSE_ERROR,'分页重复，已有结果保留'); }
          }
          if (this.items().length + additions.length > 5000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'搜索结果超过5000，请缩小关键词'); }
          if (token) { cursor.tokens.add(token); }
          cursor.items.push(...additions); cursor.handle = handle; cursor.next = batch.next; cursor.state = 'success'; cursor.error = '';
        } catch (error) {
          checkCall(ctx); if (generation !== this.generation) { return; }
          cursor.error = error instanceof AppError ? error.code + '：' + error.message : '搜索失败，请重试'; cursor.state = 'error';
        }
        changed();
      }
    };
    await Promise.all([worker(),worker()]);
  }
}
