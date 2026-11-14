import { TileWarmCache } from '../image/TileWarmCache';
import { image } from '@kit.ImageKit';
import { CancelScope } from '../model/CancelScope';
import { ReaderAsset } from '../image/ReaderAssetCache';
import { DecodedTile, TileDecoder } from '../image/TileDecoder';
import { viewError } from '../vm/ViewOperation';
import { FilePins } from '../storage/FilePins';
import { ReaderLifecycle } from '../reader/ReaderLifecycle';
import { FrameCallback } from '@kit.ArkUI';
import { ReaderTrace } from '../diagnostic/ReaderTrace';
import { ReaderTraceContext } from '../model/RequestTypes';

class TilePresented extends FrameCallback {
  private readonly complete: () => void;
  constructor(complete: () => void) { super(); this.complete = complete; }
  onIdle(_timeLeftInNano: number): void { this.complete(); }
}

@Component
export struct ImageTile {
  @Prop asset: ReaderAsset;
  @Prop index: number = 0;
  @Prop quality: number = 1;
  @Prop traceKey: string = '';
  onDecoded: () => void = () => {};
  onReady: (ready: boolean) => void = () => {};
  onFailure: (message: string) => void = () => {};
  @State private pixel: image.PixelMap | undefined = undefined;
  @State private status: string = '正在解码…';
  @State private failed: boolean = false;
  private lease?: DecodedTile;
  private leaseWidth: number = 0;
  private cancel?: CancelScope;
  private generation: number = 0;
  private visible: boolean = false;
  private targetWidth: number = 0;
  private unpin?: () => void;
  private lifecycle?: () => void;
  private retired: DecodedTile[] = [];
  private reportedGeneration: number = -1;
  private loadStarted: number = 0;
  private traceForTile(): ReaderTraceContext | undefined {
    const base = ReaderTrace.resolve(this.traceKey);
    return ReaderTrace.withPart(base,this.index + 1) || base;
  }
  aboutToAppear(): void {
    this.lifecycle = ReaderLifecycle.subscribe((foreground: boolean) => this.applyReaderVisibility(foreground));
    this.applyReaderVisibility(ReaderLifecycle.isForeground);
  }
  aboutToDisappear(): void { this.lifecycle?.(); this.lifecycle = undefined; this.applyReaderVisibility(false); }
  private applyReaderVisibility(visible: boolean): void {
    if (visible === this.visible) { return; } this.visible = visible;
    if (visible) { this.unpin = FilePins.pin(this.asset.uri.substring(7)); this.load(); }
    else { this.generation++; this.cancel?.cancel(); this.clear(); this.unpin?.(); this.unpin = undefined; }
  }
  private clear(): void { this.onReady(false); this.pixel = undefined; const lease = this.lease; this.lease = undefined; this.leaseWidth = 0; if (lease) { lease.release().catch(() => {}); } this.releaseRetired(); }
  private releaseRetired(leases?: DecodedTile[]): void {
    const retired = leases || this.retired;
    this.retired = this.retired.filter((lease: DecodedTile) => retired.indexOf(lease) < 0);
    retired.forEach((lease: DecodedTile) => lease.release().catch(() => {}));
  }
  private presented(): void {
    const generation = this.generation;
    if (!this.visible || !this.pixel || generation === this.reportedGeneration) { return; }
    this.reportedGeneration = generation;
    const retired = this.retired.slice();
    this.getUIContext().postFrameCallback(new TilePresented(() => {
      // A newer decode invalidates readiness, but must not cancel older retirement.
      this.releaseRetired(retired);
      if (!this.visible || generation !== this.generation) { return; }
      ReaderTrace.record(this.traceForTile(),'tile-presented',Date.now() - this.loadStarted,'ready','',this.index + 1);
      this.onReady(true);
    }));
  }
  private async load(): Promise<void> {
    if (this.targetWidth <= 0) { return; }
    const width = Math.max(1,Math.min(this.asset.width,2048,Math.round(this.targetWidth * this.quality))); this.loadStarted = Date.now();
    const generation = ++this.generation; if (this.cancel) { this.cancel.cancel(); }
    this.failed = false; this.status = '正在解码…';
    if (this.lease && this.leaseWidth === width) { this.status = ''; this.presented(); return; }
    const cancel = new CancelScope(); this.cancel = cancel;
    try {
      const lease = await TileWarmCache.acquire(this.asset, this.index, width,
        { callId: 'tile-' + generation.toString(), deadlineMs: Date.now() + 30000, cancel: cancel, ruleRevision: 1,
          trace: this.traceForTile() });
      if (!this.visible || generation !== this.generation || cancel.cancelled) { await lease.release(); return; }
      const old = this.lease; this.lease = lease; this.leaseWidth = width; this.pixel = lease.map;
      if (old) { this.retired.push(old); }
      this.status = ''; this.onDecoded();
      TileWarmCache.warm(this.asset, this.index + 1, width, cancel,ReaderTrace.resolve(this.traceKey));
    } catch (error) { if (this.visible && generation === this.generation && !cancel.cancelled) { this.failed = true; this.status = viewError(error as Error); if (!this.pixel) { this.onFailure(this.status); } } }
  }
  build() {
    Stack() {
      if (this.pixel) { Image(this.pixel).width('100%').height('100%').objectFit(ImageFit.Fill)
        .onComplete((event) => { if (event?.loadingStatus === 1) { this.presented(); } }) }
      else {
        Column({ space: 10 }) {
          Text(this.status).fontSize(13)
          if (this.failed) { Button('重试分块').fontSize(12).onClick(() => this.load()) }
          else { LoadingProgress().width(24).height(24) }
        }.padding(12)
      }
    }
    .width('100%').aspectRatio(this.asset.width / Math.min(TileDecoder.BLOCK_HEIGHT, this.asset.height - this.index * TileDecoder.BLOCK_HEIGHT))
    .onAreaChange((_old: Area, area: Area) => {
      const width = Math.round(this.getUIContext().vp2px(Number(area.width)));
      if (width > 0 && Math.abs(width - this.targetWidth) > 32) { this.targetWidth = width; if (this.visible) { this.load(); } }
    })
  }
}
