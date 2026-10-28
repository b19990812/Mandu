import { ReaderAsset } from '../image/ReaderAssetCache';
import { TileDecoder } from '../image/TileDecoder';
import { ImageTile } from './ImageTile';
import { ListDataSource } from './ListDataSource';

@Component
export struct ReaderAssetView {
  @Prop @Watch('changed') asset: ReaderAsset;
  @Prop @Watch('changed') quality: number = 1;
  @Prop ratio: number = 0;
  onPosition: (ratio: number) => void = () => {};
  private readonly data: ListDataSource<number> = new ListDataSource();
  controller: Scroller = new Scroller();
  private count: number = 0;
  private restored: boolean = false;
  private targetRatio: number = 0;
  private viewportWidth: number = 0;
  private visible: boolean = false;
  aboutToAppear(): void { this.changed(); }
  aboutToDisappear(): void { this.visible = false; }
  private changed(): void {
    this.visible = true; this.targetRatio = this.ratio; this.restored = false; this.count = Math.ceil(this.asset.height / TileDecoder.BLOCK_HEIGHT);
    const items: number[] = []; for (let i = 0; i < this.count; i++) { items.push(i); } this.data.replace(items);
  }
  build() {
    List({ scroller: this.controller }) {
      LazyForEach(this.data, (index: number) => {
        ListItem() { ImageTile({ asset: this.asset, index: index, quality: this.quality }) }
      }, (index: number) => this.asset.uri + ':' + index.toString() + ':' + this.quality.toString())
    }.width('100%').height('100%').cachedCount(0)
      .onAreaChange((_old: Area, area: Area) => {
        this.viewportWidth = Number(area.width);
        if (!this.restored && this.count > 0) {
          const uri = this.asset.uri; const top = this.targetRatio * this.asset.height; const index = Math.min(this.count - 1, Math.floor(top / TileDecoder.BLOCK_HEIGHT));
          setTimeout(() => {
            if (!this.visible || this.asset.uri !== uri) { return; }
            this.restored = true; this.controller.scrollToIndex(index, false, ScrollAlign.START);
            setTimeout(() => { if (this.visible && this.asset.uri === uri) { this.controller.scrollBy(0, (top - index * TileDecoder.BLOCK_HEIGHT) * this.viewportWidth / this.asset.width); } }, 0);
          }, 0);
        }
      })
      .onDidScroll(() => {
        const height = this.viewportWidth * this.asset.height / this.asset.width;
        if (this.restored && height > 0) { this.onPosition(Math.max(0, Math.min(1, this.controller.currentOffset().yOffset / height))); }
      })
  }
}
