import { ReaderAsset } from '../image/ReaderAssetCache';
import { ReadingCanvas } from './ReadingCanvas';
import { FilePins } from '../storage/FilePins';

class CanvasLayer {
  readonly asset: ReaderAsset;
  readonly ratio: number;
  readonly release: () => void;
  constructor(asset: ReaderAsset, ratio: number) { this.asset = asset; this.ratio = ratio; this.release = FilePins.pin(asset.uri.substring(7)); }
}

// Legacy vertical/spread modes retain the old surface until the new viewport is rendered.
@Component
export struct RetainedCanvas {
  @Prop @Watch('changed') asset: ReaderAsset;
  @Prop zoom: number = 1;
  @Prop ratio: number = 0;
  @Prop backdrop: string = 'dark';
  @Prop scaleMode: string = 'auto';
  @Prop vertical: boolean = false;
  @Prop turnDirection: number = 1;
  @Prop tapZones: string = 'sides';
  @Prop invertTap: boolean = false;
  tapOffset: number = 0;
  tapScale: number = 1;
  controller: Scroller = new Scroller();
  onPosition: (ratio: number) => void = () => {};
  onZoom: (zoom: number) => void = () => {};
  onTurn: (direction: number) => void = () => {};
  onMenu: () => void = () => {};
  onEnd: () => void = () => {};
  onTapTurn: (direction: number) => void = () => {};
  onInteraction: () => void = () => {};
  @State private layers: CanvasLayer[] = [];
  @State private shown: string = '';
  @State private failure: string = '';
  @State private transitionProgress: number = 0;
  @State private animating: boolean = false;
  @State private canvasWidth: number = 1;
  @State private canvasHeight: number = 1;
  private transitionGeneration: number = 0;
  private visible: boolean = false;
  aboutToAppear(): void { this.visible = true; this.changed(); }
  aboutToDisappear(): void { this.visible = false; this.transitionGeneration++; this.layers.forEach((layer: CanvasLayer) => layer.release()); this.layers = []; }
  private changed(): void {
    if (!this.visible) { return; }
    if (this.asset.uri === this.shown) {
      this.layers.forEach((layer: CanvasLayer) => { if (layer.asset.uri !== this.shown) { layer.release(); } });
      this.layers = this.layers.filter((layer: CanvasLayer) => layer.asset.uri === this.shown); this.failure = ''; return;
    }
    if (this.layers.some((layer: CanvasLayer) => layer.asset.uri === this.asset.uri)) { return; }
    this.transitionGeneration++; this.animating = false; this.transitionProgress = 0;
    this.failure = '';
    const keep = this.layers.filter((layer: CanvasLayer) => layer.asset.uri === this.shown);
    this.layers.forEach((layer: CanvasLayer) => { if (keep.indexOf(layer) < 0) { layer.release(); } });
    this.layers = keep.concat([new CanvasLayer(this.asset,this.ratio)]);
    if (!this.shown) { this.shown = this.asset.uri; }
  }
  private ready(uri: string, ready: boolean): void {
    if (!ready || !this.visible || uri !== this.asset.uri) { return; }
    if (this.shown === uri) { return; }
    if (this.animating) { return; }
    const generation = ++this.transitionGeneration; this.animating = true;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseInOut, onFinish: () => {
      if (!this.visible || generation !== this.transitionGeneration || uri !== this.asset.uri) { return; }
      this.getUIContext().animateTo({ duration: 0 }, () => {
        this.shown = uri; this.transitionProgress = 0; this.animating = false;
        this.layers.forEach((layer: CanvasLayer) => { if (layer.asset.uri !== uri) { layer.release(); } });
        this.layers = this.layers.filter((layer: CanvasLayer) => layer.asset.uri === uri);
      });
    } }, () => { this.transitionProgress = 1; });
  }
  private displacement(uri: string): number {
    if (this.layers.length < 2) { return 0; }
    return (uri === this.shown ? -this.transitionProgress : 1 - this.transitionProgress) * this.turnDirection;
  }
  build() {
    Stack() {
      ForEach(this.layers,(layer: CanvasLayer) => {
        ReadingCanvas({ asset: layer.asset,ratio: layer.ratio,zoom: this.zoom,backdrop: this.backdrop,scaleMode: this.scaleMode,
          vertical: this.vertical,tapZones: this.tapZones,invertTap: this.invertTap,tapOffset: this.tapOffset,tapScale: this.tapScale,
          interactive: !this.animating && layer.asset.uri === this.shown && this.shown === this.asset.uri,
          onReady: (ready: boolean) => this.ready(layer.asset.uri,ready),
          onFailure: (message: string) => { if (layer.asset.uri === this.asset.uri) { this.failure = message; } },onZoom: this.onZoom,onTurn: this.onTurn,onMenu: this.onMenu,
          onPosition: (ratio: number) => { if (this.shown === layer.asset.uri && this.shown === this.asset.uri) { this.onPosition(ratio); } },
          onEnd: () => { if (this.shown === layer.asset.uri && this.shown === this.asset.uri) { this.onEnd(); } },
          onTapTurn: this.onTapTurn,onInteraction: this.onInteraction })
          .opacity(layer.asset.uri === this.shown || this.animating ? 1 : 0)
          .translate({ x: this.vertical ? 0 : this.displacement(layer.asset.uri) * this.canvasWidth, y: this.vertical ? this.displacement(layer.asset.uri) * this.canvasHeight : 0 })
          .hitTestBehavior(layer.asset.uri === this.shown ? HitTestMode.Default : HitTestMode.None)
      },(layer: CanvasLayer) => layer.asset.uri)
      if (this.shown !== this.asset.uri && this.failure) {
        Column({ space: 8 }) {
          Text(this.failure).fontSize(13).fontColor('#FFFFFF')
          if (this.failure) { Button('重试目标页').onClick(() => {
            this.layers.filter((layer: CanvasLayer) => layer.asset.uri !== this.shown).forEach((layer: CanvasLayer) => layer.release());
            this.layers = this.layers.filter((layer: CanvasLayer) => layer.asset.uri === this.shown); this.changed();
          }) }
        }.padding(12).backgroundColor('#D02B3430')
      }
    }.width('100%').height('100%').clip(true)
      .onAreaChange((_old: Area,area: Area) => { this.canvasWidth = Math.max(1,Number(area.width)); this.canvasHeight = Math.max(1,Number(area.height)); })
  }
}
