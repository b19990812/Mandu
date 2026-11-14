import { CallContext } from '../model/RequestTypes';
import { ChapterPageSource, PageRef, SourceRef } from '../model/SourceTypes';
import { DownloadedPage } from '../model/DownloadTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { FileStore } from '../storage/FileStore';
import { FilePins } from '../storage/FilePins';
import { fileDigest } from '../storage/FileDigest';
import { checkCall } from '../source/SourceHttp';
import { ReaderAsset } from './ReaderAssetCache';
import { AssetProvider } from './AssetProvider';
import { ReaderTrace } from '../diagnostic/ReaderTrace';

export class OfflineAssetProvider implements AssetProvider {
  private readonly files: FileStore;
  private readonly pages: DownloadedPage[];
  private readonly pins: (() => void)[] = [];
  private disposed: boolean = false;
  constructor(files: FileStore, pages: DownloadedPage[]) {
    this.files = files; this.pages = pages;
    pages.forEach((page: DownloadedPage) => this.pins.push(FilePins.pin(files.localPath(page.fileKey))));
  }
  async load(_source: ChapterPageSource | undefined, _chapter: SourceRef, page: PageRef, ctx: CallContext): Promise<ReaderAsset> {
    const started = Date.now();
    checkCall(ctx); if (this.disposed) { throw new AppError(ErrorCode.CANCELLED, '阅读会话已关闭'); }
    if (this.pins.length === 0) { this.pages.forEach((item: DownloadedPage) => this.pins.push(FilePins.pin(this.files.localPath(item.fileKey)))); }
    const saved = this.pages.find((item: DownloadedPage) => item.pageKey === page.pageKey);
    if (!saved) { throw new AppError(ErrorCode.OFFLINE, '这一图尚未下载，请联网补齐章节'); }
    if (saved.width < 1 || saved.width > 8192 || saved.height < 1 || saved.height > 60000 || saved.width * saved.height > 134217728 || saved.bytes < 1 || saved.bytes > 33554432) {
      throw new AppError(ErrorCode.CORRUPT_FILE, '离线图像尺寸或长度记录异常');
    }
    const path = this.files.localPath(saved.fileKey);
    const verifyStarted = Date.now();
    try {
      if (await fileDigest(path, ctx) !== saved.digest) { throw new AppError(ErrorCode.CORRUPT_FILE, '离线图像摘要不符，请到下载页修复'); }
      ReaderTrace.record(ctx.trace,'offline-file-verify',Date.now() - verifyStarted,'ok','offline',0,saved.bytes);
    } catch (error) {
      ReaderTrace.record(ctx.trace,'offline-file-verify',Date.now() - verifyStarted,error instanceof AppError ? error.code : 'failed','offline',0,saved.bytes);
      if (error instanceof AppError) { throw error; }
      throw new AppError(ErrorCode.CORRUPT_FILE, '离线图像缺失或损坏，请到下载页修复');
    }
    checkCall(ctx); if (this.disposed) { throw new AppError(ErrorCode.CANCELLED, '阅读会话已关闭'); }
    const asset: ReaderAsset = { uri: 'file://' + path, width: saved.width, height: saved.height, bytes: saved.bytes };
    ReaderTrace.record(ctx.trace,'page-asset-ready',Date.now() - started,'ok','offline',0,saved.bytes);
    return asset;
  }
  forget(_index: number): void { /* Retrying verifies again; a browser cache operation never deletes offline files. */ }
  park(): void { this.pins.forEach((release) => release()); this.pins.length = 0; }
  dispose(): void { if (this.disposed) { return; } this.disposed = true; this.park(); }
}
