import { ReaderPerf } from '../diagnostic/ReaderPerf';
import { ReaderTrace } from '../diagnostic/ReaderTrace';
import { TileWarmCache } from '../image/TileWarmCache';
import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { BookSession } from '../business/ReaderService';
import { ReaderAsset } from '../image/ReaderAssetCache';
import { CallContext, NetworkPriority, ReaderTraceContext } from '../model/RequestTypes';
import { CancelScope } from '../model/CancelScope';
import { ViewOperation, viewError } from './ViewOperation';
import { StripModel } from '../reader/StripModel';
import { ReaderLifecycle } from '../reader/ReaderLifecycle';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { BrowserCache } from '../image/BrowserCache';
import { TrialReaderSessions } from '../reader/TrialReaderSessions';
import { ReaderSession } from '../business/ChapterReaderService';
import { AssetProvider } from '../image/AssetProvider';
import { ReaderPreloader } from '../reader/ReaderPreloader';
import { DEFAULT_PREFETCH_PAGES } from '../model/ReaderPreferences';
import { ChapterAhead } from '../reader/ChapterAhead';
import { NetworkPolicy } from '../network/NetworkPolicy';
import { EHENTAI_ID } from '../network/EhentaiAccess';
import { defaultReaderDisplay, ReaderDisplay, READER_MODES, stripMode, validDisplay } from '../model/ReaderDisplay';
import { ChapterPageSource, PageRef, SourceRef } from '../model/SourceTypes';

interface ReaderRuntime { source: ChapterPageSource | undefined; chapter: SourceRef; pages: PageRef[]; cache: AssetProvider; offline: boolean; partialOffline: boolean; }

@Observed
export class ReaderVM {
  title: string = '阅读器';
  sourceId: string = '';
  status: string = '正在读取章节…';
  index: number = 0;
  total: number = 0;
  ratio: number = 0;
  asset?: ReaderAsset;
  companionAsset?: ReaderAsset;
  companionStatus: string = '正在读取图像…';
  displayIndex: number = 0;
  active: boolean = true;
  busy: boolean = false;
  zoom: number = 1;
  offsetX: number = 0;
  offsetY: number = 0;
  previousId: string = '';
  nextId: string = '';
  mode: string = 'paged';
  pagerTarget: number = 0;
  pagerRevision: number = 0;
  readerEpoch: number = 0;
  pagerMoving: boolean = false;
  turnDirection: number = 1;
  private chapterScope?: CancelScope;
  usesPager(): boolean { return this.mode === 'paged' || this.mode === 'tap' || this.mode === 'curl' || this.mode === 'spread'; }
  direction: string = 'ltr';
  background: string = 'dark';
  scale: string = 'auto';
  tapZones: string = 'sides';
  invertTap: boolean = false;
  incognito: boolean = false;
  isStrip(): boolean { return stripMode(this.mode); }
  private applyDisplay(display: ReaderDisplay): void { this.background = display.background; this.scale = display.scale; this.tapZones = display.tapZones; this.invertTap = display.invertTap; }
  display(display: ReaderDisplay): void { if (validDisplay(display)) { this.applyDisplay(display); this.persistReading(); } }
  stripRevision: number = 0;
  readonly strip: StripModel = new StripModel();
  trialMode: boolean = false;
  autoNext: boolean = true;
  skipRead: boolean = false;
  bookmarked: boolean = false;
  chapterChanging: boolean = false;
  private preloadNext: boolean = true;
  private prefetchWifi: boolean = false;
  private mangaId: string = '';
  private ahead?: ChapterAhead;
  private prefetchGeneration: number = 0;
  private prefetchAttempt: number = 0;
  private finishing: boolean = false;
  private app?: AppContainer;
  private session?: BookSession;
  private chapterId: string = '';
  private readonly operation: ViewOperation = new ViewOperation();
  private prefetch?: ReaderPreloader;
  private renderAhead?: ReaderPreloader;
  private prefetchIndex: number = -1;
  private prefetchPages: number = DEFAULT_PREFETCH_PAGES;
  private pageVisible: boolean = true;
  private foreground: boolean = true;
  private stripRestoring: boolean = false;
  private saveTimer: number = -1;
  private completed: boolean = false;
  private offlineOnly: boolean = false;
  private prefetchEnabled: boolean = true;
  private maxSaveTimer: number = -1;
  private lifecycle?: () => void;
  private reading?: ReaderRuntime;
  private websiteSource(id: string): string { return id === 'org.hsmihon.local' || id.startsWith('org.example.demo.') ? '' : id; }
  private trial?: ReaderSession;
  private trialToken: string = '';
  private readonly loadedPages: Set<number> = new Set();
  private traceSessionId: string = '';
  private readonly traceContexts: Map<string,ReaderTraceContext> = new Map();

  private beginTraceSession(sourceId: string): void {
    this.traceSessionId = ReaderTrace.newSessionId(); this.traceContexts.clear();
    ReaderTrace.record(ReaderTrace.context(this.traceSessionId,sourceId,0,'reader'),'reader-session',0,'start');
  }
  tracePage(index: number,role: string): ReaderTraceContext {
    const sourceId = this.reading?.source?.id || this.sourceId;
    const pageIndex = Math.max(0,index + 1);
    const sessionId = this.traceSessionId || 'unscoped';
    const key = sourceId + ':' + pageIndex.toString() + ':' + role;
    let trace = this.traceContexts.get(key);
    if (!trace) {
      trace = ReaderTrace.context(sessionId,sourceId,pageIndex,role);
      this.traceContexts.set(key,trace);
    } else { ReaderTrace.registerContext(trace); }
    return trace;
  }

  initialize(context: common.UIAbilityContext, chapterId: string, offlineOnly: boolean = false,trialToken: string = ''): void {
    this.trialToken = trialToken; this.trialMode = trialToken !== '';
    this.offlineOnly = offlineOnly; this.operation.reopen(); this.app = new AppContainer(context); this.chapterId = chapterId;
    this.beginTraceSession(this.sourceId);
    this.ahead = new ChapterAhead(this.app.bookReader);
    this.foreground = ReaderLifecycle.isForeground; this.active = this.pageVisible && this.foreground;
    if (this.lifecycle) { this.lifecycle(); }
    this.lifecycle = ReaderLifecycle.subscribe((foreground: boolean) => { this.foreground = foreground; this.updateActive(); });
    if (this.active) { this.open(); }
  }
  async open(): Promise<void> {
    if (!this.app || this.busy || !this.active) { return; } const ctx = this.operation.begin(60000); ctx.trace = ReaderTrace.context(this.traceSessionId,this.sourceId,0,'open');
    const openStarted = Date.now(); let openOutcome = 'ok'; this.busy = true; this.status = '正在读取完整章节…'; let opened = false;
    try {
      if (!this.trialMode) {
        const chapter = await this.app.catalog.chapter(this.chapterId); if (!this.operation.active(ctx)) { return; }
        this.mangaId = chapter?.mangaId || ''; this.sourceId = this.websiteSource(chapter?.ref.sourceId || '');
        if (ctx.trace) { ctx.trace.sourceId = this.sourceId; }
      }
      const prefs = await this.app.preferences.read(this.mangaId); if (!this.operation.active(ctx)) { return; }
      this.mode = prefs.mode; this.direction = prefs.direction; this.prefetchEnabled = prefs.prefetch; this.prefetchPages = prefs.prefetchPages;
      this.autoNext = prefs.autoNext; this.skipRead = prefs.skipRead; this.preloadNext = prefs.preloadNext; this.prefetchWifi = prefs.prefetchWifi;
      this.applyDisplay(prefs); this.incognito = prefs.incognito;
      BrowserCache.setBudget(prefs.cacheMiB);
      if (this.trialMode) {
        if (!this.trial) { this.trial = TrialReaderSessions.take(this.trialToken); }
        const trial = this.trial;
        if (ReaderPerf.enabled && trial.source.id.startsWith('org.example.demo.')) { this.mode = ReaderPerf.mode; this.direction = 'ltr'; this.incognito = true; this.prefetchEnabled = true; this.prefetchWifi = false; }
        else { ReaderPerf.enabled = false; }
        this.sourceId = this.websiteSource(trial.source.id);
        if (ctx.trace) { ctx.trace.sourceId = this.sourceId; }
        this.reading = { source: trial.source,chapter: trial.manifest.chapter,pages: trial.manifest.pages,cache: trial.cache,offline: false,partialOffline: false };
        const position = await this.app.trialPositions.read(trial.manifest.chapter,trial.manifest.pages);
        if (!this.operation.active(ctx)) { return; }
        this.title = trial.manifest.label; this.total = trial.manifest.pages.length; this.index = ReaderPerf.enabled ? 0 : position.index; this.ratio = ReaderPerf.enabled ? 0 : position.ratio; this.asset = undefined;
        this.loadedPages.clear(); this.strip.reset(this.total); opened = true;
      } else {
      const prepared = await this.ahead?.take(this.chapterId);
      if (!this.operation.active(ctx)) { prepared?.cache.dispose(); return; }
      const session = prepared || await this.app.bookReader.open(this.chapterId, ctx, this.offlineOnly,this.skipRead);
      if (!this.operation.active(ctx)) { session.cache.dispose(); return; }
      if (this.reading) { this.reading.cache.dispose(); } this.session = session;
      this.reading = { source: session.source,chapter: session.chapter.ref,pages: session.pages,cache: session.cache,offline: session.offline,partialOffline: session.partialOffline };
      this.title = session.mangaTitle + ' · ' + session.chapter.title; this.total = session.pages.length; this.index = session.startIndex; this.ratio = session.startRatio;
      this.previousId = session.previousId; this.nextId = session.nextId; this.asset = undefined; opened = true;
      this.completed = session.startCompleted;
      this.bookmarked = session.chapter.bookmarked;
      this.loadedPages.clear(); this.strip.reset(session.pages.length);
      this.status = session.positionChanged ? '内容已改变，已恢复到附近图像' : '章节已读取';
      }
    } catch (error) { openOutcome = error instanceof AppError ? error.code : 'failed'; if (this.operation.active(ctx)) { this.status = viewError(error as Error); } }
    finally { if (ctx.cancel.cancelled && openOutcome === 'ok') { openOutcome = 'cancelled'; }
      ReaderTrace.record(ctx.trace,'reader-open',Date.now() - openStarted,openOutcome,'',this.total); if (this.operation.active(ctx)) { this.busy = false; } }
    if (opened && this.operation.active(ctx)) { this.readerEpoch++; TileWarmCache.clear(); this.renderAhead?.clear(); this.renderAhead = undefined; this.prefetch?.clear(); this.prefetch = undefined; this.prefetchIndex = -1; await this.load(this.index, true); }
  }
  async load(index: number, restore: boolean = false): Promise<void> {
    if (!this.reading || !this.app || !this.active || this.chapterChanging || index < 0 || index >= this.total) { return; }
    if (this.usesPager()) {
      if (this.pagerMoving) { return; }
      this.prioritizePage(index);
      this.pagerTarget = index; this.pagerRevision++; this.busy = false;
      if (!this.asset) { this.status = '正在准备可显示的页面…'; }
      return;
    }
    const session = this.reading; const ctx = this.operation.begin(60000, session.source?.version || 0);
    ctx.priority = { value: NetworkPriority.Visible };
    this.busy = true; this.status = '正在读取图像…';
    this.turnDirection = (index < this.index ? -1 : 1) * (this.mode !== 'vertical' && this.direction === 'rtl' ? -1 : 1);
    const displayIndex = this.mode === 'spread' ? Math.floor(index / 2) * 2 : index;
    try {
      const pageContext = (pageIndex: number): CallContext => ({ callId: ctx.callId + '-page-' + pageIndex.toString(),deadlineMs: ctx.deadlineMs,
        cancel: ctx.cancel,ruleRevision: ctx.ruleRevision,priority: ctx.priority,trace: this.tracePage(pageIndex,'visible') });
      const requests: Promise<ReaderAsset>[] = [session.cache.load(session.source,session.chapter,session.pages[displayIndex],pageContext(displayIndex))];
      if (this.mode === 'spread' && displayIndex + 1 < this.total) { requests.push(session.cache.load(session.source,session.chapter,session.pages[displayIndex + 1],pageContext(displayIndex + 1))); }
      const assets = await Promise.all(requests);
      if (!this.operation.active(ctx)) { return; }
      this.index = index; this.displayIndex = displayIndex; if (!restore) { this.ratio = 0; }
      this.zoom = 1; this.offsetX = 0; this.offsetY = 0;
      assets.forEach((asset: ReaderAsset, offset: number) => { this.loadedPages.add(displayIndex + offset); this.stripDimensions(displayIndex + offset,asset); });
      this.asset = assets[0]; this.companionAsset = assets.length > 1 ? assets[1] : undefined; this.companionStatus = '';
      this.status = '图像 ' + (index + 1).toString() + ' / ' + this.total.toString();
      this.startPrefetch(displayIndex); await this.save(); this.prepareNext();
    } catch (error) { if (this.operation.active(ctx)) { this.status = viewError(error as Error); this.companionStatus = this.status; } }
    finally { if (this.operation.active(ctx)) { this.busy = false; } }
  }
  private async startPrefetch(index: number): Promise<void> {
    const session = this.reading;
    if (!this.prefetchEnabled || !session || !this.active || index === this.prefetchIndex) { return; }
    const generation = ++this.prefetchGeneration;
    if (this.prefetchWifi && !session.offline) {
      if (Date.now() - this.prefetchAttempt < 1000) { return; } this.prefetchAttempt = Date.now();
      const allowed = await NetworkPolicy.allowed(true);
      if (generation !== this.prefetchGeneration || this.reading !== session || !this.active) { return; }
      if (!allowed) { TileWarmCache.clear(); this.renderAhead?.clear(); this.renderAhead = undefined; this.prefetch?.clear(); this.prefetchIndex = -1; return; }
    }
    if (!this.prefetch) {
      this.prefetch = new ReaderPreloader(async (page: number,scope: CancelScope) => {
        await session.cache.load(session.source,session.chapter,session.pages[page],{ callId: 'reader-prefetch',deadlineMs: Date.now() + 60000,cancel: scope,
          ruleRevision: session.source?.version || 0,priority: { value: NetworkPriority.Prefetch },trace: this.tracePage(page,'prefetch') });
      });
    }
    if (!this.usesPager() && !this.renderAhead) {
      this.renderAhead = new ReaderPreloader(async (page: number, scope: CancelScope) => {
        const asset = await session.cache.load(session.source,session.chapter,session.pages[page],{ callId: 'reader-prerender-asset',deadlineMs: Date.now() + 60000,cancel: scope,
          ruleRevision: session.source?.version || 0,priority: { value: NetworkPriority.Near },trace: this.tracePage(page,'near') });
        await TileWarmCache.page(asset,scope,this.tracePage(page,'decode-prefetch'));
      });
    }
    this.renderAhead?.update(index,this.mode === 'spread' ? 2 : 1,this.total,2);
    const count = !session.offline && session.chapter.sourceId === EHENTAI_ID ? Math.min(2,this.prefetchPages) : this.prefetchPages;
    this.prefetchIndex = index; this.prefetch.update(index,this.mode === 'spread' ? 2 : 1,this.total,count);
  }
  prioritizePage(index: number): void {
    const span = this.mode === 'spread' ? 2 : 1; const first = Math.floor(index / span) * span;
    for (let page = first; page < first + span; page++) { this.reading?.cache.prioritize?.(page); }
  }
  async pagerAsset(index: number, scope: CancelScope, foreground: boolean): Promise<ReaderAsset> {
    return this.stripAsset(index,scope,!foreground);
  }
  async allowPagerPrefetch(): Promise<boolean> {
    if (!this.active || !this.prefetchEnabled) { return false; }
    return !this.prefetchWifi || this.reading?.offline === true || await NetworkPolicy.allowed(true);
  }
  pagerCommit(index: number, asset: ReaderAsset, ratio: number, companion: ReaderAsset | undefined = undefined, focus: number = index): void {
    if (!this.active || !this.usesPager() || index < 0 || index >= this.total) { return; }
    this.clearSaveTimers(); this.index = this.mode === 'spread' && focus >= index && focus < Math.min(this.total,index + 2) ? focus : index;
    this.displayIndex = index; this.asset = asset; this.companionAsset = companion; this.companionStatus = ''; this.ratio = ratio;
    this.loadedPages.add(index); if (companion) { this.loadedPages.add(index + 1); }
    this.busy = false; this.status = '图像 ' + (this.index + 1).toString() + ' / ' + this.total.toString();
    this.save(); this.startPrefetch(index); this.prepareNext();
  }
  private async prepareNext(): Promise<void> {
    if (!this.ahead || !this.active || !this.preloadNext || !this.prefetchEnabled || this.trialMode || !this.nextId || this.index + Math.max(10,this.prefetchPages) < this.total) { return; }
    const id = this.nextId;
    if (this.prefetchWifi && !await NetworkPolicy.allowed(true)) { return; }
    if (this.active && id === this.nextId) {
      this.ahead.prepare(id,this.offlineOnly,this.skipRead,ReaderTrace.context(this.traceSessionId,this.sourceId,0,'chapter-prefetch'));
    }
  }
  scroll(ratio: number): void {
    if (!this.active || this.busy || this.pagerMoving || this.chapterChanging) { return; }
    this.ratio = Math.max(0, Math.min(1, ratio)); if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); }
    this.saveTimer = setTimeout(() => { this.save(); }, 300);
    if (this.maxSaveTimer < 0) { this.maxSaveTimer = setTimeout(() => { this.maxSaveTimer = -1; this.save(); }, 1500); }
  }
  async stripAsset(index: number, scope: CancelScope,background: boolean = false): Promise<ReaderAsset> {
    const session = this.reading; if (!this.active || !session || !session.pages[index]) { throw new AppError(ErrorCode.CANCELLED, '章节已关闭'); }
    try {
      const asset = await session.cache.load(session.source, session.chapter, session.pages[index], { callId: 'strip-' + index.toString(), deadlineMs: Date.now() + 60000, cancel: scope,
        ruleRevision: session.source?.version || 0,priority: { value: background ? NetworkPriority.Near : NetworkPriority.Visible },trace: this.tracePage(index,background ? 'near' : 'visible') });
      if (scope.cancelled || this.reading !== session || !this.active) { throw new AppError(ErrorCode.CANCELLED, '章节已关闭'); }
      this.loadedPages.add(index); return asset;
    } catch (error) { if (!scope.cancelled && this.reading === session) { this.loadedPages.delete(index); } throw error as Error; }
  }
  stripDimensions(index: number, asset: ReaderAsset): void {
    if (!this.active || this.strip.matches(index,asset)) { return; }
    if (this.isStrip()) { this.stripRestoring = true; this.stripRevision++; }
    this.strip.remember(index,asset);
  }
  stripReady(revision: number): void { if (revision === this.stripRevision) { this.stripRestoring = false; } }
  stripPosition(index: number, ratio: number): void {
    if (!this.active || this.busy || this.chapterChanging || this.stripRestoring || !this.loadedPages.has(index)) { return; }
    this.index = index; this.displayIndex = index; this.scroll(ratio); this.startPrefetch(index); this.prepareNext(); this.status = '条漫 · 图像 ' + (index + 1).toString() + ' / ' + this.total.toString();
  }
  private persistReading(): void { this.app?.preferences.reading(this.mode,this.direction,this.mangaId,{ background: this.background,scale: this.scale,tapZones: this.tapZones,invertTap: this.invertTap }).catch(() => { this.status = '阅读设置保存失败'; }); }
  async resetReading(): Promise<void> {
    if (!this.app || !this.mangaId) { return; }
    try { await this.app.preferences.resetReading(this.mangaId); const prefs = await this.app.preferences.read(); this.direction = prefs.direction; this.applyDisplay(prefs); this.switchMode(prefs.mode,false); this.status = '本漫画已恢复全局阅读设置'; }
    catch (error) { this.status = viewError(error as Error); }
  }
  switchDirection(): void { this.direction = this.direction === 'ltr' ? 'rtl' : 'ltr'; this.persistReading(); }
  switchMode(mode: string,persist: boolean = true): void {
    if (this.chapterChanging || READER_MODES.indexOf(mode) < 0 || this.mode === mode) { return; }
    this.save(); this.operation.cancel(); TileWarmCache.clear(); this.renderAhead?.clear(); this.renderAhead = undefined; this.prefetch?.clear(); this.prefetchIndex = -1;
    this.mode = mode; this.zoom = 1; this.offsetX = 0; this.stripRestoring = stripMode(mode); this.stripRevision++; this.readerEpoch++;
    if (persist) { this.persistReading(); } this.load(this.index,true);
  }
  jump(index: number): void {
    if (!this.active || this.chapterChanging || index < 0 || index >= this.total) { return; } this.save();
    if (this.isStrip()) { this.stripRestoring = true; this.index = index; this.ratio = 0; this.stripRevision++; }
    this.load(index);
  }
  turnPage(direction: number): void {
    if (this.busy || this.pagerMoving || this.chapterChanging || !this.active) { return; }
    const step = this.mode === 'spread' ? 2 : 1; const target = (this.mode === 'spread' ? this.displayIndex : this.index) + direction * step;
    if (target >= this.total) { if (!this.trialMode && this.autoNext && this.nextId) { this.changeChapter(this.nextId,true); } else { this.reachedEnd(); this.status = this.nextId ? '本章结束，可从菜单进入下一章' : '已到最后一章'; } }
    else if (target < 0) { if (!this.trialMode && this.autoNext && this.previousId) { this.changeChapter(this.previousId); } }
    else { this.jump(target); }
  }
  async changeChapter(id: string, completed: boolean = false): Promise<void> {
    if (!id || !this.app || this.trialMode || this.busy || this.pagerMoving || this.chapterChanging || !this.active) { return; }
    this.chapterChanging = true; const scope = new CancelScope(); this.chapterScope = scope;
    const nextTraceSession = ReaderTrace.newSessionId(); const changeTrace = ReaderTrace.context(nextTraceSession,this.sourceId,0,'open');
    const changeStarted = Date.now(); let changeOutcome = 'ok';
    const old = this.reading; const forward = id === this.nextId; let prepared: BookSession | undefined;
    try {
      // Save the old chapter before transferring cache ownership; failures leave it readable.
      if (!await this.persistPosition(completed) || !this.active) { changeOutcome = 'aborted'; return; }
      prepared = await this.ahead?.take(id);
      if (scope.cancelled || !this.active) { changeOutcome = scope.cancelled ? 'cancelled' : 'inactive'; return; }
      if (!prepared) { prepared = await this.app.bookReader.open(id,{ callId: 'reader-continue',deadlineMs: Date.now() + 60000,cancel: scope,ruleRevision: 1,trace: changeTrace },this.offlineOnly,this.skipRead); }
      if (scope.cancelled || !this.active || this.reading !== old) { changeOutcome = scope.cancelled ? 'cancelled' : 'superseded'; return; }
      changeTrace.sourceId = this.websiteSource(prepared.source?.id || '');
      const start = forward ? 0 : prepared.startIndex;
      const display = this.mode === 'spread' ? Math.floor(start / 2) * 2 : start;
      const assets: ReaderAsset[] = [];
      for (let index = display; index < Math.min(prepared.pages.length,display + (this.mode === 'spread' ? 2 : 1)); index++) {
        const pageTrace = ReaderTrace.context(nextTraceSession,changeTrace.sourceId,index + 1,'visible');
        const asset = await prepared.cache.load(prepared.source,prepared.chapter.ref,prepared.pages[index],{ callId: 'reader-continue-image',deadlineMs: Date.now() + 60000,
          cancel: scope,ruleRevision: prepared.source?.version || 1,trace: pageTrace });
        assets.push(asset); await TileWarmCache.page(asset,scope,ReaderTrace.context(nextTraceSession,changeTrace.sourceId,index + 1,'decode-prefetch'));
      }
      if (scope.cancelled || !this.active || this.reading !== old) { changeOutcome = scope.cancelled ? 'cancelled' : 'superseded'; return; }
      this.clearSaveTimers(); this.operation.cancel(); this.prefetchGeneration++;
      this.renderAhead?.clear(); this.renderAhead = undefined; this.prefetch?.clear(); this.prefetch = undefined; this.prefetchIndex = -1;
      const session = prepared; prepared = undefined;
      this.session = session; this.reading = { source: session.source,chapter: session.chapter.ref,pages: session.pages,cache: session.cache,offline: session.offline,partialOffline: session.partialOffline };
      this.chapterId = id; this.title = session.mangaTitle + ' · ' + session.chapter.title;
      this.sourceId = this.websiteSource(session.chapter.ref.sourceId);
      this.traceSessionId = nextTraceSession; this.traceContexts.clear();
      this.turnDirection = (forward ? 1 : -1) * (this.mode !== 'vertical' && this.direction === 'rtl' ? -1 : 1);
      this.total = session.pages.length; this.index = start; this.displayIndex = display; this.ratio = forward ? 0 : session.startRatio;
      this.completed = session.startCompleted; this.bookmarked = session.chapter.bookmarked; this.previousId = session.previousId; this.nextId = session.nextId;
      this.loadedPages.clear(); this.strip.reset(this.total);
      assets.forEach((asset: ReaderAsset,offset: number) => { this.loadedPages.add(display + offset); this.strip.remember(display + offset,asset); });
      this.asset = assets[0]; this.companionAsset = assets.length > 1 ? assets[1] : undefined; this.companionStatus = '';
      this.readerEpoch++; this.stripRevision++; this.stripRestoring = this.isStrip();
      this.status = '图像 ' + (start + 1).toString() + ' / ' + this.total.toString();
      old?.cache.dispose(); this.startPrefetch(display); this.prepareNext();
    } catch (error) { changeOutcome = error instanceof AppError ? error.code : 'failed'; if (!scope.cancelled && this.active) { this.status = viewError(error as Error); } }
    finally { if (scope.cancelled && changeOutcome === 'ok') { changeOutcome = 'cancelled'; }
      ReaderTrace.record(changeTrace,'chapter-change',Date.now() - changeStarted,changeOutcome,'',prepared?.pages.length || this.total);
      prepared?.cache.dispose(); if (this.chapterScope === scope) { this.chapterScope = undefined; this.chapterChanging = false; } }
  }
  continueChapter(): void {
    if (this.autoNext && !this.trialMode && this.nextId && this.active && !this.busy && !this.chapterChanging) { this.changeChapter(this.nextId,true); }
  }
  reachedEnd(atEnd: boolean = false): void {
    if (!this.active || this.busy || this.completed || this.finishing || !this.loadedPages.has(this.total - 1) || !atEnd && this.displayIndex + (this.mode === 'spread' ? 2 : 1) < this.total) { return; }
    this.finishing = true; this.save(true).finally(() => { this.finishing = false; });
  }
  async toggleBookmark(): Promise<void> {
    if (!this.app || !this.session || this.busy) { return; }
    try { await this.app.progress.bookmark(this.session.chapter.id,!this.bookmarked); this.bookmarked = !this.bookmarked; }
    catch (error) { this.status = viewError(error as Error); }
  }
  isOfflineOnly(): boolean { return this.offlineOnly; }
  focusSpread(index: number, ratio: number = 0): void {
    if (this.busy || this.pagerMoving || this.mode !== 'spread' || this.index === index || index < this.displayIndex || index > this.displayIndex + 1) { return; }
    this.save(); this.index = index; this.scroll(ratio);
  }
  async download(): Promise<void> { if (!this.app) { return; } try { await this.app.downloads.enqueue(this.chapterId); this.status = '本章已加入下载队列'; } catch (error) { this.status = viewError(error as Error); } }
  async save(completed: boolean = false): Promise<void> {
    await this.persistPosition(completed);
  }
  private async persistPosition(completed: boolean = false): Promise<boolean> {
    if (!this.app || !this.reading || !this.loadedPages.has(this.index)) { return true; }
    const index = this.index; const ratio = this.ratio; const page = this.reading.pages[index]; const updatedAt = Date.now();
    if (!page) { return true; }
    if (this.incognito) { if (completed) { this.completed = true; this.status = '隐身阅读：本章已结束，未保存进度'; } return true; }
    try {
      if (this.trialMode) { await this.app.trialPositions.save(this.reading.chapter,page.pageKey,index,ratio,updatedAt); }
      else if (this.session) { await this.app.bookReader.save(this.session,index,ratio,completed); }
      if (completed) { this.completed = true; this.status = '本章已标记读完'; } return true;
    }
    catch (error) { this.status = '进度保存失败：' + viewError(error as Error); return false; }
  }
  async retry(): Promise<void> {
    if (!this.reading || this.busy || this.pagerMoving || this.chapterChanging) { return; }
    if (this.usesPager()) { this.readerEpoch++; return; }
    if (this.isStrip()) { this.retryStripPage(this.index); return; }
    TileWarmCache.clear(); this.reading.cache.forget(this.displayIndex);
    if (this.mode === 'spread' && this.displayIndex + 1 < this.total) { TileWarmCache.clear(); this.reading.cache.forget(this.displayIndex + 1); }
    await this.load(this.index,true);
  }
  retryStripPage(index: number): void {
    if (!this.active || !this.reading) { return; }
    TileWarmCache.clear(); this.reading.cache.forget(index); this.loadedPages.delete(index); this.stripRestoring = true; this.stripRevision++; this.strip.invalidate(index);
  }
  cancel(): void { this.operation.cancel(); this.busy = false; this.status = '已取消，当前图像保留'; }
  setPageVisible(visible: boolean): void { this.pageVisible = visible; this.updateActive(); }
  private updateActive(): void {
    const active = this.pageVisible && this.foreground; if (active === this.active) { return; }
    this.active = active; if (active) { this.resume(); } else { this.suspend(); }
  }
  private clearSaveTimers(): void {
    if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
    if (this.maxSaveTimer >= 0) { clearTimeout(this.maxSaveTimer); this.maxSaveTimer = -1; }
  }
  suspend(): void {
    this.chapterScope?.cancel();
    this.clearSaveTimers(); this.save(); this.operation.cancel(); TileWarmCache.clear(); this.renderAhead?.clear(); this.renderAhead = undefined; this.prefetch?.clear(); this.prefetchIndex = -1; this.prefetchGeneration++; this.ahead?.clear();
    this.asset = undefined; this.companionAsset = undefined; this.reading?.cache.park(); this.busy = false;
  }
  resume(): void { this.readerEpoch++; if (!this.active) { return; } if (this.reading) { this.load(this.index,true); } else { this.open(); } }
  dispose(): void {
    this.chapterScope?.cancel();
    this.clearSaveTimers(); this.save(); this.operation.close(); this.active = false;
    if (this.lifecycle) { this.lifecycle(); this.lifecycle = undefined; }
    TileWarmCache.clear(); this.renderAhead?.clear(); this.renderAhead = undefined; this.prefetch?.clear(); this.ahead?.clear(); if (this.reading) { this.reading.cache.dispose(); } this.asset = undefined; this.companionAsset = undefined; this.busy = false;
    ReaderTrace.flush().catch(() => {});
  }
}
