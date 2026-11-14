import { ReaderVM } from '../vm/ReaderVM';
import { ReaderAsset } from '../image/ReaderAssetCache';
import { CancelScope } from '../model/CancelScope';
import { StripItem } from '../reader/StripModel';
import { ImageTile } from './ImageTile';
import { TileDecoder } from '../image/TileDecoder';
import { FilePins } from '../storage/FilePins';
import { viewError } from '../vm/ViewOperation';
import { ReaderLifecycle } from '../reader/ReaderLifecycle';

@Component
export struct WebtoonTile {
  @ObjectLink vm: ReaderVM;
  @Prop item: StripItem;
  @State private asset: ReaderAsset | undefined = undefined;
  @State private status: string = '正在读取图像…';
  private scope?: CancelScope;
  private unpin?: () => void;
  private active: boolean = false;
  private lifecycle?: () => void;
  aboutToAppear(): void {
    this.lifecycle = ReaderLifecycle.subscribe((foreground: boolean) => this.applyReaderVisibility(foreground));
    this.applyReaderVisibility(ReaderLifecycle.isForeground);
  }
  aboutToDisappear(): void { this.lifecycle?.(); this.lifecycle = undefined; this.applyReaderVisibility(false); }
  private applyReaderVisibility(active: boolean): void {
    if (active === this.active) { return; } this.active = active;
    if (active) { this.load(); }
    else { this.scope?.cancel(); this.asset = undefined; this.unpin?.(); this.unpin = undefined; }
  }
  private async load(): Promise<void> {
    this.scope?.cancel(); const scope = new CancelScope(); this.scope = scope;
    try {
      const asset = await this.vm.stripAsset(this.item.page, scope);
      if (!this.active || scope.cancelled) { return; }
      if (this.unpin) { this.unpin(); } this.unpin = FilePins.pin(asset.uri.substring(7)); this.asset = asset;
      this.vm.stripDimensions(this.item.page, asset);
    } catch (error) { if (this.active && !scope.cancelled) { this.status = viewError(error as Error); } }
  }
  build() {
    if (this.asset && this.item.tile >= 0) {
      ImageTile({ asset: this.asset, index: this.item.tile, quality: 1,traceKey: this.vm.tracePage(this.item.page,'visible').operationId })
    } else {
      Column({ space: 12 }) {
        Text('图像 ' + (this.item.page + 1).toString() + ' · ' + this.status).fontSize(14)
        Button('重试图像').fontSize(13).onClick(() => this.vm.retryStripPage(this.item.page))
      }.width('100%').height(this.item.tile < 0 ? 240 : undefined)
        .aspectRatio(this.item.tile < 0 ? 1 : this.item.width / Math.min(TileDecoder.BLOCK_HEIGHT, this.item.height - this.item.tile * TileDecoder.BLOCK_HEIGHT))
    }
  }
}
