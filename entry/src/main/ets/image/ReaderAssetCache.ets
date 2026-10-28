import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { CancelScope } from '../model/CancelScope';
import { ChapterPageSource, PageRef, SourceRef } from '../model/SourceTypes';
import { Transport } from '../network/Transport';
import { checkCall, requireHttpSuccess } from '../source/SourceHttp';
import { FileStore } from '../storage/FileStore';
import { AssetProvider } from './AssetProvider';
import { BrowserCache } from './BrowserCache';
import { FilePins } from '../storage/FilePins';
import { transferAsset } from './AssetTransfer';

export interface ReaderAsset { uri: string; width: number; height: number; bytes: number; }
interface CacheItem { index: number; key: string; asset: ReaderAsset; release: () => void; }
interface PendingAsset { request: Promise<ReaderAsset>; cancel: CancelScope; consumers: number; complete: boolean; }

// Four session leases over the shared bounded disk cache. No direct Image(remoteURL).
export class ReaderAssetCache implements AssetProvider {
  private readonly files: FileStore;
  private readonly prefix: string = util.generateRandomUUID().replace(/-/g, '');
  private readonly entries: CacheItem[] = [];
  private disposed: boolean = false;
  private readonly transport: Transport;
  private readonly pending: Map<number, PendingAsset> = new Map();
  private readonly maxPixels: number;
  private readonly maxBytes: number;
  private sequence: number = 0;
  private readonly disk: BrowserCache;
  private readonly forced: Set<number> = new Set();
  private readonly revisionKey: string;

  constructor(cacheDir: string, transport: Transport, maxPixels: number = 4194304, maxBytes: number = 2097152,revisionKey: string = '') {
    this.files = new FileStore(cacheDir, 'reader_assets');
    this.disk = new BrowserCache(cacheDir);
    this.transport = transport;
    this.maxPixels = Math.min(134217728, Math.max(1, maxPixels));
    this.maxBytes = Math.min(33554432, Math.max(1, maxBytes));
    this.revisionKey = revisionKey;
  }

  async load(source: ChapterPageSource | undefined, chapter: SourceRef, page: PageRef, ctx: CallContext): Promise<ReaderAsset> {
    checkCall(ctx);
    if (!source) { throw new AppError(ErrorCode.OFFLINE, '当前没有可用在线源'); }
    if (this.disposed) { throw new AppError(ErrorCode.CANCELLED, '阅读会话已关闭'); }
    const cachedIndex = this.entries.findIndex((item: CacheItem) => item.index === page.ordinal);
    if (cachedIndex >= 0 && this.files.exists(this.entries[cachedIndex].key)) {
      const cached = this.entries.splice(cachedIndex, 1)[0];
      this.entries.push(cached);
      return cached.asset;
    }
    let pending = this.pending.get(page.ordinal);
    if (!pending || pending.cancel.cancelled) {
      const scope = new CancelScope();
      const requestContext: CallContext = { callId: ctx.callId + '-shared', deadlineMs: Date.now() + 60000, cancel: scope, ruleRevision: ctx.ruleRevision };
      const request = this.download(source, chapter, page, requestContext);
      const current: PendingAsset = { request: request, cancel: scope, consumers: 0, complete: false };
      this.pending.set(page.ordinal, current); pending = current;
      const finish = (): void => { current.complete = true; if (this.pending.get(page.ordinal) === current) { this.pending.delete(page.ordinal); } };
      request.then(finish, finish);
    }
    return this.consume(pending, ctx);
  }

  private consume(pending: PendingAsset, ctx: CallContext): Promise<ReaderAsset> {
    pending.consumers++;
    return new Promise<ReaderAsset>((resolve, reject) => {
      let settled = false; let unsubscribe: () => void = () => {};
      const finish = (asset: ReaderAsset | undefined, error: Error | undefined): void => {
        if (settled) { return; } settled = true; clearTimeout(timer); unsubscribe(); pending.consumers--;
        if (pending.consumers === 0 && !pending.complete) { pending.cancel.cancel(); }
        if (error) { reject(error); } else { resolve(asset!); }
      };
      const timer = setTimeout(() => finish(undefined, new AppError(ErrorCode.TIMEOUT, '图像读取超时') as Error), Math.max(1, ctx.deadlineMs - Date.now()));
      unsubscribe = ctx.cancel.subscribe(() => finish(undefined, new AppError(ErrorCode.CANCELLED, '图像读取已取消') as Error));
      pending.request.then((asset: ReaderAsset) => {
        try { checkCall(ctx); finish(asset, undefined); } catch (error) { finish(undefined, error as Error); }
      }, (error: Error) => finish(undefined, error));
    });
  }

  private async download(source: ChapterPageSource, chapter: SourceRef, page: PageRef, ctx: CallContext): Promise<ReaderAsset> {
    const key = this.prefix + '_' + page.ordinal.toString() + '_' + (++this.sequence).toString();
    const writing = FilePins.pin(this.files.localPath(key));
    try {
      const identity = await this.disk.identity(source.id, chapter.remoteId, page.pageKey, this.revisionKey || source.version.toString());
      const cached = this.forced.has(page.ordinal) ? undefined : await this.disk.acquire(identity);
      if (cached) {
        try { checkCall(ctx); const asset = cached.asset; this.remember(page.ordinal,asset.uri.substring(asset.uri.lastIndexOf('/') + 1),asset); return asset; }
        finally { cached.release(); }
      }
      checkCall(ctx);
      const verified = await transferAsset(this.files,key,source,chapter,page,this.transport,ctx,this.maxBytes);
      const bytes = verified.bytes;
      checkCall(ctx);
      if (this.disposed) { throw new AppError(ErrorCode.CANCELLED, '阅读会话已关闭'); }
      const decoder = image.createImageSource(this.files.localPath(key));
      let width = 0;
      let height = 0;
      try {
        const info = await decoder.getImageInfo();
        if (['image/png', 'image/jpeg', 'image/jpg', 'image/webp'].indexOf(info.mimeType) < 0) { throw new AppError(ErrorCode.UNSUPPORTED, '当前仅支持JPEG、PNG和WebP静态图'); }
        width = info.size.width; height = info.size.height;
      } catch (error) { if (error instanceof AppError) { throw error; } throw new AppError(ErrorCode.CORRUPT_FILE, '下载结果不是可读取的图片'); }
      finally { await decoder.release(); }
      checkCall(ctx);
      if (this.disposed) { throw new AppError(ErrorCode.CANCELLED, '阅读会话已关闭'); }
      if (width <= 0 || height <= 0 || width > 8192 || height > 60000 || width * height > this.maxPixels) {
        throw new AppError(ErrorCode.UNSUPPORTED, '图像超过当前阅读解码预算');
      }
      const asset: ReaderAsset = { uri: 'file://' + this.files.localPath(key), width: width, height: height, bytes: bytes };
      this.remember(page.ordinal, key, asset); await this.disk.put(identity, key, asset); this.forced.delete(page.ordinal);
      return asset;
    } catch (error) {
      writing();
      this.remove(key);
      if (error instanceof AppError) { throw error; }
      throw new AppError(ErrorCode.IO_ERROR, '图像缓存读取失败');
    } finally { writing(); }
  }

  private remember(index: number, key: string, asset: ReaderAsset): void {
    this.entries.push({ index: index, key: key, asset: asset, release: FilePins.pin(this.files.localPath(key)) });
    while (this.entries.length > 4) { this.entries.shift()!.release(); }
  }

  dispose(): void {
    this.disposed = true;
    this.park();
  }
  park(): void {
    this.pending.forEach((pending: PendingAsset) => pending.cancel.cancel());
    this.pending.clear();
    this.entries.forEach((item: CacheItem) => item.release());
    this.entries.length = 0;
  }

  forget(index: number): void {
    this.forced.add(index);
    const pending = this.pending.get(index);
    if (pending) { pending.cancel.cancel(); this.pending.delete(index); }
    const position = this.entries.findIndex((item: CacheItem) => item.index === index);
    if (position >= 0) { const item = this.entries.splice(position, 1)[0]; item.release(); this.remove(item.key); }
  }

  private remove(key: string): void {
    try { if (!FilePins.inUse(this.files.localPath(key))) { this.files.remove(key); } }
    catch (_) { hilog.error(0x0001, 'HSReader', 'READER_CACHE_CLEANUP_FAILED'); }
  }
}
