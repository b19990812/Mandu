import { CallContext, ResponseRetention } from '../model/RequestTypes';
import { SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem, PageToken } from '../model/SourceTypes';
import { SourceRegistry, SourceHandle } from '../source/SourceRegistry';
import { CatalogRepository } from '../storage/CatalogRepository';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkCall } from '../source/SourceHttp';
import { SiteSession } from '../network/SiteSession';
import { SourceChanges } from '../source/SourceChanges';
import { NetworkPerf } from '../diagnostic/NetworkPerf';
import { SharedRequest } from '../network/SharedRequest';

export interface CachedBrowse { batch: SourceBrowseBatch; expiresAt: number; staleAllowed: boolean; storedAt: number; }

export class SourceDiscoveryService {
  private static cache: Map<string,CachedBrowse> = new Map();
  private static pending: Map<string,SharedRequest<SourceBrowseBatch>> = new Map();
  private readonly registry: SourceRegistry;
  private readonly catalog: CatalogRepository;
  constructor(registry: SourceRegistry,catalog: CatalogRepository) { this.registry = registry; this.catalog = catalog; }
  open(id: string): Promise<SourceHandle> { return this.registry.open(id); }
  private key(handle: SourceHandle,query: SourceBrowseQuery,token?: PageToken): string {
    return JSON.stringify([handle.source.id,handle.snapshotKey,handle.revision,SourceChanges.epoch(handle.source.id),SiteSession.epoch(handle.source.id),
      query.feed,query.filters.slice().sort((a,b) => a.id.localeCompare(b.id)),token || null]);
  }
  async cached(handle: SourceHandle,query: SourceBrowseQuery,ctx: CallContext): Promise<CachedBrowse | undefined> {
    checkCall(ctx); await this.registry.assertCurrent(handle.source.id,handle.revision); checkCall(ctx);
    const key = this.key(handle,query); const saved = SourceDiscoveryService.cache.get(key);
    if (!saved) { return undefined; }
    if (Date.now() - saved.storedAt > 1800000 || !saved.staleAllowed && saved.expiresAt <= Date.now()) { SourceDiscoveryService.cache.delete(key); return undefined; }
    SourceDiscoveryService.cache.delete(key); SourceDiscoveryService.cache.set(key,saved); return saved;
  }
  async browse(handle: SourceHandle,query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (!handle.source.discovery) { throw new AppError(ErrorCode.UNSUPPORTED,'该源暂未提供原生首页，请使用搜索或网站首页'); }
    checkCall(ctx); const key = this.key(handle,query,token);
    let pending = SourceDiscoveryService.pending.get(key);
    if (!pending || pending.cancelled) {
      if (SourceDiscoveryService.pending.size >= 32 && !pending) { throw new AppError(ErrorCode.RATE_LIMITED,'栏目请求过多，请稍后重试'); }
      const request = new SharedRequest<SourceBrowseBatch>(ctx,async (call: CallContext) => {
        try { return await this.fetch(handle,query,token,call); }
        finally { if (SourceDiscoveryService.pending.get(key) === request) { SourceDiscoveryService.pending.delete(key); } }
      });
      SourceDiscoveryService.pending.set(key,request); pending = request;
    }
    const watch = this.registry.watch(handle,ctx);
    try { const batch = await pending.consume(ctx); watch.check(); return batch; } finally { watch.release(); }
  }
  private async fetch(handle: SourceHandle,query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    const watch = this.registry.watch(handle,ctx);
    const key = this.key(handle,query,token); const started = Date.now();
    const retention: ResponseRetention = { allowed: true,expiresAt: Date.now() + 300000,staleAllowed: true };
    const call: CallContext = { callId: ctx.callId,deadlineMs: ctx.deadlineMs,cancel: ctx.cancel,ruleRevision: ctx.ruleRevision,retention: retention,priority: ctx.priority };
    try {
      const batch = await handle.source.discovery!.browse(query,token,call); watch.check();
      if (key !== this.key(handle,query,token)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'站点会话已变化，请重新加载栏目'); }
      // Cache first pages only, with an item and entry bound. Pagination stays live.
      if (!token && retention.allowed && batch.items.length <= 500) {
        SourceDiscoveryService.cache.delete(key);
        SourceDiscoveryService.cache.set(key,{ batch: batch,expiresAt: retention.expiresAt,staleAllowed: retention.staleAllowed,storedAt: Date.now() });
        while (SourceDiscoveryService.cache.size > 16) { const oldest: string = Array.from(SourceDiscoveryService.cache.keys())[0]; SourceDiscoveryService.cache.delete(oldest); }
      } else if (!token) { SourceDiscoveryService.cache.delete(key); }
      NetworkPerf.stage(handle.source.id,'browse-load',started,batch.items.length); return batch;
    }
    finally { watch.release(); }
  }
  async select(handle: SourceHandle,item: SourceBrowseItem,ctx: CallContext): Promise<string> {
    if (item.manga.ref.sourceId !== handle.source.id) { throw new AppError(ErrorCode.CONFLICT,'漫画不属于当前来源'); }
    const watch = this.registry.watch(handle,ctx);
    try {
      checkCall(ctx); await this.registry.assertCurrent(handle.source.id,handle.revision); watch.check();
      const records = await this.catalog.saveSearch([item.manga],() => watch.check()); watch.check(); return records[0].id;
    } finally { watch.release(); }
  }
}
