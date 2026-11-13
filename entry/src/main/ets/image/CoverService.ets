import { SourceHandle } from '../source/SourceRegistry';
import { SourceChanges } from '../source/SourceChanges';
import { SiteSession } from '../network/SiteSession';
import { CancelScope } from '../model/CancelScope';
import { CallContext, NetworkPriority } from '../model/RequestTypes';
import { ChapterPageSource, ImageRequest, PageRef, PageToken, SourceBatch, SourceRef } from '../model/SourceTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { UrlPolicy } from '../network/UrlPolicy';
import { ReaderAsset, ReaderAssetCache } from './ReaderAssetCache';
import { checkCall } from '../source/SourceHttp';

class CoverSource implements ChapterPageSource {
  readonly id: string; readonly version: number; private readonly handle: SourceHandle; private readonly address: string;
  constructor(handle: SourceHandle,address: string) { this.handle = handle; this.address = address; this.id = handle.source.id; this.version = handle.source.version; }
  pages(_chapter: SourceRef,_token: PageToken | undefined,_ctx: CallContext): Promise<SourceBatch<PageRef>> { return Promise.reject(new AppError(ErrorCode.UNSUPPORTED,'封面没有章节页清单')); }
  async resolveImage(_chapter: SourceRef,_page: PageRef,_refresh: boolean,_ctx: CallContext): Promise<ImageRequest> {
    return { url: new UrlPolicy(this.handle.rule.allowedHosts).validate(this.address).toString(),headers: this.handle.rule.definition.imageHeaders || [],contentRevision: this.handle.snapshotKey };
  }
}
interface HandleEntry { request: Promise<SourceHandle>; createdAt: number; }
interface CoverEntry { cache: ReaderAssetCache; source: CoverSource; handle: SourceHandle; users: number; }
export interface CoverLease { asset: ReaderAsset; release: () => void; }

export class CoverService {
  private static handles: Map<string,HandleEntry> = new Map();
  private static covers: Map<string,CoverEntry> = new Map();
  private static identity(cacheDir: string,source: string): string { return JSON.stringify([cacheDir,source,SourceChanges.epoch(source),SiteSession.epoch(source)]); }
  static async load(cacheDir: string,sourceId: string,mangaId: string,address: string,scope: CancelScope,open: () => Promise<SourceHandle>): Promise<CoverLease> {
    const version = CoverService.identity(cacheDir,sourceId);
    let saved = CoverService.handles.get(version);
    if (!saved || Date.now() - saved.createdAt >= 30000) {
      const request = open(); saved = { request: request,createdAt: Date.now() }; CoverService.handles.set(version,saved);
      request.catch(() => { if (CoverService.handles.get(version)?.request === request) { CoverService.handles.delete(version); } });
      while (CoverService.handles.size > 8) { const first: string = Array.from(CoverService.handles.keys())[0]; CoverService.handles.delete(first); }
    }
    const handle = await saved.request;
    const ctx: CallContext = { callId: 'cover',deadlineMs: Date.now() + 30000,cancel: scope,ruleRevision: handle.source.version,priority: { value: NetworkPriority.Cover } };
    checkCall(ctx);
    if (version !== CoverService.identity(cacheDir,sourceId)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'封面会话已变化'); }
    const key = JSON.stringify([version,handle.snapshotKey,handle.revision,mangaId,address]);
    let entry = CoverService.covers.get(key);
    if (!entry) {
      if (CoverService.covers.size >= 128) { throw new AppError(ErrorCode.RATE_LIMITED,'封面加载数量已达上限'); }
      entry = { cache: new ReaderAssetCache(cacheDir,handle.transport,4194304,2097152,handle.snapshotKey + ':cover:' + SiteSession.epoch(sourceId).toString()),
        source: new CoverSource(handle,address),handle: handle,users: 0 }; CoverService.covers.set(key,entry);
    }
    const current = entry; current.users++; let released = false;
    const release = (): void => { if (released) { return; } released = true; current.users--; if (!current.users) { current.cache.dispose(); if (CoverService.covers.get(key) === current) { CoverService.covers.delete(key); } } };
    try {
      const asset = await current.cache.load(current.source,{ sourceId: sourceId,remoteId: mangaId,locator: '' },{ pageKey: 'cover',ordinal: 0,locator: address },ctx);
      checkCall(ctx); if (version !== CoverService.identity(cacheDir,sourceId)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'封面会话已变化'); }
      return { asset: asset,release: release };
    } catch (error) { release(); throw error as Error; }
  }
}
