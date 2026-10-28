import { image } from '@kit.ImageKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { checkCall } from '../source/SourceHttp';
import { ReaderAsset } from './ReaderAssetCache';

export class DecodedTile {
  readonly map: image.PixelMap;
  readonly bytes: number;
  private released: boolean = false;
  private speculative: boolean;
  constructor(map: image.PixelMap, bytes: number, speculative: boolean = false) { this.map = map; this.bytes = bytes; this.speculative = speculative; }
  promote(): boolean {
    if (this.released) { return false; }
    if (!this.speculative) { return true; }
    if (!TileDecoder.promoteBytes(this.bytes)) { return false; }
    this.speculative = false; return true;
  }
  async release(): Promise<void> {
    if (this.released) { return; } this.released = true;
    try { await this.map.release(); } finally { TileDecoder.releaseBytes(this.bytes,this.speculative); }
  }
}

// One codec queue, independent display/preload pools, exact RGBA accounting for live maps.
// This budget does not by itself prove absence of hidden codec allocations; G3 measures those.
export class TileDecoder {
  static readonly BLOCK_HEIGHT: number = 1024;
  static readonly DISPLAY_LIMIT: number = 134217728;
  static readonly PRELOAD_LIMIT: number = 16777216;
  private static tail: Promise<void> = Promise.resolve();
  private static displayUsed: number = 0;
  private static preloadUsed: number = 0;
  private static peak: number = 0;
  static releaseBytes(bytes: number, speculative: boolean = false): void {
    if (speculative) { TileDecoder.preloadUsed = Math.max(0,TileDecoder.preloadUsed - bytes); }
    else { TileDecoder.displayUsed = Math.max(0,TileDecoder.displayUsed - bytes); }
  }
  static promoteBytes(bytes: number): boolean {
    if (TileDecoder.displayUsed + bytes > TileDecoder.DISPLAY_LIMIT) { return false; }
    TileDecoder.displayUsed += bytes; TileDecoder.releaseBytes(bytes,true); return true;
  }
  static displayBytes(): number { return TileDecoder.displayUsed; }
  static preloadBytes(): number { return TileDecoder.preloadUsed; }
  static liveBytes(): number { return TileDecoder.displayUsed + TileDecoder.preloadUsed; }
  static peakBytes(): number { return TileDecoder.peak; }
  async decode(asset: ReaderAsset, tile: number, targetWidth: number, ctx: CallContext, speculative: boolean = false): Promise<DecodedTile> {
    const previous = TileDecoder.tail; let release: () => void = () => {};
    TileDecoder.tail = new Promise<void>((resolve) => { release = resolve; }); await previous;
    try {
      checkCall(ctx);
      if (!asset.uri.startsWith('file:///') || !Number.isSafeInteger(tile) || tile < 0) { throw new AppError(ErrorCode.POLICY_DENIED, '仅解码受控本地图片'); }
      const top = tile * TileDecoder.BLOCK_HEIGHT; const height = Math.min(TileDecoder.BLOCK_HEIGHT, asset.height - top);
      if (height < 1) { throw new AppError(ErrorCode.CONFIG_INVALID, '图像分块位置无效'); }
      const width = Math.max(1, Math.min(asset.width, 2048, Math.round(targetWidth)));
      const outputHeight = Math.max(1, Math.round(height * width / asset.width));
      const reserved = width * outputHeight * 4;
      const limit = speculative ? TileDecoder.PRELOAD_LIMIT : TileDecoder.DISPLAY_LIMIT;
      if ((speculative ? TileDecoder.preloadUsed : TileDecoder.displayUsed) + reserved > limit) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '图像解码预算已满，滚动后重试'); }
      const source = image.createImageSource(asset.uri.substring('file://'.length));
      let map: image.PixelMap | undefined = undefined;
      let sourceClosed = false;
      try {
        map = await source.createPixelMap({ desiredRegion: { x: 0, y: top, size: { width: asset.width, height: height } },
          desiredSize: { width: width, height: outputHeight }, cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888, editable: false });
        checkCall(ctx);
        const info = await map.getImageInfo();
        if (info.size.width !== width || info.size.height !== outputHeight) { throw new AppError(ErrorCode.CORRUPT_FILE, '区域解码尺寸不符合请求'); }
        const bytes = map.getPixelBytesNumber();
        if (bytes > 8388608 || (speculative ? TileDecoder.preloadUsed : TileDecoder.displayUsed) + bytes > limit) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '单块像素超过解码预算'); }
        await source.release(); sourceClosed = true;
        // A cached map can be promoted while the source is closing; recheck its destination pool.
        checkCall(ctx);
        if ((speculative ? TileDecoder.preloadUsed : TileDecoder.displayUsed) + bytes > limit) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '图像解码预算已满，滚动后重试'); }
        if (speculative) { TileDecoder.preloadUsed += bytes; } else { TileDecoder.displayUsed += bytes; }
        TileDecoder.peak = Math.max(TileDecoder.peak,TileDecoder.liveBytes());
        const lease = new DecodedTile(map, bytes, speculative); map = undefined; return lease;
      } finally { if (map) { await map.release(); } if (!sourceClosed) { await source.release(); } }
    } finally { release(); }
  }
}
