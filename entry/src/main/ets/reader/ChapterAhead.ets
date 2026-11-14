import { BookSession, ReaderService } from '../business/ReaderService';
import { CancelScope } from '../model/CancelScope';
import { CallContext, ReaderTraceContext } from '../model/RequestTypes';
import { ReaderTrace } from '../diagnostic/ReaderTrace';

// At most one prepared chapter and its first three compressed images; no whole-chapter decode.
export class ChapterAhead {
  private readonly reader: ReaderService;
  private scope?: CancelScope;
  private pending?: Promise<void>;
  private ready?: BookSession;
  private id: string = '';
  private preparedAt: number = 0;
  constructor(reader: ReaderService) { this.reader = reader; }
  prepare(id: string, offlineOnly: boolean, skipRead: boolean,trace?: ReaderTraceContext): void {
    if (!id || this.id === id) { return; } this.clear(); this.id = id;
    const scope = new CancelScope(); this.scope = scope;
    const ctx: CallContext = { callId: 'reader-prefetch-next',deadlineMs: Date.now() + 60000,cancel: scope,ruleRevision: 1,trace: trace };
    this.pending = this.load(id,offlineOnly,skipRead,ctx);
  }
  private async load(id: string, offlineOnly: boolean, skipRead: boolean, ctx: CallContext): Promise<void> {
    let session: BookSession | undefined = undefined;
    try {
      session = await this.reader.open(id,ctx,offlineOnly,skipRead);
      for (let index = 0; !ctx.cancel.cancelled && index < Math.min(3,session.pages.length); index++) {
        try { await session.cache.load(session.source,session.chapter.ref,session.pages[index],{ callId: ctx.callId,deadlineMs: ctx.deadlineMs,cancel: ctx.cancel,
          ruleRevision: session.source?.version || 1,trace: ctx.trace ? ReaderTrace.context(ctx.trace.sessionId,session.source?.id || ctx.trace.sourceId,index + 1,'chapter-prefetch') : undefined }); }
        catch (error) { if (index === 0 || ctx.cancel.cancelled) { throw error as Error; } break; }
      }
      if (ctx.cancel.cancelled || this.id !== id) { session.cache.dispose(); return; }
      this.ready = session; this.preparedAt = Date.now(); session = undefined;
    } catch (_) { session?.cache.dispose(); }
  }
  async take(id: string): Promise<BookSession | undefined> {
    if (id !== this.id) { this.clear(); return undefined; }
    await this.pending;
    if (this.id !== id || this.scope?.cancelled || Date.now() - this.preparedAt > 120000) { this.clear(); return undefined; }
    const session = this.ready; this.ready = undefined; this.id = ''; this.pending = undefined; this.scope = undefined; return session;
  }
  clear(): void { this.scope?.cancel(); this.scope = undefined; this.ready?.cache.dispose(); this.ready = undefined; this.id = ''; this.pending = undefined; this.preparedAt = 0; }
}
