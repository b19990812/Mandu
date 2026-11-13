import { TileDecoder } from '../image/TileDecoder';
import { DecodeScheduler } from '../image/DecodeScheduler';
import { ReaderPerf } from '../diagnostic/ReaderPerf';
import { NativeCurlSurface } from './NativeCurlSurface';
import { CurlGpuBridge } from '../reader/CurlGpuBridge';
import { CurlGesture } from '../reader/CurlGesture';
import { SpreadViewer } from './SpreadViewer';
import { CurlFrameStore } from '../reader/CurlFrameStore';
import { CurlSnapshotQueue } from '../reader/CurlSnapshotQueue';
import { curlSnapshotScale, turnCompletes, spreadMargin } from '../reader/PageTurnGeometry';
import { image } from '@kit.ImageKit';
import { FrameCallback } from '@kit.ArkUI';

import { ReaderVM } from '../vm/ReaderVM';
import { ReaderAsset } from '../image/ReaderAssetCache';
import { PagerSlot, PagerWindow } from '../reader/PagerWindow';
import { ReadingCanvas } from './ReadingCanvas';
import { readerBackground } from '../model/ReaderDisplay';
import { ErrorCode } from '../model/ErrorTypes';

class ReleaseCurlFrames extends FrameCallback {
  private maps: image.PixelMap[];
  constructor(maps: image.PixelMap[]) { super(); this.maps = maps; }
  onIdle(_remaining: number): void { this.maps.forEach((map: image.PixelMap) => { map.release().catch(() => {}); }); this.maps = []; }
}

class TurnFrame extends FrameCallback {
  private readonly advance: () => void;
  constructor(advance: () => void) { super(); this.advance = advance; }
  onFrame(_time: number): void { this.advance(); }
}

class PrepareTurnFrames extends FrameCallback {
  private readonly prepare: () => void;
  constructor(prepare: () => void) { super(); this.prepare = prepare; }
  onIdle(_remaining: number): void { this.prepare(); }
}

@Component
struct PagerSurface {
  // ForEach keeps this slot's identity stable; loadRevision publishes async changes.
  slot: PagerSlot = new PagerSlot(-1, 'unbound');
  @ObjectLink vm: ReaderVM;
  @Prop selected: boolean = false;
  @Prop moving: boolean = false;
  @Prop zoom: number = 1;
  @Prop viewportWidth: number = 1;
  @Prop @Watch('refresh') loadRevision: number = 0;
  @State private displayAsset: ReaderAsset | undefined = undefined;
  @State private displayStatus: string = '正在准备图片…';
  @State private displayFailed: boolean = false;
  onReady: (index: number, ready: boolean) => void = () => {};
  onFailure: (index: number, message: string) => void = () => {};
  onZoom: (zoom: number) => void = () => {};
  onTurn: (direction: number) => void = () => {};
  onMenu: () => void = () => {};
  onRetry: () => void = () => {};
  onRetryPage: (index: number) => void = () => {};
  onViewportSettled: (index: number) => void = () => {};
  aboutToAppear(): void { this.refresh(); }
  private refresh(): void { this.displayAsset = this.slot.asset; this.displayStatus = this.slot.status; this.displayFailed = this.slot.failed; }
  build() {
    Stack() {
      if (this.slot.span === 2) {
        SpreadViewer({ vm: this.vm,slot: this.slot,selected: this.selected,moving: this.moving,zoom: this.zoom,viewportWidth: this.viewportWidth,loadRevision: this.loadRevision,
          onReady: this.onReady,onFailure: this.onFailure,onZoom: this.onZoom,onTurn: this.onTurn,onMenu: this.onMenu,onRetry: this.onRetryPage,onViewportSettled: this.onViewportSettled })
      } else if (this.displayAsset) {
        ReadingCanvas({ asset: this.displayAsset, ratio: this.slot.ratio, zoom: this.selected ? this.zoom : 1,
          backdrop: this.vm.background, scaleMode: this.vm.scale, tapZones: this.vm.tapZones, invertTap: this.vm.invertTap,
          externalPaging: true, interactive: this.selected && !this.moving,
          onReady: (ready: boolean) => this.onReady(this.slot.index,ready),
          onFailure: (message: string) => { this.slot.failed = true; this.slot.status = message; this.onFailure(this.slot.index,message); },
          onPosition: (ratio: number) => { if (this.selected && !this.moving) { this.slot.ratio = ratio; this.vm.scroll(ratio); } },
          onEnd: () => { if (this.selected && !this.moving) { this.vm.reachedEnd(); } },
          onZoom: this.onZoom, onTapTurn: this.onTurn, onMenu: this.onMenu,onViewportSettled: () => this.onViewportSettled(this.slot.index) })
      } else {
        Column({ space: 16 }) {
          Text('第 ' + (this.slot.index + 1).toString() + ' 页').fontColor('#FFFFFF')
          Text(this.displayStatus).fontColor('#CBD8D4').fontSize(14)
          if (this.displayFailed) { Button('重试图片').onClick(this.onRetry) }
          else { LoadingProgress().width(32).height(32) }
          if (this.selected) { Button('阅读菜单').onClick(this.onMenu) }
        }.padding(24)
      }
    }.id('pager-surface-' + this.slot.key).width('100%').height('100%').backgroundColor(readerBackground(this.vm.background))
  }
}

@Component
export struct HorizontalPager {
  @ObjectLink vm: ReaderVM;
  @Prop @Watch('requested') requestRevision: number = 0;
  @Prop @Watch('reset') epoch: number = 0;
  @Prop @Watch('visualChanged') zoom: number = 1;
  @Prop readingDirection: string = 'ltr';
  @Prop @Watch('visualChanged') visualKey: string = '';
  @Prop gestures: boolean = true;
  onZoom: (zoom: number) => void = () => {};
  onMenu: () => void = () => {};
  @State private window: PagerWindow = new PagerWindow();
  private dragOffset: number = 0;
  @State private slideOffset: number = 0;
  @State private viewportWidth: number = 1;
  @State private moving: boolean = false;
  @State @Watch('hintChanged') private hint: string = '';
  @State private edgeStretch: number = 1;
  @State private retryIndex: number = -1;
  @State private loadRevision: number = 0;
  @State private chapterCover: PagerSlot | undefined = undefined;
  private curlFront: image.PixelMap | undefined = undefined;
  private curlBehind: image.PixelMap | undefined = undefined;
  private curlProgress: number = 0;
  private curlReverse: boolean = false;
  private curlBook: boolean = false;
  private readonly gpu: CurlGpuBridge = new CurlGpuBridge();
  private readonly curlGesture: CurlGesture = new CurlGesture();
  private touchY: number = 0;
  private handingOff: boolean = false;
  private setOffset(value: number): void { this.dragOffset = value; if (!this.curls()) { this.slideOffset = value; } }
  private drawCurl(): number {
    const current = this.window.find(this.window.center); const next = this.window.find(this.curlTarget);
    if (!current || !next || !this.curlFront || !this.curlBehind) { return 0; }
    const sequence = this.gpu.present(this.frameKey(current),this.frameKey(next),this.curlProgress,this.curlGesture.corner,
      this.curlGesture.fingerY,this.curlReverse,this.curlBook,this.curlGesture.velocity,spreadMargin(this.viewportWidth) / this.viewportWidth);
    if (ReaderPerf.firstFrame(sequence)) {
      const turn = ReaderPerf.turns; const generation = this.generation;
      const acknowledged = (): void => {
        if (!this.visible || !ReaderPerf.enabled || turn !== ReaderPerf.turns || generation !== this.generation) { return; }
        if (this.gpu.presented(sequence)) { ReaderPerf.firstSwapped(sequence); }
        else { this.getUIContext().postFrameCallback(new TurnFrame(acknowledged)); }
      };
      this.getUIContext().postFrameCallback(new TurnFrame(acknowledged));
    }
    return sequence;
  }
  private curlTarget: number = -1;
  private textureGeneration: number = 0;
  private readonly frames: CurlFrameStore = new CurlFrameStore((maps: image.PixelMap[]) => this.retireFrames(maps));
  private readonly captureJobs: Map<string,Promise<void>> = new Map();
  private readonly snapshots: CurlSnapshotQueue = new CurlSnapshotQueue();
  private preferredDirection: number = 1;
  private viewportHeight: number = 1;
  private retireFrames(maps: image.PixelMap[]): void {
    // PixelMap reads can still be running on a native worker when a slot expires.
    this.gpu.drain().then(() => {
      if (!this.visible) { maps.forEach((map: image.PixelMap) => { map.release().catch(() => {}); }); return; }
      this.getUIContext().postFrameCallback(new ReleaseCurlFrames(maps));
    });
  }
  private releaseCurl(): void {
    this.gpu.clear();
    this.curlFront = undefined; this.curlBehind = undefined; this.curlTarget = -1; this.curlProgress = 0;
    this.syncCurlPriority();
  }
  private curls(): boolean { return this.vm.mode === 'curl' || this.vm.mode === 'spread'; }
  private frameKey(slot: PagerSlot): string { return this.textureGeneration.toString() + ':' + slot.key + ':' + slot.paintRevision.toString() + ':' + (slot.companion?.paintRevision || 0).toString() + ':' + slot.ratio.toString() + ':' + (slot.companion?.ratio || 0).toString(); }
  private frameKeys(): string[] { return this.window.slots.map((slot: PagerSlot) => this.frameKey(slot)); }
  private orderedSlots(): PagerSlot[] {
    const target = this.decodeTarget >= 0 ? this.decodeTarget : this.pending;
    return this.window.slots.slice().sort((a: PagerSlot,b: PagerSlot) => {
      const rank = (slot: PagerSlot): number => slot.index === this.window.center ? 0 : slot.index === target ? 1 :
        (slot.index - this.window.center) * this.preferredDirection > 0 ? 2 : 3;
      return rank(a) - rank(b);
    });
  }
  private syncCurlPriority(): void {
    const keys = this.visible && this.curls() ? this.orderedSlots().map((slot: PagerSlot) => this.frameKey(slot)) : [];
    this.snapshots.order(keys,this.curlFront !== undefined);
    this.gpu.prioritize(keys);
  }
  private prepareCurl(index: number): boolean {
    const current = this.window.find(this.window.center); const next = this.window.find(index);
    if (!current?.complete() || !next?.complete()) { return false; }
    const front = this.frames.get(this.frameKey(current)); const behind = this.frames.get(this.frameKey(next));
    if (!front || !behind || !this.gpu.ready(this.frameKey(current)) || !this.gpu.ready(this.frameKey(next))) { this.capture(current); this.capture(next); return false; }
    this.curlFront = front; this.curlBehind = behind; this.curlTarget = index;
    this.curlBook = this.vm.mode === 'spread';
    this.curlReverse = (index - this.window.center) * this.sign() < 0; this.syncCurlPriority(); return true;
  }
  private capture(slot: PagerSlot): Promise<void> {
    if (!this.visible || !this.curls() || this.zoom > 1 || !slot.complete()) { return Promise.resolve(); }
    const key = this.frameKey(slot); if (this.gpu.ready(key)) { return Promise.resolve(); }
    const existing = this.captureJobs.get(key); if (existing) { return existing; }
    this.syncCurlPriority();
    // Share the whole snapshot/upload/completion chain, not only its two inner jobs.
    // A slow upload must not add one continuation and native retain per finger update.
    const job = this.captureFrame(slot,key,this.textureGeneration).finally(() => {
      if (this.captureJobs.get(key) === job) { this.captureJobs.delete(key); }
    });
    this.captureJobs.set(key,job); return job;
  }
  private async captureFrame(slot: PagerSlot,key: string,generation: number): Promise<void> {
    this.frames.retain(this.frameKeys());
    this.gpu.retain(this.frameKeys());
    const scale = curlSnapshotScale(this.getUIContext().vp2px(this.viewportWidth),this.getUIContext().vp2px(this.viewportHeight));
    const snapshotAt = ReaderPerf.enabled ? Date.now() : 0;
    const captured = await this.frames.capture(key,() => this.snapshots.capture(key,() => this.getUIContext().getComponentSnapshot().get('pager-surface-' + slot.key,{ scale: scale,waitUntilRenderFinished: true })));
    if (!this.visible || generation !== this.textureGeneration || this.window.find(slot.index) !== slot || this.frameKey(slot) !== key || !slot.complete()) { return; }
    ReaderPerf.event('snapshot',Date.now() - snapshotAt,key);
    const map = this.frames.get(key);
    const uploadAt = ReaderPerf.enabled ? Date.now() : 0;
    const uploaded = captured && map ? await this.gpu.cache(key,map) : false;
    if (ReaderPerf.enabled) { ReaderPerf.event('native-cache',Date.now() - uploadAt,this.gpu.metrics()); }
    if (!this.visible || generation !== this.textureGeneration || this.window.find(slot.index) !== slot || this.frameKey(slot) !== key) { return; }
    if (!uploaded) {
      if (this.pending >= 0 && (slot.index === this.pending || slot.index === this.window.center)) { this.hint = '翻页画面准备失败，点击重试'; this.retryIndex = this.pending; this.cancelPending(); }
      return;
    }
    if (this.dragging) { this.dragTo(this.lastOffset); }
    else if (this.pending >= 0 && !this.settling && this.pending !== this.window.center) {
      const target = this.window.find(this.pending); const current = this.window.find(this.window.center);
      if (target?.complete() && current && this.gpu.ready(this.frameKey(target)) && this.gpu.ready(this.frameKey(current))) { this.settle(target.index); }
    }
  }
  private visualChanged(): void {
    this.cancelMotion(); this.textureGeneration++; this.frames.clear();
    this.gpu.retain([]);
    this.snapshots.order([],false);
    if (this.visible) { this.getUIContext().postFrameCallback(new PrepareTurnFrames(() => this.captureReady())); }
  }
  private captureReady(): void { if (this.visible) { this.syncCurlPriority(); this.orderedSlots().forEach((slot: PagerSlot) => this.capture(slot)); } }
  private viewportSettled(index: number): void {
    const slot = this.window.find(this.window.group(index));
    if (slot && !this.moving) { this.capture(slot); }
  }
  private cancelPending(): void { this.pending = -1; this.setMoving(false); }
  private commit(slot: PagerSlot, restore: boolean = false): void {
    const focus = restore && this.vm.index >= slot.index && this.vm.index < slot.index + this.window.span ? this.vm.index : slot.index;
    const ratio = focus === slot.index ? slot.ratio : slot.companion?.ratio || 0;
    this.vm.pagerCommit(slot.index,slot.asset!,ratio,slot.companion?.asset,focus); this.decodeTarget = -1; this.updateDecodeFocus();
  }
  private visible: boolean = false;
  private initialized: boolean = false;
  private dragging: boolean = false;
  private settling: boolean = false;
  private generation: number = 0;
  private pending: number = -1;
  private lastOffset: number = 0;
  private neighbourGeneration: number = 0;
  private anchorOffset: number = 0;
  private held: boolean = false;
  private animationTarget: number = -1;
  private decodeTarget: number = -1;
  private updateDecodeFocus(): void {
    const uris: string[] = [];
    const indices = this.decodeTarget >= 0 ? [this.window.center,this.decodeTarget] : [this.window.center];
    indices.forEach((index: number) => { const slot = this.window.find(index); if (slot?.asset) { uris.push(slot.asset.uri); } if (slot?.companion?.asset) { uris.push(slot.companion.asset.uri); } });
    DecodeScheduler.focus(uris);
    this.syncCurlPriority();
  }
  private probeTimer: number = -1;
  private probeTurns: number = 0;
  private probeDirection: number = 1;
  private probeNext: number = 0;
  private hintChanged(): void { ReaderPerf.hint(this.hint); }
  private probeTick(): void {
    if (!ReaderPerf.enabled || !this.vm.trialMode || this.vm.sourceId || !this.visible || !this.initialized || this.moving || Date.now() < this.probeNext) { return; }
    if (this.probeTurns >= 64) { clearInterval(this.probeTimer); this.probeTimer = -1; ReaderPerf.hint(''); const state = DecodeScheduler.counts(); ReaderPerf.event('decode-state',0,JSON.stringify([state.limit,state.active,state.waiting,state.preloadActive,state.peakActive,TileDecoder.liveBytes(),TileDecoder.reservedBytes()])); ReaderPerf.event('done',0,this.gpu.metrics()); ReaderPerf.enabled = false; return; }
    if (this.window.center + this.probeDirection * this.window.span < 0 || this.window.center + this.probeDirection * this.window.span >= this.window.total) { this.probeDirection *= -1; }
    if (this.window.total <= this.window.span) { ReaderPerf.event('run-error',0,'not-enough-synthetic-pages'); clearInterval(this.probeTimer); return; }
    this.turn(this.probeDirection * this.sign()); this.probeTurns++; this.probeNext = Date.now() + 750;
  }
  aboutToAppear(): void { this.visible = true; this.reset(); if (ReaderPerf.enabled && ReaderPerf.automatic) { this.probeNext = Date.now() + 1500; this.probeTimer = setInterval(() => this.probeTick(),100); } }
  aboutToDisappear(): void { if (this.probeTimer >= 0) { clearInterval(this.probeTimer); } this.visible = false; this.cancelMotion(); DecodeScheduler.focus([]); this.textureGeneration++; this.frames.clear(); this.neighbourGeneration++; this.chapterCover?.dispose(); this.chapterCover = undefined; this.window.clear(); }
  private reset(): void {
    if (!this.visible) { return; }
    this.visualChanged(); this.neighbourGeneration++; this.initialized = false;
    const previous = this.window.detachCenter();
    this.chapterCover?.dispose(); this.chapterCover = previous;
    this.window.onFailure = (index: number, message: string) => this.failed(index,message);
    this.window.onChange = (_index: number) => { if (this.visible) { this.updateDecodeFocus(); this.loadRevision++; } };
    this.window.reset(this.vm.index,this.vm.total,this.vm.ratio,(index,scope) => this.vm.pagerAsset(index,scope),this.vm.mode === 'spread' ? 2 : 1);
    this.pending = this.window.center;
  }
  private sign(): number { return this.readingDirection === 'rtl' ? -1 : 1; }
  private setMoving(value: boolean): void { this.moving = value; if (this.vm.pagerMoving !== value) { this.vm.pagerMoving = value; } }
  private cancelMotion(): void {
    this.decodeTarget = -1; this.updateDecodeFocus(); this.releaseCurl(); this.generation++; this.dragging = false; this.settling = false; this.pending = -1; this.held = false; this.anchorOffset = 0; this.handingOff = false;
    this.setOffset(0); this.slideOffset = 0; this.edgeStretch = 1; this.retryIndex = -1; this.lastOffset = 0; this.setMoving(false); this.hint = '';
  }
  private failed(index: number, message: string): void {
    const page = this.window.page(index); if (page) { page.failed = true; page.status = message; page.ready = false; }
    if (this.visible) { this.loadRevision++; }
    if (this.visible && (this.pending === this.window.group(index) || this.chapterCover && this.window.group(index) === this.window.center)) { this.hint = message; this.retryIndex = index; this.cancelPending(); }
  }
  private async neighbours(): Promise<void> {
    const generation = ++this.neighbourGeneration;
    if (await this.vm.allowPagerPrefetch() && this.visible && generation === this.neighbourGeneration) { this.window.neighbours(); }
  }
  private ready(index: number, ready: boolean): void {
    const page = this.window.page(index); const slot = this.window.find(this.window.group(index)); if (!page || !slot) { return; }
    const previousKey = this.frameKey(slot);
    page.ready = ready; if (ready) { page.failed = false; page.status = ''; }
    else {
      page.paintRevision++;
      this.frames.invalidate(previousKey); this.frames.retain(this.frameKeys()); this.gpu.retain(this.frameKeys());
    }
    if (!this.visible || !slot.complete()) { return; }
    ReaderPerf.event('viewport-ready',0,slot.index.toString());
    this.capture(slot);
    if (slot.index === this.window.center && this.chapterCover) { this.chapterCover.dispose(); this.chapterCover = undefined; }
    if (this.pending === slot.index && !this.dragging && !this.settling) {
      if (slot.index === this.window.center) { this.pending = -1; this.initialized = true; this.commit(slot,true); this.neighbours(); }
      else { this.settle(slot.index); }
    } else if (slot.index === this.window.center && !this.moving) { if (!this.initialized) { this.initialized = true; this.commit(slot,true); } this.neighbours(); }
  }
  private acceptReady(slot: PagerSlot,index: number,ready: boolean): void {
    if (slot !== this.chapterCover && this.window.find(this.window.group(index)) === slot) { this.ready(index,ready); }
  }
  private acceptFailure(slot: PagerSlot,index: number,message: string): void {
    if (slot !== this.chapterCover && this.window.find(this.window.group(index)) === slot) { this.failed(index,message); }
  }
  private requested(): void {
    // @Watch runs during the parent's render. Start the command after that render
    // so request/settle cannot mutate the parent's ReaderVM from inside build().
    const revision = this.requestRevision;
    Promise.resolve().then(() => {
      if (this.visible && !this.settling && revision === this.requestRevision) { this.request(this.vm.pagerTarget); }
    });
  }
  private loadTarget(index: number): PagerSlot | undefined {
    const slot = this.window.ensure(index);
    if (slot?.errorCode === ErrorCode.BROWSER_RETRY_ON_DISPLAY) { this.window.retry(slot.index); }
    if (slot?.companion?.errorCode === ErrorCode.BROWSER_RETRY_ON_DISPLAY) { this.window.retry(slot.companion.index); }
    this.vm.prioritizePage(index);
    return slot;
  }
  private request(index: number): void {
    if (!this.visible || this.vm.chapterChanging || this.chapterCover || this.settling || this.dragging) { return; }
    this.neighbourGeneration++; this.retryIndex = -1;
    if (this.window.group(index) === this.window.center) { this.cancelMotion(); if (this.vm.mode === 'spread') { this.vm.focusSpread(index,this.window.page(index)?.ratio || 0); } return; }
    index = this.window.group(index);
    ReaderPerf.turn(index);
    this.curlGesture.begin(this.viewportHeight,this.viewportHeight);
    this.pending = index;
    this.preferredDirection = Math.sign(index - this.window.center) || this.preferredDirection;
    this.decodeTarget = index; const slot = this.loadTarget(index); this.updateDecodeFocus();
    if (!slot) { this.pending = -1; this.hint = ''; return; }
    const failed = slot.failed ? slot : slot.companion?.failed ? slot.companion : undefined;
    this.hint = failed ? failed.status : slot.complete() ? '' : '正在准备目标页…';
    if (failed) { this.retryIndex = failed.index; }
    if (slot.complete()) { this.settle(index); }
  }
  private turn(physical: number): void {
    if (this.moving || this.vm.chapterChanging || this.chapterCover) { return; }
    const logical = physical * this.sign();
    const target = this.window.center + logical * this.window.span;
    if (target < 0 || target >= this.window.total) { this.vm.turnPage(logical); return; }
    this.request(target);
  }
  private start(event: GestureEvent): void {
    if (this.handingOff || this.vm.chapterChanging || this.chapterCover || !this.gestures || this.zoom > 1 || !this.window.find(this.window.center)?.complete()) { return; }
    ReaderPerf.event('gesture-start');
    if (!this.held) { this.curlGesture.begin(this.touchY,this.viewportHeight); } else { this.curlGesture.resume(this.viewportHeight); }
    this.generation++; this.settling = false; this.held = false; this.anchorOffset = this.dragOffset;
    this.neighbourGeneration++; this.pending = -1; this.retryIndex = -1; this.dragging = true; this.setMoving(true); this.drag(event);
  }
  private drag(event: GestureEvent): void {
    if (!this.dragging || this.zoom > 1) { return; }
    this.curlGesture.move(event.offsetY,this.viewportHeight,event.velocityX,this.viewportWidth);
    const travel = this.curls() ? this.curlGesture.travel(this.viewportWidth,this.curlBook) : this.viewportWidth;
    this.dragTo(Math.max(-travel,Math.min(travel,this.anchorOffset + event.offsetX)));
  }
  private dragTo(delta: number): void {
    this.lastOffset = delta;
    const logical = (delta < 0 ? 1 : -1) * this.sign(); const target = this.window.center + logical * this.window.span;
    this.preferredDirection = logical;
    this.decodeTarget = target; const slot = this.loadTarget(target); this.updateDecodeFocus();
    if (!slot?.complete()) {
      if (this.curls()) { this.releaseCurl(); }
      this.setOffset(0);
      this.curlProgress = 0; this.edgeStretch = this.curls() ? 1 : 1 + Math.min(0.015,Math.abs(delta) / this.viewportWidth * 0.04);
      const failed = slot?.failed ? slot : slot?.companion?.failed ? slot.companion : undefined;
      this.hint = failed ? failed.status : slot ? '正在准备目标页…' : '';
      return;
    }
    this.edgeStretch = 1; this.hint = '';
    if (this.curls()) {
      if (!this.prepareCurl(target)) { this.releaseCurl(); this.setOffset(0); this.hint = '正在准备翻页纹理…'; return; }
      this.curlProgress = this.curlGesture.progress(delta,this.viewportWidth,this.curlBook);
      this.drawCurl();
    }
    this.setOffset(delta);
  }
  private end(event: GestureEvent): void {
    if (!this.dragging) { return; } this.dragging = false;
    ReaderPerf.event('gesture-end',0,this.lastOffset.toString());
    const logical = (this.lastOffset < 0 ? 1 : -1) * this.sign(); const target = this.window.center + logical * this.window.span;
    const complete = turnCompletes(this.dragOffset,this.viewportWidth,event.velocityX);
    if ((target < 0 || target >= this.window.total) && turnCompletes(this.lastOffset,this.viewportWidth,event.velocityX)) {
      this.cancelMotion(); this.vm.turnPage(logical); return;
    }
    this.settle(complete && this.window.find(target)?.complete() ? target : this.window.center);
  }
  private settle(index: number): void {
    const slot = this.window.find(index); if (!slot?.complete() || !this.visible) { this.cancelMotion(); return; }
    if (index === this.window.center && !this.dragOffset) { this.cancelMotion(); return; }
    if (this.curls() && index !== this.window.center && !this.prepareCurl(index)) {
      this.pending = index; this.setMoving(true); this.hint = '正在准备翻页画面…'; return;
    }
    if (this.curls() && index === this.window.center && !this.curlFront) { this.cancelMotion(); return; }
    const generation = ++this.generation; this.settling = true; this.setMoving(true); this.pending = -1;
    this.animationTarget = index; this.held = false; this.hint = ''; this.edgeStretch = 1;
    const travel = this.curls() ? this.curlGesture.travel(this.viewportWidth,this.curlBook) : this.viewportWidth;
    const start = this.dragOffset; const end = -Math.sign(index - this.window.center) * this.sign() * travel;
    const startY = this.curlGesture.fingerY;
    const began = Date.now(); const duration = Math.max(140,(this.curls() ? 460 : 250) * Math.abs(end - start) / travel);
    const inertia = this.curls() && end !== start ? Math.max(0,Math.min(2,this.curlGesture.velocity * this.viewportWidth * duration / 1000 / (end - start))) : 0;
    const automatic = this.curls() && start === 0 && startY === this.curlGesture.corner;
    const advance = (): void => {
      if (!this.visible || generation !== this.generation) { return; }
      const elapsed = Math.min(1,(Date.now() - began) / duration);
      const eased = elapsed * elapsed * elapsed * (10 - 15 * elapsed + 6 * elapsed * elapsed) +
        inertia * (elapsed - 6 * Math.pow(elapsed,3) + 8 * Math.pow(elapsed,4) - 3 * Math.pow(elapsed,5));
      this.setOffset(start + (end - start) * eased);
      if (this.curls()) {
        this.curlProgress = this.curlGesture.progress(this.dragOffset,this.viewportWidth,this.curlBook);
        this.curlGesture.fingerY = automatic ? this.curlGesture.corner + (this.curlGesture.corner ? -0.16 : 0.16) * Math.sin(Math.PI * this.curlProgress) :
          startY + (this.curlGesture.corner - startY) * eased;
      }
      const sequence = this.curls() ? this.drawCurl() : 0;
      if (elapsed < 1) { this.getUIContext().postFrameCallback(frame); return; }
      this.handingOff = true;
      const wait = (): void => {
        if (!this.visible || generation !== this.generation) { return; }
        if (this.curls() && !this.gpu.presented(sequence)) {
          if (!sequence || Date.now() - began > duration + 1500) { this.cancelMotion(); this.hint = '卷页渲染未完成，当前页已保留'; return; }
          this.getUIContext().postFrameCallback(new TurnFrame(wait)); return;
        }
        if (ReaderPerf.enabled) { ReaderPerf.event('swap-ack',0,this.gpu.metrics()); }
        if (index !== this.window.center && this.window.commit(index)) { this.commit(slot); ReaderPerf.committed(index); }
        this.setOffset(0); this.lastOffset = 0;
        // The exact final target remains on the GPU while ArkUI renders its
        // newly committed page. Clear the overlay only after that handoff.
        this.getUIContext().postFrameCallback(new TurnFrame(() => this.getUIContext().postFrameCallback(new TurnFrame(() => {
          if (!this.visible || generation !== this.generation) { return; }
          this.releaseCurl(); this.handingOff = false; this.settling = false; this.setMoving(false); this.hint = '';
          this.frames.retain(this.frameKeys()); this.gpu.retain(this.frameKeys()); this.neighbours(); this.captureReady();
        }))));
      };
      wait();
    };
    const frame = new TurnFrame(advance);
    this.getUIContext().postFrameCallback(frame);
  }
  private motionTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down && event.touches.length === 1) { this.touchY = event.touches[0].y; }
    if (event.touches.length > 1) { if (this.moving) { this.cancelMotion(); } return; }
    if (event.type === TouchType.Down && !this.handingOff && this.settling && this.gestures && this.zoom <= 1) {
      this.generation++; this.settling = false; this.held = true;
    } else if ((event.type === TouchType.Up || event.type === TouchType.Cancel) && this.held && !this.dragging) {
      this.held = false; this.settle(event.type === TouchType.Cancel ? this.window.center : this.animationTarget);
    }
  }
  private retry(index: number): void {
    const page = this.window.page(index); this.hint = ''; this.retryIndex = -1;
    if (page?.failed) { this.window.retry(index); } this.request(index);
  }
  private pageOffset(index: number): number { if (this.curls()) { return index === this.window.center ? 0 : this.viewportWidth * 2; } return Math.sign(index - this.window.center) * this.sign() * this.viewportWidth + this.slideOffset; }
  private surfaces(): PagerSlot[] { return this.chapterCover ? this.window.slots.concat([this.chapterCover]) : this.window.slots; }
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      ForEach(this.surfaces(),(slot: PagerSlot) => {
        PagerSurface({ slot: slot,vm: this.vm,selected: slot !== this.chapterCover && slot.index === this.window.center,moving: this.moving,zoom: this.zoom,viewportWidth: this.viewportWidth,loadRevision: this.loadRevision,
          onReady: (index: number,ready: boolean) => this.acceptReady(slot,index,ready),onFailure: (index: number,message: string) => this.acceptFailure(slot,index,message),onZoom: this.onZoom,onTurn: (direction: number) => this.turn(direction),
          onMenu: this.onMenu,onRetry: () => this.retry(slot.index),onRetryPage: (index: number) => this.retry(index),onViewportSettled: (index: number) => this.viewportSettled(index) })
          .translate({ x: slot === this.chapterCover ? 0 : this.pageOffset(slot.index) }).scale({ x: slot.index === this.window.center ? this.edgeStretch : 1, y: 1 })
          .hitTestBehavior(!this.chapterCover && slot.index === this.window.center ? HitTestMode.Default : HitTestMode.None)
      },(slot: PagerSlot) => slot.key)
      NativeCurlSurface({ controller: this.gpu,onReady: () => this.captureReady() })
      if (this.hint) {
        Column({ space: 8 }) {
          Text(this.hint).fontColor('#FFFFFF').fontSize(13).maxLines(3)
          if (this.retryIndex >= 0) { Button('重试目标页').onClick(() => this.retry(this.retryIndex)) }
        }.padding(12).backgroundColor('#D02B3430').borderRadius(8).margin({ bottom: 48 })
      }
    }.width('100%').height('100%').clip(true).backgroundColor(readerBackground(this.vm.background))
      .onAreaChange((_old: Area,area: Area) => {
        const height = Number(area.height); const width = Number(area.width);
        if (width > 0 && height > 0 && (Math.abs(width - this.viewportWidth) > 1 || Math.abs(height - this.viewportHeight) > 1)) {
          this.viewportWidth = width; this.viewportHeight = height; this.visualChanged();
        }
      })
      .onTouch((event: TouchEvent) => this.motionTouch(event))
      .parallelGesture(PanGesture({ fingers: 1,direction: PanDirection.Horizontal,distance: 4 })
        .onActionStart((event: GestureEvent) => this.start(event)).onActionUpdate((event: GestureEvent) => this.drag(event))
        .onActionEnd((event: GestureEvent) => this.end(event)).onActionCancel(() => { if (this.dragging) { this.dragging = false; this.settle(this.window.center); } }))
  }
}
