import { ReaderAsset } from '../image/ReaderAssetCache';
import { CancelScope } from '../model/CancelScope';
import { FilePins } from '../storage/FilePins';
import { viewError } from '../vm/ViewOperation';

@Observed
export class PagerSlot {
  readonly key: string;
  readonly index: number;
  readonly scope: CancelScope = new CancelScope();
  asset: ReaderAsset | undefined = undefined;
  ready: boolean = false;
  paintRevision: number = 0;
  status: string = '正在准备图片…';
  failed: boolean = false;
  ratio: number = 0;
  companion: PagerSlot | undefined = undefined;
  readonly span: number;
  private unpin?: () => void;
  constructor(index: number, key: string, ratio: number = 0, span: number = 1) { this.index = index; this.key = key; this.ratio = ratio; this.span = span; }
  complete(): boolean { return this.ready && !!this.asset && (!this.companion || this.companion.complete()); }
  accept(asset: ReaderAsset): void {
    if (this.scope.cancelled) { return; }
    this.unpin = FilePins.pin(asset.uri.substring(7)); this.asset = asset; this.status = '';
  }
  dispose(): void { this.scope.cancel(); this.ready = false; this.companion?.dispose(); this.unpin?.(); this.unpin = undefined; }
}

// A small stable-identity window. The UI owns decoded maps; this layer owns file pins.
@Observed
export class PagerWindow {
  slots: PagerSlot[] = [];
  center: number = 0;
  total: number = 0;
  span: number = 1;
  onFailure: (index: number, message: string) => void = () => {};
  onChange: (index: number) => void = () => {};
  private serial: number = 0;
  private loader?: (index: number, scope: CancelScope) => Promise<ReaderAsset>;
  reset(index: number, total: number, ratio: number, loader: (index: number, scope: CancelScope) => Promise<ReaderAsset>, span: number = 1): void {
    this.clear(); this.span = span === 2 ? 2 : 1; this.center = this.group(index); this.total = total; this.loader = loader;
    const slot = this.ensure(this.center,index === this.center ? ratio : 0);
    if (slot?.companion && index !== this.center) { slot.companion.ratio = ratio; }
  }
  group(index: number): number { return Math.floor(index / this.span) * this.span; }
  find(index: number): PagerSlot | undefined { return this.slots.find((slot: PagerSlot) => slot.index === index); }
  page(index: number): PagerSlot | undefined { const group = this.find(this.group(index)); return group?.index === index ? group : group?.companion; }
  detachCenter(): PagerSlot | undefined {
    const slot = this.find(this.center);
    if (slot) { this.slots = this.slots.filter((item: PagerSlot) => item !== slot); }
    return slot;
  }
  ensure(index: number, ratio: number = 0): PagerSlot | undefined {
    if (index < 0 || index >= this.total || !this.loader) { return undefined; }
    index = this.group(index);
    const existing = this.find(index); if (existing) { return existing; }
    // Keep the old center during a distant seek, but never build a chapter-sized tree.
    if (this.slots.length >= 3) {
      const removable = this.slots.find((slot: PagerSlot) => slot.index !== this.center && slot.index !== index);
      if (removable) { removable.dispose(); this.slots = this.slots.filter((slot: PagerSlot) => slot !== removable); }
    }
    const slot = new PagerSlot(index, (++this.serial).toString(), ratio,this.span);
    if (this.span === 2 && index + 1 < this.total) { slot.companion = new PagerSlot(index + 1,slot.key + '-pair'); }
    this.slots = this.slots.concat([slot]); this.read(slot); if (slot.companion) { this.read(slot.companion); } return slot;
  }
  private async read(slot: PagerSlot): Promise<void> {
    const loader = this.loader; if (!loader) { return; }
    try { const asset = await loader(slot.index, slot.scope); if (!slot.scope.cancelled) { slot.accept(asset); } }
    catch (error) { if (!slot.scope.cancelled) { slot.failed = true; slot.status = viewError(error as Error); this.onFailure(slot.index,slot.status); } }
    if (!slot.scope.cancelled && this.page(slot.index) === slot) { this.onChange(slot.index); }
  }
  retry(index: number): void {
    const slot = this.find(this.group(index)); const page = this.page(index); if (!slot || !page?.failed) { return; }
    if (page.asset) {
      const ratio = slot.ratio; const companionRatio = slot.companion?.ratio || 0;
      slot.dispose(); this.slots = this.slots.filter((item: PagerSlot) => item !== slot);
      const replacement = this.ensure(slot.index,ratio); if (replacement?.companion) { replacement.companion.ratio = companionRatio; }
    } else { page.failed = false; page.status = '正在准备图片…'; this.onChange(page.index); this.read(page); }
  }
  commit(index: number): boolean {
    const slot = this.find(index); if (!slot?.complete()) { return false; }
    this.center = index;
    const keep = this.slots.filter((item: PagerSlot) => Math.abs(item.index - index) <= this.span);
    this.slots.forEach((item: PagerSlot) => { if (keep.indexOf(item) < 0) { item.dispose(); } });
    this.slots = keep; return true;
  }
  neighbours(): void { this.ensure(this.center + this.span); this.ensure(this.center - this.span); }
  clear(): void { this.slots.forEach((slot: PagerSlot) => slot.dispose()); this.slots = []; this.loader = undefined; }
}
