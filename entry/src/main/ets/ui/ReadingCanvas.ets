import { TileWarmCache } from '../image/TileWarmCache';
import { ReaderAsset } from '../image/ReaderAssetCache';
import { TileDecoder } from '../image/TileDecoder';
import { ImageTile } from './ImageTile';
import { ListDataSource } from './ListDataSource';
import { readerBackground, tapAction } from '../model/ReaderDisplay';
import { ReaderTrace } from '../diagnostic/ReaderTrace';
import { ReaderTraceContext } from '../model/RequestTypes';

@Component
export struct ReadingCanvas {
  @Prop @Watch('assetChanged') asset: ReaderAsset;
  @Prop traceKey: string = '';
  @Prop @Watch('zoomChanged') zoom: number = 1;
  @Prop ratio: number = 0;
  @Prop backdrop: string = 'dark';
  @Prop @Watch('displayChanged') scaleMode: string = 'auto';
  @Prop vertical: boolean = false;
  @Prop externalPaging: boolean = false;
  @Prop interactive: boolean = true;
  @Prop imageAlign: string = 'center';
  @Prop @Watch('displayChanged') edgeInset: number = 0;
  onReady: (ready: boolean) => void = () => {};
  onFailure: (message: string) => void = () => {};
  @Prop tapZones: string = 'sides';
  @Prop invertTap: boolean = false;
  onPosition: (ratio: number) => void = () => {};
  onZoom: (zoom: number) => void = () => {};
  onTurn: (direction: number) => void = () => {};
  onMenu: () => void = () => {};
  onEnd: () => void = () => {};
  onTapTurn: (direction: number) => void = () => {};
  onInteraction: () => void = () => {};
  onViewportSettled: () => void = () => {};
  tapOffset: number = 0;
  tapScale: number = 1;
  private readonly data: ListDataSource<number> = new ListDataSource();
  controller: Scroller = new Scroller();
  private horizontal: Scroller = new Scroller();
  @State private canvasWidth: number = 320;
  @State private canvasHeight: number = 400;
  @State private imageWidth: number = 320;
  @State private topSpace: number = 0;
  @State private preview: number = 1;
  private currentRatio: number = 0;
  private generation: number = 0;
  private restoring: boolean = true;
  private visible: boolean = false;
  private pinchStart: number = 1;
  private gestureZoom: number = 1;
  private tapX: number = 0;
  private tapY: number = 0;
  private tapStart: number = 0;
  private tapMoved: boolean = false;
  private tapAtTop: boolean = false;
  private tapAtBottom: boolean = false;
  private multiTouch: boolean = false;
  private lastTap: number = 0;
  private menuTimer: number = -1;
  private loadedUri: string = '';
  private rendered: Set<number> = new Set();
  private viewportReady: boolean = false;
  private lastTileDecoded: boolean = false;
  private assetStarted: number = 0;
  aboutToAppear(): void { this.visible = true; this.assetChanged(); }
  aboutToDisappear(): void { this.visible = false; this.onReady(false); this.generation++; if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); } }
  private baseWidth(): number {
    const available = Math.max(1,this.canvasWidth - this.edgeInset);
    if (this.scaleMode === 'width') { return available; }
    if (this.scaleMode === 'height') { return this.canvasHeight * this.asset.width / this.asset.height; }
    return this.asset.height / this.asset.width > 3 ? available : Math.min(available,this.canvasHeight * this.asset.width / this.asset.height);
  }
  private displayChanged(): void { this.configureWarm(); this.layoutAt(this.currentRatio,0); }
  private configureWarm(): void { TileWarmCache.configure(this.getUIContext().vp2px(this.canvasWidth),this.getUIContext().vp2px(this.canvasHeight),this.scaleMode); }
  private assetChanged(): void {
    if (this.loadedUri === this.asset.uri) { return; }
    this.loadedUri = this.asset.uri; this.assetStarted = Date.now(); this.rendered.clear(); this.viewportReady = false; this.onReady(false);
    this.lastTileDecoded = false;
    const count = Math.ceil(this.asset.height / TileDecoder.BLOCK_HEIGHT); const items: number[] = [];
    for (let index = 0; index < count; index++) { items.push(index); } this.data.replace(items);
    this.currentRatio = this.ratio; this.layoutAt(this.currentRatio,0);
  }
  private zoomChanged(): void {
    const oldHeight = this.imageWidth * this.asset.height / this.asset.width;
    const oldX = this.horizontal.currentOffset().xOffset;
    const width = this.baseWidth() * this.zoom; const newHeight = width * this.asset.height / this.asset.width;
    const ratio = Math.max(0,this.currentRatio + this.canvasHeight / (2 * Math.max(oldHeight,1)) - this.canvasHeight / (2 * Math.max(newHeight,1)));
    const x = this.imageWidth > this.canvasWidth ? (oldX + this.canvasWidth / 2) * width / this.imageWidth - this.canvasWidth / 2 : (width - this.canvasWidth) / 2;
    this.layoutAt(ratio,Math.max(0,x));
  }
  private layoutAt(ratio: number,x: number): void {
    if (this.viewportReady) { this.viewportReady = false; this.onReady(false); }
    this.restoring = true; const generation = ++this.generation; const uri = this.asset.uri;
    this.imageWidth = Math.max(1,this.baseWidth() * Math.max(1,Math.min(4,this.zoom)));
    const height = this.imageWidth * this.asset.height / this.asset.width; this.topSpace = Math.max(0,(this.canvasHeight - height) / 2);
    const target = Math.max(0,Math.min(ratio,Math.max(0,1 - this.canvasHeight / height))); this.currentRatio = target;
    setTimeout(() => {
      if (!this.visible || this.asset.uri !== uri || generation !== this.generation) { return; }
      const y = target * this.asset.height; const index = Math.min(this.data.totalCount() - 1,Math.floor(y / TileDecoder.BLOCK_HEIGHT));
      this.controller.scrollToIndex(Math.max(0,index),false,ScrollAlign.START); this.horizontal.scrollTo({ xOffset: x,yOffset: 0 });
      setTimeout(() => {
        if (!this.visible || this.asset.uri !== uri || generation !== this.generation) { return; }
        this.controller.scrollBy(0,(y - index * TileDecoder.BLOCK_HEIGHT) * this.imageWidth / this.asset.width);
        this.restoring = false; this.reportReady(); this.onPosition(this.currentRatio); this.reportEnd();
      },20);
    },0);
  }
  private tileReady(index: number, ready: boolean): void {
    if (ready) { this.rendered.add(index); } else { this.rendered.delete(index); }
    this.reportReady();
  }
  private reportReady(): void {
    if (!this.visible || this.restoring) { return; }
    const scale = this.imageWidth / this.asset.width;
    const top = Math.max(0, this.controller.currentOffset().yOffset - this.topSpace) / scale;
    const bottom = Math.min(this.asset.height, top + this.canvasHeight / scale);
    const first = Math.max(0, Math.floor(top / TileDecoder.BLOCK_HEIGHT));
    const last = Math.min(this.data.totalCount() - 1, Math.ceil(bottom / TileDecoder.BLOCK_HEIGHT) - 1);
    let ready = last >= first;
    for (let index = first; index <= last; index++) { if (!this.rendered.has(index)) { ready = false; } }
    if (ready !== this.viewportReady) {
      this.viewportReady = ready;
      if (ready) {
        const trace = this.traceContext();
        ReaderTrace.record(trace,'viewport-ready',Date.now() - (trace?.startedAt || this.assetStarted),'ready','visible',this.rendered.size);
      }
      this.onReady(ready);
    }
  }
  private traceContext(): ReaderTraceContext | undefined { return ReaderTrace.resolve(this.traceKey); }
  private setZoom(value: number): void { this.preview = 1; this.onZoom(Math.max(1,Math.min(4,value))); }
  private reportEnd(): void {
    const height = this.imageWidth * this.asset.height / this.asset.width;
    if (this.visible && !this.restoring && this.lastTileDecoded && this.zoom <= 1 && this.controller.currentOffset().yOffset + this.canvasHeight >= height + this.topSpace * 2 - 2) { this.onEnd(); }
  }
  private tap(event: TouchEvent): void {
    if (!this.interactive) { return; }
    if (event.touches.length > 1) { this.multiTouch = true; this.tapMoved = true; this.lastTap = 0; if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); this.menuTimer = -1; } return; }
    const touch = event.touches[0] || event.changedTouches[0]; if (!touch) { return; }
    if (event.type === TouchType.Down) { this.multiTouch = false; this.tapX = touch.screenX; this.tapY = touch.screenY; this.tapStart = Date.now(); this.tapMoved = false; this.onInteraction(); const y = this.controller.currentOffset().yOffset; this.tapAtTop = y <= 2; this.tapAtBottom = y + this.canvasHeight >= this.imageWidth * this.asset.height / this.asset.width + this.topSpace * 2 - 2; }
    if (Math.abs(touch.screenX - this.tapX) + Math.abs(touch.screenY - this.tapY) > 12 ||
      this.externalPaging && Math.abs(touch.screenX - this.tapX) > 4) { this.tapMoved = true; }
    if (event.type === TouchType.Cancel) { this.tapMoved = true; this.multiTouch = true; }
    if (this.tapMoved) { this.lastTap = 0; if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); this.menuTimer = -1; } }
    if (this.multiTouch) { return; }
    if (event.type === TouchType.Up && this.zoom <= 1 && this.tapMoved) {
      if (!this.externalPaging && !this.vertical && Math.abs(touch.screenX - this.tapX) > 80 && Math.abs(touch.screenY - this.tapY) < 40) { this.onTurn(touch.screenX < this.tapX ? 1 : -1); }
      if (this.vertical && Math.abs(touch.screenY - this.tapY) > 80 && Math.abs(touch.screenX - this.tapX) < 40 && (touch.screenY < this.tapY ? this.tapAtBottom : this.tapAtTop)) { this.onTurn(touch.screenY < this.tapY ? 1 : -1); }
    }
    if (event.type === TouchType.Up && !this.tapMoved && Date.now() - this.tapStart < 350) {
      const fraction = this.tapOffset + Math.max(0,Math.min(1,touch.x / this.canvasWidth)) * this.tapScale;
      const action = tapAction(fraction,this.tapZones,this.invertTap);
      // Paging zones are immediate. Only the menu zone waits for a possible zoom double tap.
      if (this.zoom <= 1 && action) {
        if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); this.menuTimer = -1; }
        this.lastTap = 0; this.onTapTurn(action); return;
      }
      if (action) { this.lastTap = 0; this.onMenu(); return; }
      if (Date.now() - this.lastTap < 400) { if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); this.menuTimer = -1; } this.lastTap = 0; this.setZoom(this.zoom > 1 ? 1 : 2); }
      else {
        this.lastTap = Date.now(); this.menuTimer = setTimeout(() => {
          this.menuTimer = -1; if (!this.visible) { return; }
          this.onMenu();
        },400);
      }
    }
  }
  build() {
    Stack() {
      Scroll(this.horizontal) {
        List({ scroller: this.controller }) {
          LazyForEach(this.data,(index: number) => {
            ListItem() {
              Row() { ImageTile({ asset: this.asset,index: index,quality: 1,traceKey: this.traceKey,onFailure: this.onFailure,onReady: (ready: boolean) => this.tileReady(index,ready),onDecoded: () => { if (index + 1 === this.data.totalCount()) { this.lastTileDecoded = true; this.reportEnd(); } } }).width(this.imageWidth) }
                .width(Math.max(this.canvasWidth,this.imageWidth)).justifyContent(this.zoom > 1 || this.imageAlign === 'center' ? FlexAlign.Center : this.imageAlign === 'end' ? FlexAlign.End : FlexAlign.Start)
            }
          },(index: number) => this.asset.uri + ':' + index.toString())
        }.width(Math.max(this.canvasWidth,this.imageWidth)).height(this.canvasHeight).cachedCount(0)
          .contentStartOffset(this.topSpace).contentEndOffset(this.topSpace).edgeEffect(EdgeEffect.None).scrollBar(BarState.Off)
          .onDidScroll(() => {
            if (!this.restoring) {
              const height = this.imageWidth * this.asset.height / this.asset.width;
              this.currentRatio = Math.max(0,Math.min(1,(this.controller.currentOffset().yOffset - this.topSpace) / height)); this.reportReady(); this.onPosition(this.currentRatio); this.reportEnd();
            }
          })
          .onScrollStop(() => { if (this.visible && !this.restoring) { this.onViewportSettled(); } })
      }.width('100%').height('100%').scrollable(this.zoom > 1 ? ScrollDirection.Horizontal : ScrollDirection.None).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
        .scale({ x: this.preview,y: this.preview })
    }.width('100%').height('100%').clip(true).backgroundColor(readerBackground(this.backdrop))
      .onAreaChange((_old: Area,area: Area) => {
        const width = Number(area.width); const height = Number(area.height);
        if (width > 0 && height > 0 && (Math.abs(width - this.canvasWidth) > 1 || Math.abs(height - this.canvasHeight) > 1)) { this.canvasWidth = width; this.canvasHeight = height; this.configureWarm(); this.layoutAt(this.currentRatio,0); }
      })
      .parallelGesture(PinchGesture({ fingers: 2 }).onActionStart(() => { this.pinchStart = this.zoom; this.gestureZoom = this.zoom; })
        .onActionUpdate((event: GestureEvent) => { this.gestureZoom = Math.max(1,Math.min(4,this.pinchStart * event.scale)); this.preview = this.gestureZoom / this.pinchStart; })
        .onActionEnd(() => this.setZoom(this.gestureZoom)).onActionCancel(() => { this.preview = 1; }))
      .onTouch((event: TouchEvent) => this.tap(event))
  }
}
