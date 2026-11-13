import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { CancelScope } from '../model/CancelScope';
import { ByteSink } from '../model/ByteSink';
import { SourcePackageStore, SourceState } from '../model/SourcePackageTypes';
import { ChapterRef, ImageRequest, MangaDetail, MangaSummary, PageRef, PageToken, Source, SourceBatch, SourceRef, SourceDiscovery, SourceFeed, SourceBrowseQuery, SourceBrowseBatch, SourceCatalog, SourceCatalogSnapshot } from '../model/SourceTypes';
import { RequestPlan, Transport, TransportResponse } from '../network/Transport';
import { UrlPolicy } from '../network/UrlPolicy';
import { checkCall } from './SourceHttp';
import { SourceImportService } from './SourceImportService';
import { RuleSource } from './rules/RuleSource';
import { ValidatedRulePackage } from './rules/RuleTypes';
import { SourceChanges } from './SourceChanges';
import { observeRetention } from '../network/ResponseRetentionPolicy';

export interface SourceHandle { source: Source; rule: ValidatedRulePackage; revision: number; snapshotKey: string; transport: Transport; }
export interface SourceWatch { check: () => void; release: () => void; }
export interface NativeSourceResolver { owns(id: string): boolean; open(id: string,key?: string): Promise<SourceHandle>; assertCurrent(id: string,revision: number): Promise<void>; }

export class SourceRegistry {
  private readonly store: SourcePackageStore;
  private readonly imports: SourceImportService;
  private readonly createTransport: (rule: ValidatedRulePackage) => Transport;
  private readonly native?: NativeSourceResolver;
  constructor(store: SourcePackageStore, createTransport: (rule: ValidatedRulePackage) => Transport,native?: NativeSourceResolver) {
    this.store = store; this.imports = new SourceImportService(store); this.createTransport = createTransport; this.native = native;
  }
  async open(id: string): Promise<SourceHandle> {
    if (this.native?.owns(id)) { return this.native.open(id); }
    const catalog = await this.store.read(); const state = catalog.entries.find((item: SourceState) => item.id === id);
    if (!state || state.removed || !state.enabled) { throw new AppError(ErrorCode.DISABLED, '源已禁用或移除'); }
    const rule = await this.imports.load(state.active, state.id);
    const guard = async (): Promise<void> => {
      const current = (await this.store.read()).entries.find((item: SourceState) => item.id === state.id);
      if (!current || !current.enabled || current.removed) { throw new AppError(ErrorCode.DISABLED, '源已禁用或移除，旧结果已丢弃'); }
      if (current.revision !== state.revision || current.active !== state.active) { throw new AppError(ErrorCode.CONTENT_CHANGED, '源规则已切换，请重新读取'); }
    };
    const transport = new RegistryTransport(this.createTransport(rule), state, guard, false);
    const source = new RuleSource(rule.definition, rule.baseUrl, new UrlPolicy(rule.allowedHosts), transport, state.revision.toString());
    const guarded = new RegisteredSource(source, state, guard);
    await guarded.ensure();
    return { source: guarded, rule: rule, revision: state.revision, snapshotKey: state.active, transport: transport };
  }
  async openPinned(id: string, key: string): Promise<SourceHandle> {
    if (this.native?.owns(id)) { return this.native.open(id,key); }
    const state = (await this.store.read()).entries.find((item: SourceState) => item.id === id);
    if (!state || !state.enabled || state.removed || !state.versions.some((item) => item.key === key)) { throw new AppError(ErrorCode.DISABLED, '下载所用源版本已禁用或不存在'); }
    const rule = await this.imports.load(key, id);
    const guard = async (): Promise<void> => {
      const current = (await this.store.read()).entries.find((item: SourceState) => item.id === id);
      if (!current || !current.enabled || current.removed || !current.versions.some((item) => item.key === key)) { throw new AppError(ErrorCode.DISABLED, '源已禁用或移除，下载已停止'); }
    };
    const transport = new RegistryTransport(this.createTransport(rule), state, guard, true);
    const source = new RuleSource(rule.definition, rule.baseUrl, new UrlPolicy(rule.allowedHosts), transport, key);
    await guard();
    return { source: new RegisteredSource(source, state, guard), rule: rule, revision: state.revision, snapshotKey: key, transport: transport };
  }
  watch(handle: SourceHandle, ctx: CallContext): SourceWatch {
    let changed = false; let disabled = false;
    const release = SourceChanges.subscribe(handle.source.id, (state: SourceState) => { changed = state.revision !== handle.revision; disabled = !state.enabled || state.removed; });
    const address = SourceChanges.watchAddress(handle.source.id,() => { changed = true; });
    return { check: (): void => { checkCall(ctx); if (disabled) { throw new AppError(ErrorCode.DISABLED, '源已禁用或移除'); } if (changed) { throw new AppError(ErrorCode.CONTENT_CHANGED, '源规则或网址已切换，旧结果已丢弃'); } }, release: () => { release(); address(); } };
  }
  async assertCurrent(id: string, revision: number): Promise<void> {
    if (this.native?.owns(id)) { await this.native.assertCurrent(id,revision); return; }
    const state = (await this.store.read()).entries.find((entry: SourceState) => entry.id === id);
    if (!state || !state.enabled || state.removed) { throw new AppError(ErrorCode.DISABLED, '源已禁用或移除'); }
    if (state.revision !== revision) { throw new AppError(ErrorCode.CONTENT_CHANGED, '源规则已切换，旧结果已丢弃'); }
  }
}

export class RegistryTransport implements Transport {
  private readonly delegate: Transport;
  private readonly state: SourceState;
  private readonly guard: () => Promise<void>;
  private readonly pinned: boolean;
  constructor(delegate: Transport, state: SourceState, guard: () => Promise<void>, pinned: boolean) { this.delegate = delegate; this.state = state; this.guard = guard; this.pinned = pinned; }
  private async call(plan: RequestPlan, ctx: CallContext, sink?: ByteSink): Promise<TransportResponse> {
    const cancel = new CancelScope(); const unsubscribe = ctx.cancel.subscribe(() => cancel.cancel());
    const unwatch = SourceChanges.subscribe(this.state.id, (state: SourceState) => { if (!state.enabled || state.removed || !this.pinned && state.revision !== this.state.revision) { cancel.cancel(); } });
    const address = SourceChanges.watchAddress(this.state.id,() => cancel.cancel());
    const inner: CallContext = { callId: ctx.callId, deadlineMs: ctx.deadlineMs, cancel: cancel, ruleRevision: ctx.ruleRevision,retention: ctx.retention,priority: ctx.priority };
    try {
      await this.guard(); checkCall(inner);
      const response = sink ? await this.delegate.streamToFile(plan, inner, sink) : await this.delegate.send(plan, inner);
      observeRetention(ctx,response.headers);
      await this.guard(); checkCall(inner); return response;
    } catch (error) {
      await this.guard();
      if (error instanceof AppError) { throw error; }
      throw new AppError(ErrorCode.NETWORK_ERROR, '受控网络请求失败');
    } finally { unsubscribe(); unwatch(); address(); }
  }
  send(plan: RequestPlan, ctx: CallContext): Promise<TransportResponse> { return this.call(plan, ctx); }
  streamToFile(plan: RequestPlan, ctx: CallContext, sink: ByteSink): Promise<TransportResponse> { return this.call(plan, ctx, sink); }
}

export class RegisteredSource implements Source {
  readonly id: string;
  readonly version: number;
  readonly discovery: SourceDiscovery | undefined;
  readonly catalog: SourceCatalog | undefined;
  private readonly delegate: Source;
  private readonly guard: () => Promise<void>;
  constructor(delegate: Source, state: SourceState, guard: () => Promise<void>) {
    this.delegate = delegate; this.id = state.id; this.version = delegate.version; this.guard = guard;
    this.discovery = delegate.discovery ? new RegisteredDiscovery(delegate.discovery,guard) : undefined;
    this.catalog = delegate.catalog ? new RegisteredCatalog(delegate.catalog,guard) : undefined;
  }
  async ensure(): Promise<void> { await this.guard(); }
  private async call<T>(ctx: CallContext, operation: () => Promise<T>): Promise<T> {
    checkCall(ctx); await this.guard(); checkCall(ctx);
    const result = await operation();
    checkCall(ctx); await this.guard(); checkCall(ctx);
    return result;
  }
  search(query: string, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    return this.call(ctx, () => this.delegate.search(query, token, ctx));
  }
  details(manga: SourceRef, ctx: CallContext): Promise<MangaDetail> { return this.call(ctx, () => this.delegate.details(manga, ctx)); }
  chapters(manga: SourceRef, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    return this.call(ctx, () => this.delegate.chapters(manga, token, ctx));
  }
  pages(chapter: SourceRef, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<PageRef>> {
    return this.call(ctx, () => this.delegate.pages(chapter, token, ctx));
  }
  resolveImage(chapter: SourceRef, page: PageRef, refresh: boolean, ctx: CallContext): Promise<ImageRequest> {
    return this.call(ctx, () => this.delegate.resolveImage(chapter, page, refresh, ctx));
  }
}

class RegisteredCatalog implements SourceCatalog {
  private readonly delegate: SourceCatalog;
  private readonly guard: () => Promise<void>;
  constructor(delegate: SourceCatalog,guard: () => Promise<void>) { this.delegate = delegate; this.guard = guard; }
  async loadCatalog(manga: SourceRef,ctx: CallContext): Promise<SourceCatalogSnapshot> {
    checkCall(ctx); await this.guard(); checkCall(ctx);
    const snapshot = await this.delegate.loadCatalog(manga,ctx);
    checkCall(ctx); await this.guard(); checkCall(ctx); return snapshot;
  }
}

class RegisteredDiscovery implements SourceDiscovery {
  readonly feeds: SourceFeed[];
  private readonly delegate: SourceDiscovery;
  private readonly guard: () => Promise<void>;
  constructor(delegate: SourceDiscovery,guard: () => Promise<void>) { this.delegate = delegate; this.feeds = delegate.feeds; this.guard = guard; }
  async browse(query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    checkCall(ctx); await this.guard(); checkCall(ctx);
    const batch = await this.delegate.browse(query,token,ctx);
    checkCall(ctx); await this.guard(); checkCall(ctx); return batch;
  }
}
