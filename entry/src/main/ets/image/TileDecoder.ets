import { image } from '@kit.ImageKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { CancelScope } from '../model/CancelScope';
import { checkCall } from '../source/SourceHttp';
import { ReaderAsset } from './ReaderAssetCache';
import { DecodeDemand, DecodeScheduler } from './DecodeScheduler';
import { ReaderPerf } from '../diagnostic/ReaderPerf';

class TilePixels {
  readonly map: image.PixelMap;
  readonly bytes: number;
  readonly key: string;
  speculative: boolean;
  references: number = 0;
  closed: boolean = false;
  constructor(map: image.PixelMap,bytes: number,speculative: boolean,key: string = '') { this.map = map; this.bytes = bytes; this.speculative = speculative; this.key = key; }
}
export class DecodedTile {
  readonly map: image.PixelMap;
  readonly bytes: number;
  private released: boolean = false;
  private readonly shared: TilePixels;
  constructor(map: image.PixelMap,bytes: number,speculative: boolean = false,shared?: TilePixels) {
    this.shared = shared || new TilePixels(map,bytes,speculative); this.shared.references++;
    this.map = this.shared.map; this.bytes = this.shared.bytes;
  }
  isSpeculative(): boolean { return this.shared.speculative; }
  promote(): boolean {
    if (this.released || this.shared.closed) { return false; }
    if (!this.shared.speculative) { return true; }
    if (!TileDecoder.promoteBytes(this.bytes)) { return false; } this.shared.speculative = false; return true;
  }
  retain(): DecodedTile {
    if (this.released || this.shared.closed) { throw new AppError(ErrorCode.CANCELLED,'像素租约已释放'); }
    return new DecodedTile(this.map,this.bytes,this.shared.speculative,this.shared);
  }
  async release(): Promise<void> {
    if (this.released) { return; } this.released = true; this.shared.references--;
    if (this.shared.references > 0) { return; }
    this.shared.closed = true; TileDecoder.forget(this.shared);
    try { await this.map.release(); } finally { TileDecoder.releaseBytes(this.bytes,this.shared.speculative); }
  }
}
class TileDecodeJob {
  readonly cancel: CancelScope = new CancelScope();
  readonly demand: DecodeDemand;
  consumers: number = 0;
  foregroundConsumers: number = 0;
  result?: DecodedTile;
  retired: boolean = false;
  promise?: Promise<DecodedTile>;
  constructor(uri: string,speculative: boolean) { this.demand = new DecodeDemand(uri,speculative); }
}

// Bounded parallel native decoding, independent sources, shared pixels with per-consumer leases.
export class TileDecoder {
  static readonly BLOCK_HEIGHT: number = 1024;
  static readonly DISPLAY_LIMIT: number = 134217728;
  static readonly PRELOAD_LIMIT: number = 16777216;
  private static displayUsed: number = 0;
  private static preloadUsed: number = 0;
  private static displayReserved: number = 0;
  private static preloadReserved: number = 0;
  private static peak: number = 0;
  private static jobs: Map<string,TileDecodeJob> = new Map();
  private static pixels: Map<string,TilePixels> = new Map();
  static configureConcurrency(limit: number): void { DecodeScheduler.configure(limit); }
  static releaseBytes(bytes: number,speculative: boolean = false): void {
    if (speculative) { TileDecoder.preloadUsed = Math.max(0,TileDecoder.preloadUsed - bytes); }
    else { TileDecoder.displayUsed = Math.max(0,TileDecoder.displayUsed - bytes); }
  }
  static promoteBytes(bytes: number): boolean {
    if (TileDecoder.displayUsed + TileDecoder.displayReserved + bytes > TileDecoder.DISPLAY_LIMIT) { return false; }
    TileDecoder.displayUsed += bytes; TileDecoder.releaseBytes(bytes,true); return true;
  }
  static forget(pixels: TilePixels): void { if (TileDecoder.pixels.get(pixels.key) === pixels) { TileDecoder.pixels.delete(pixels.key); } }
  static displayBytes(): number { return TileDecoder.displayUsed; }
  static preloadBytes(): number { return TileDecoder.preloadUsed; }
  static liveBytes(): number { return TileDecoder.displayUsed + TileDecoder.preloadUsed; }
  static reservedBytes(): number { return TileDecoder.displayReserved + TileDecoder.preloadReserved; }
  static peakBytes(): number { return TileDecoder.peak; }
  private static reserve(bytes: number,speculative: boolean): void {
    const used = speculative ? TileDecoder.preloadUsed + TileDecoder.preloadReserved : TileDecoder.displayUsed + TileDecoder.displayReserved;
    if (used + bytes > (speculative ? TileDecoder.PRELOAD_LIMIT : TileDecoder.DISPLAY_LIMIT)) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'图像解码预算已满，滚动后重试'); }
    if (speculative) { TileDecoder.preloadReserved += bytes; } else { TileDecoder.displayReserved += bytes; }
  }
  private static unreserve(bytes: number,speculative: boolean): void { if (speculative) { TileDecoder.preloadReserved -= bytes; } else { TileDecoder.displayReserved -= bytes; } }
  private static key(asset: ReaderAsset,tile: number,width: number): string { return asset.uri + '|' + asset.width.toString() + 'x' + asset.height.toString() + '|' + asset.bytes.toString() + '|' + tile.toString() + '|' + width.toString(); }
  private static retire(key: string,job: TileDecodeJob): void {
    if (job.consumers) { return; } job.cancel.cancel();
    if (TileDecoder.jobs.get(key) === job) { TileDecoder.jobs.delete(key); }
    if (job.result && !job.retired) { job.retired = true; job.result.release().catch(() => {}); }
  }
  async decode(asset: ReaderAsset,tile: number,targetWidth: number,ctx: CallContext,speculative: boolean = false): Promise<DecodedTile> {
    checkCall(ctx);
    if (!asset.uri.startsWith('file:///') || !Number.isSafeInteger(tile) || tile < 0 || !Number.isFinite(targetWidth)) { throw new AppError(ErrorCode.POLICY_DENIED,'仅解码受控本地图片'); }
    const width = Math.max(1,Math.min(asset.width,2048,Math.round(targetWidth))); const key = TileDecoder.key(asset,tile,width);
    const pixels = TileDecoder.pixels.get(key);
    if (pixels && !pixels.closed) {
      const lease = new DecodedTile(pixels.map,pixels.bytes,pixels.speculative,pixels);
      if (!speculative && !lease.promote()) { await lease.release(); throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'显示像素预算不足'); }
      return lease;
    }
    let job = TileDecoder.jobs.get(key);
    if (!job || job.cancel.cancelled) {
      job = new TileDecodeJob(asset.uri,speculative); TileDecoder.jobs.set(key,job); const current = job;
      const shared: CallContext = { callId: ctx.callId,deadlineMs: Date.now() + 60000,cancel: current.cancel,ruleRevision: ctx.ruleRevision };
      current.promise = this.produce(asset,tile,width,key,shared,current);
      current.promise.then((result: DecodedTile) => { current.result = result; TileDecoder.retire(key,current); },() => { if (TileDecoder.jobs.get(key) === current) { TileDecoder.jobs.delete(key); } });
    }
    return this.consume(key,job,ctx,speculative);
  }
  private consume(key: string,job: TileDecodeJob,ctx: CallContext,speculative: boolean): Promise<DecodedTile> {
    job.consumers++; if (!speculative) { job.foregroundConsumers++; job.demand.background = false; DecodeScheduler.changed(); }
    return new Promise<DecodedTile>((resolve,reject) => {
      let finished = false; let stop: () => void = () => {}; let timer: number = -1;
      const finish = (lease?: DecodedTile,error?: Error): void => {
        if (finished) { return; } finished = true; stop(); if (timer >= 0) { clearTimeout(timer); }
        job.consumers--; if (!speculative) { job.foregroundConsumers--; }
        if (job.consumers > 0) { job.demand.background = job.foregroundConsumers === 0; DecodeScheduler.changed(); }
        TileDecoder.retire(key,job); if (error) { reject(error); } else { resolve(lease!); }
      };
      stop = ctx.cancel.subscribe(() => finish(undefined,new AppError(ErrorCode.CANCELLED,'图像解码已取消') as Error));
      if (!finished) { timer = setTimeout(() => finish(undefined,new AppError(ErrorCode.TIMEOUT,'图像解码已超时') as Error),Math.max(1,ctx.deadlineMs - Date.now())); }
      job.promise!.then((result: DecodedTile) => {
        if (finished) { return; }
        let lease: DecodedTile | undefined;
        try { checkCall(ctx); lease = result.retain(); if (!speculative && !lease.promote()) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'显示像素预算不足'); } finish(lease); }
        catch (error) { lease?.release().catch(() => {}); finish(undefined,error as Error); }
      },(error: Error) => finish(undefined,error));
    });
  }
  private async produce(asset: ReaderAsset,tile: number,width: number,key: string,ctx: CallContext,job: TileDecodeJob): Promise<DecodedTile> {
    const release = await DecodeScheduler.acquire(ctx,job.demand); const decodeAt = ReaderPerf.enabled ? Date.now() : 0;
    // A queued preload joined by the visible page reserves the display pool when it starts.
    const speculative = job.demand.background; let reserved = 0;
    try {
      checkCall(ctx); const top = tile * TileDecoder.BLOCK_HEIGHT; const height = Math.min(TileDecoder.BLOCK_HEIGHT,asset.height - top);
      if (height < 1) { throw new AppError(ErrorCode.CONFIG_INVALID,'图像分块位置无效'); }
      const outputHeight = Math.max(1,Math.round(height * width / asset.width));
      const estimate = Math.ceil(width * 4 / 256) * 256 * outputHeight; TileDecoder.reserve(estimate,speculative); reserved = estimate;
      const source = image.createImageSource(asset.uri.substring('file://'.length)); let sourceClosed = false;
      let map: image.PixelMap | undefined = undefined;
      try {
        map = await source.createPixelMap({ desiredRegion: { x: 0,y: top,size: { width: asset.width,height: height } },
          desiredSize: { width: width,height: outputHeight },cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,desiredPixelFormat: image.PixelMapFormat.RGBA_8888,editable: false });
        checkCall(ctx); const info = await map.getImageInfo(); const bytes = map.getPixelBytesNumber();
        if (info.size.width !== width || info.size.height !== outputHeight) { throw new AppError(ErrorCode.CORRUPT_FILE,'区域解码尺寸不符合请求'); }
        if (bytes < 1 || bytes > 8388608) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'单块像素超过解码预算'); }
        if (bytes > reserved) { TileDecoder.reserve(bytes - reserved,speculative); }
        else { TileDecoder.unreserve(reserved - bytes,speculative); } reserved = bytes;
        await source.release(); sourceClosed = true; checkCall(ctx);
        TileDecoder.unreserve(reserved,speculative); reserved = 0;
        if (speculative) { TileDecoder.preloadUsed += bytes; } else { TileDecoder.displayUsed += bytes; }
        TileDecoder.peak = Math.max(TileDecoder.peak,TileDecoder.liveBytes());
        const owner = new TilePixels(map,bytes,speculative,key); TileDecoder.pixels.set(key,owner);
        const lease = new DecodedTile(map,bytes,speculative,owner); map = undefined; return lease;
      } finally { try { if (map) { await map.release(); } } finally { if (!sourceClosed) { await source.release(); } } }
    } finally { if (reserved) { TileDecoder.unreserve(reserved,speculative); } ReaderPerf.event('decode',Date.now() - decodeAt); release(); }
  }
}
