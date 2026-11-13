import { ReaderAsset } from './ReaderAssetCache';
import { DecodedTile, TileDecoder } from './TileDecoder';
import { CallContext } from '../model/RequestTypes';
import { CancelScope } from '../model/CancelScope';
import { checkCall } from '../source/SourceHttp';
import { FilePins } from '../storage/FilePins';

// Idle maps use only the preload pool; acquire promotes their lease into the display pool.
export class TileWarmCache {
  private static maps: Map<string, DecodedTile> = new Map();
  private static pending: Map<string, Promise<void>> = new Map();
  private static scope: CancelScope = new CancelScope();
  private static bytes: number = 0;
  private static width: number = 1280;
  private static height: number = 1600;
  private static fit: string = 'auto';
  static configure(width: number, height: number, fit: string): void {
    if (width === TileWarmCache.width && height === TileWarmCache.height && fit === TileWarmCache.fit) { return; }
    TileWarmCache.clear(); TileWarmCache.width = width; TileWarmCache.height = height; TileWarmCache.fit = fit;
  }
  private static key(asset: ReaderAsset, tile: number, width: number): string {
    return asset.uri + ':' + asset.width + ':' + asset.height + ':' + tile + ':' + Math.max(1, Math.min(asset.width, 2048, Math.round(width)));
  }
  static async acquire(asset: ReaderAsset, tile: number, width: number, ctx: CallContext): Promise<DecodedTile> {
    const key = TileWarmCache.key(asset, tile, width);
    checkCall(ctx);
    const map = TileWarmCache.maps.get(key);
    if (map) {
      TileWarmCache.maps.delete(key); TileWarmCache.bytes -= map.bytes;
      if (map.promote()) { return map; }
      await map.release();
    }
    return new TileDecoder().decode(asset, tile, width, ctx);
  }
  static async page(asset: ReaderAsset, cancel: CancelScope): Promise<void> {
    const width = TileWarmCache.fit === 'width' || (TileWarmCache.fit === 'auto' && asset.height / asset.width > 3) ? TileWarmCache.width :
      TileWarmCache.fit === 'height' ? TileWarmCache.height * asset.width / asset.height : Math.min(TileWarmCache.width, TileWarmCache.height * asset.width / asset.height);
    for (let tile = 0; tile < Math.min(2, Math.ceil(asset.height / TileDecoder.BLOCK_HEIGHT)); tile++) {
      if (cancel.cancelled) { return; } await TileWarmCache.warm(asset, tile, width, cancel);
    }
  }
  static async warm(asset: ReaderAsset, tile: number, width: number, cancel: CancelScope): Promise<void> {
    const key = TileWarmCache.key(asset, tile, width);
    if (cancel.cancelled || tile * TileDecoder.BLOCK_HEIGHT >= asset.height || TileWarmCache.maps.has(key) || TileWarmCache.pending.has(key) || TileWarmCache.pending.size >= 2) { return; }
    const scope = TileWarmCache.scope;
    const task = TileWarmCache.prepare(key, asset, tile, width, scope, cancel);
    TileWarmCache.pending.set(key, task);
    try { await task; } finally { if (TileWarmCache.pending.get(key) === task) { TileWarmCache.pending.delete(key); } }
  }
  private static async prepare(key: string, asset: ReaderAsset, tile: number, width: number, scope: CancelScope, caller: CancelScope): Promise<void> {
    const cancel = new CancelScope(); const stop = scope.subscribe(() => cancel.cancel()); const stopCaller = caller.subscribe(() => cancel.cancel());
    const unpin = FilePins.pin(asset.uri.substring(7));
    try {
      // Only idle preload leases may be evicted. Display usage never consumes this budget.
      while (TileWarmCache.maps.size > 0 && (TileDecoder.preloadBytes() >= TileDecoder.PRELOAD_LIMIT || TileWarmCache.bytes > 8388608 || TileWarmCache.maps.size >= 6)) {
        let oldest: string = '';
        TileWarmCache.maps.forEach((_map: DecodedTile, entry: string) => { if (!oldest) { oldest = entry; } });
        const map = TileWarmCache.maps.get(oldest)!; TileWarmCache.maps.delete(oldest); TileWarmCache.bytes -= map.bytes; await map.release();
      }
      if (cancel.cancelled || TileDecoder.preloadBytes() >= TileDecoder.PRELOAD_LIMIT) { return; }
      const map = await new TileDecoder().decode(asset, tile, width,
        { callId: 'reader-prerender', deadlineMs: Date.now() + 30000, cancel: cancel, ruleRevision: 0 }, true);
      if (cancel.cancelled || !map.isSpeculative() || TileWarmCache.bytes + map.bytes > TileDecoder.PRELOAD_LIMIT || TileWarmCache.maps.size >= 6) { await map.release(); return; }
      TileWarmCache.maps.set(key, map); TileWarmCache.bytes += map.bytes;
    } catch (_) { /* Best effort; the visible path retains retry and error reporting. */ }
    finally { stop(); stopCaller(); unpin(); }
  }
  private static async evict(): Promise<void> {
    const maps: DecodedTile[] = []; TileWarmCache.maps.forEach((map: DecodedTile) => maps.push(map));
    TileWarmCache.maps.clear(); TileWarmCache.bytes = 0;
    for (const map of maps) { await map.release(); }
  }
  static clear(): void {
    TileWarmCache.scope.cancel(); TileWarmCache.scope = new CancelScope(); TileWarmCache.pending.clear(); TileWarmCache.evict().catch(() => {});
  }
}
