import { ReaderVM } from '../vm/ReaderVM';
import { PagerSlot } from '../reader/PagerWindow';
import { ReaderAsset } from '../image/ReaderAssetCache';
import { ReadingCanvas } from './ReadingCanvas';
import { readerBackground } from '../model/ReaderDisplay';
import { spreadMargin, SPREAD_GUTTER } from '../reader/PageTurnGeometry';

@Component
struct SpreadPage {
  @ObjectLink vm: ReaderVM;
  slot: PagerSlot = new PagerSlot(-1, 'unbound');
  @Prop side: number = 0;
  @Prop paired: boolean = true;
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
  onRetry: (index: number) => void = () => {};
  onViewportSettled: (index: number) => void = () => {};
  aboutToAppear(): void { this.refresh(); }
  private refresh(): void { this.displayAsset = this.slot.asset; this.displayStatus = this.slot.status; this.displayFailed = this.slot.failed; }
  build() {
    Stack() {
      if (this.displayAsset) {
        ReadingCanvas({ asset: this.displayAsset,traceKey: this.vm.tracePage(this.slot.index,'visible').operationId,ratio: this.slot.ratio,zoom: this.selected ? this.zoom : 1,
          backdrop: this.vm.background,scaleMode: this.vm.scale,tapZones: this.vm.tapZones,invertTap: this.vm.invertTap,
          imageAlign: this.paired ? this.side === 0 ? 'end' : 'start' : 'center',
          edgeInset: this.paired ? spreadMargin(this.viewportWidth) : 0,
          tapOffset: this.paired ? this.side * 0.5 : 0,tapScale: this.paired ? 0.5 : 1,
          externalPaging: true,interactive: this.selected && !this.moving,
          onReady: (ready: boolean) => this.onReady(this.slot.index,ready),onFailure: (message: string) => this.onFailure(this.slot.index,message),
          onInteraction: () => { if (this.selected && !this.moving) { this.vm.focusSpread(this.slot.index,this.slot.ratio); } },
          onPosition: (ratio: number) => { if (this.selected && !this.moving) { this.slot.ratio = ratio; if (this.vm.index === this.slot.index) { this.vm.scroll(ratio); } } },
          onEnd: () => { if (this.selected && !this.moving && this.slot.index + 1 === this.vm.total) { this.vm.reachedEnd(true); } },
          onZoom: this.onZoom,onTapTurn: this.onTurn,onMenu: this.onMenu,onViewportSettled: () => this.onViewportSettled(this.slot.index) })
      } else {
        Column({ space: 12 }) {
          Text('图像 ' + (this.slot.index + 1).toString()).fontColor('#FFFFFF').fontSize(16)
          Text(this.displayStatus).fontSize(13).fontColor('#CBD8D4')
          if (this.displayFailed) { Button('重试图像').onClick(() => this.onRetry(this.slot.index)) }
          else { LoadingProgress().width(28).height(28) }
          if (this.selected) { Button('阅读菜单').onClick(this.onMenu) }
        }.padding(16)
      }
    }.width('100%').height('100%').backgroundColor(readerBackground(this.vm.background))
  }
}

@Component
export struct SpreadViewer {
  @ObjectLink vm: ReaderVM;
  slot: PagerSlot = new PagerSlot(-1, 'unbound');
  @Prop selected: boolean = false;
  @Prop moving: boolean = false;
  @Prop zoom: number = 1;
  @Prop viewportWidth: number = 1;
  @Prop loadRevision: number = 0;
  onReady: (index: number, ready: boolean) => void = () => {};
  onFailure: (index: number, message: string) => void = () => {};
  onZoom: (zoom: number) => void = () => {};
  onTurn: (direction: number) => void = () => {};
  onMenu: () => void = () => {};
  onRetry: (index: number) => void = () => {};
  onViewportSettled: (index: number) => void = () => {};
  @Builder
  private page(slot: PagerSlot, side: number) {
    SpreadPage({ vm: this.vm,slot: slot,side: side,paired: true,selected: this.selected,moving: this.moving,zoom: this.zoom,viewportWidth: this.viewportWidth,loadRevision: this.loadRevision,
      onReady: this.onReady,onFailure: this.onFailure,onZoom: this.onZoom,onTurn: this.onTurn,onMenu: this.onMenu,onRetry: this.onRetry,onViewportSettled: this.onViewportSettled })
      .layoutWeight(1)
  }
  build() {
    Row({ space: SPREAD_GUTTER }) {
      if (this.vm.direction === 'rtl') {
        if (this.slot.companion) { this.page(this.slot.companion,0) }
        else { Blank().layoutWeight(1) }
        this.page(this.slot,1)
      } else {
        this.page(this.slot,0)
        if (this.slot.companion) { this.page(this.slot.companion,1) }
        else { Blank().layoutWeight(1) }
      }
    }.width('100%').height('100%')
      .backgroundColor(readerBackground(this.vm.background))
  }
}
