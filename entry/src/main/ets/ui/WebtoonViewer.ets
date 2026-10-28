import { TileWarmCache } from '../image/TileWarmCache';
import { ReaderVM } from '../vm/ReaderVM';
import { StripItem } from '../reader/StripModel';
import { TileDecoder } from '../image/TileDecoder';
import { WebtoonTile } from './WebtoonTile';
import { readerBackground, tapAction } from '../model/ReaderDisplay';

@Component
export struct WebtoonViewer {
  @ObjectLink vm: ReaderVM;
  controller: Scroller = new Scroller();
  @Prop @Watch('zoomChanged') zoom: number = 1;
  onZoom: (zoom: number) => void = () => {};
  onMenu: () => void = () => {};
  private horizontal: Scroller = new Scroller();
  @State private canvasWidth: number = 320;
  @State private contentWidth: number = 320;
  @State private canvasHeight: number = 400;
  @State private preview: number = 1;
  private pinchStart: number = 1;
  private gestureZoom: number = 1;
  private tapX: number = 0;
  private tapY: number = 0;
  private tapStart: number = 0;
  private tapMoved: boolean = false;
  private lastTap: number = 0;
  private menuTimer: number = -1;
  private first: number = 0;
  private bottomReached: boolean = false;
  private endArmed: boolean = false;
  private viewportWidth: number = 320;
  private ready: boolean = false;
  private restoring: boolean = false;
  private generation: number = 0;
  private visible: boolean = false;
  @Prop @Watch('restore') revision: number = 0;
  aboutToAppear(): void { this.visible = true; this.ready = false; this.restore(); }
  aboutToDisappear(): void { this.visible = false; this.generation++; if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); } }
  private zoomChanged(): void {
    this.contentWidth = this.canvasWidth * this.zoom; this.viewportWidth = this.contentWidth;
    TileWarmCache.configure(this.getUIContext().vp2px(this.contentWidth),this.getUIContext().vp2px(this.canvasHeight),'width');
    this.restore();
    this.horizontal.scrollTo({ xOffset: Math.max(0,(this.contentWidth - this.canvasWidth) / 2),yOffset: 0 });
  }
  private setZoom(value: number): void { this.preview = 1; this.onZoom(Math.max(1,Math.min(4,value))); }
  private tap(event: TouchEvent): void {
    if (event.touches.length > 1) { this.tapMoved = true; this.lastTap = 0; if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); this.menuTimer = -1; } return; }
    const touch = event.touches[0] || event.changedTouches[0]; if (!touch) { return; }
    if (event.type === TouchType.Down) { this.tapX = touch.screenX; this.tapY = touch.screenY; this.tapStart = Date.now(); this.tapMoved = false; this.endArmed = true; }
    if (Math.abs(touch.screenX - this.tapX) + Math.abs(touch.screenY - this.tapY) > 12 || event.type === TouchType.Cancel) { this.tapMoved = true; }
    if (event.type === TouchType.Up && this.tapMoved && touch.screenY < this.tapY - 24) { this.continueAtEnd(); }
    if (event.type === TouchType.Up && !this.tapMoved && Date.now() - this.tapStart < 350) {
      const action = tapAction(touch.x / this.canvasWidth,this.vm.tapZones,this.vm.invertTap);
      if (this.zoom <= 1 && action) {
        if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); this.menuTimer = -1; }
        this.lastTap = 0; this.endArmed = action > 0; this.controller.scrollBy(0,action * this.canvasHeight * 0.8); this.continueAtEnd(); return;
      }
      if (action) { this.lastTap = 0; this.onMenu(); return; }
      if (Date.now() - this.lastTap < 400) { if (this.menuTimer >= 0) { clearTimeout(this.menuTimer); this.menuTimer = -1; } this.lastTap = 0; this.setZoom(this.zoom > 1 ? 1 : 2); }
      else { this.lastTap = Date.now(); this.menuTimer = setTimeout(() => { this.menuTimer = -1; if (this.visible) { this.onMenu(); } },400); }
    }
  }
  private continueAtEnd(): void {
    if (this.visible && this.ready && !this.restoring && this.bottomReached && this.endArmed && this.zoom <= 1 && !this.vm.chapterChanging && !this.vm.busy) {
      this.endArmed = false; this.vm.continueChapter();
    }
  }
  private restore(): void {
    this.endArmed = false; this.bottomReached = false;
    const page = this.vm.index; const ratio = this.vm.ratio; const revision = this.revision; const generation = ++this.generation; this.restoring = true;
    setTimeout(() => {
      if (!this.visible || generation !== this.generation) { return; }
      const index = this.vm.strip.position(page, ratio); const item = this.vm.strip.data.getData(index);
      this.controller.scrollToIndex(index, false, ScrollAlign.START); this.first = index;
      setTimeout(() => {
        if (!this.visible || generation !== this.generation) { return; }
        if (item && item.tile >= 0) { this.controller.scrollBy(0, Math.max(0, ratio * item.height - item.tile * TileDecoder.BLOCK_HEIGHT) * this.viewportWidth / item.width); }
        this.ready = true; this.restoring = false; this.vm.stripReady(revision);
      }, 30);
    }, 0);
  }
  private savePosition(): void {
    if (!this.ready || this.restoring) { return; }
    const item = this.vm.strip.data.getData(this.first); if (!item) { return; }
    if (item.tile < 0) { return; }
    const rect = this.controller.getItemRect(this.first);
    const top = item.tile * TileDecoder.BLOCK_HEIGHT + Math.max(0, -rect.y) * item.width / this.viewportWidth;
    this.vm.stripPosition(item.page, Math.min(1, top / item.height));
  }
  build() {
    Scroll(this.horizontal) {
    List({ scroller: this.controller }) {
      LazyForEach(this.vm.strip.data, (item: StripItem) => {
        ListItem() { WebtoonTile({ vm: this.vm, item: item }) }.margin({ bottom: this.vm.mode === 'continuous' && item.tile >= 0 && (item.tile + 1) * TileDecoder.BLOCK_HEIGHT >= item.height ? 16 : 0 })
      }, (item: StripItem) => this.vm.readerEpoch.toString() + ':' + item.page.toString() + ':' + item.tile.toString() + ':' + item.generation.toString())
      ListItem() {
        if (!this.vm.nextId) { Text('已到最后一章').fontColor('#CBD8D4').padding(24) }
        else if (!this.vm.autoNext) { Button('进入下一章').onClick(() => this.vm.changeChapter(this.vm.nextId,true)) }
        else { Row().height(1) }
      }
    }.width(this.contentWidth).height(this.canvasHeight).cachedCount(0).edgeEffect(EdgeEffect.None).scrollBar(BarState.Off)
      .onScrollIndex((start: number) => { this.first = start; this.savePosition(); })
      .onReachEnd(() => { this.bottomReached = true; this.continueAtEnd(); })
      .onDidScroll(() => { this.savePosition(); this.bottomReached = this.controller.isAtEnd(); this.continueAtEnd(); })
    }.width('100%').height('100%').scrollable(ScrollDirection.Horizontal).edgeEffect(EdgeEffect.None).scrollBar(BarState.Off)
      .scale({ x: this.preview,y: this.preview }).clip(true).backgroundColor(readerBackground(this.vm.background))
      .onAreaChange((_old: Area,area: Area) => {
        const width = Number(area.width); const height = Number(area.height);
        if (width > 0 && height > 0 && (Math.abs(width - this.canvasWidth) > 1 || Math.abs(height - this.canvasHeight) > 1)) {
          this.canvasWidth = width; this.canvasHeight = height; this.zoomChanged();
        }
      })
      .parallelGesture(PinchGesture({ fingers: 2 }).onActionStart(() => { this.pinchStart = this.zoom; this.gestureZoom = this.zoom; })
        .onActionUpdate((event: GestureEvent) => { this.gestureZoom = Math.max(1,Math.min(4,this.pinchStart * event.scale)); this.preview = this.gestureZoom / this.pinchStart; })
        .onActionEnd(() => this.setZoom(this.gestureZoom)).onActionCancel(() => { this.preview = 1; }))
      .onTouch((event: TouchEvent) => this.tap(event))
  }
}

