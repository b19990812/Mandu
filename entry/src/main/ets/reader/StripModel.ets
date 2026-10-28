import { ReaderAsset } from '../image/ReaderAssetCache';
import { TileDecoder } from '../image/TileDecoder';
import { ListDataSource } from '../ui/ListDataSource';

export interface StripItem { page: number; tile: number; width: number; height: number; generation: number; }
export class StripModel {
  readonly data: ListDataSource<StripItem> = new ListDataSource();
  private readonly sizes: Map<number, number[]> = new Map();
  private readonly epochs: Map<number,number> = new Map();
  private total: number = 0;
  reset(total: number): void { this.total = total; this.sizes.clear(); this.epochs.clear(); this.rebuild(); }
  invalidate(page: number): void { this.epochs.set(page,(this.epochs.get(page) || 0) + 1); this.rebuild(); }
  matches(index: number, asset: ReaderAsset): boolean { const size = this.sizes.get(index); return size !== undefined && size[0] === asset.width && size[1] === asset.height; }
  remember(index: number, asset: ReaderAsset): boolean {
    const size = this.sizes.get(index); if (size && size[0] === asset.width && size[1] === asset.height) { return false; }
    this.sizes.set(index, [asset.width, asset.height]); this.rebuild(); return true;
  }
  private rebuild(): void {
    const items: StripItem[] = [];
    for (let page = 0; page < this.total; page++) {
      const size = this.sizes.get(page);
      const generation = this.epochs.get(page) || 0;
      if (!size) { items.push({ page: page, tile: -1, width: 1, height: 1,generation: generation }); }
      else { for (let tile = 0; tile < Math.ceil(size[1] / TileDecoder.BLOCK_HEIGHT); tile++) { items.push({ page: page, tile: tile, width: size[0], height: size[1],generation: generation }); } }
    }
    this.data.replace(items);
  }
  position(page: number, ratio: number): number {
    const size = this.sizes.get(page); const tile = size ? Math.min(Math.ceil(size[1] / TileDecoder.BLOCK_HEIGHT) - 1,Math.floor(ratio * size[1] / TileDecoder.BLOCK_HEIGHT)) : -1;
    for (let index = 0; index < this.data.totalCount(); index++) {
      const item = this.data.getData(index); if (item.page === page && (item.tile >= tile || item.tile === -1)) { return index; }
    }
    return 0;
  }
}
