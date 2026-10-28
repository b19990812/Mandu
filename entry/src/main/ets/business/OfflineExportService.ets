import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { DownloadRepository } from '../storage/DownloadRepository';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { FileStore, FileSink } from '../storage/FileStore';
import { FilePins } from '../storage/FilePins';
import { StoredComicWriter } from '../local/StoredComicWriter';
import { checkCall } from '../source/SourceHttp';

export class OfflineExportService {
  private readonly records: DownloadRepository;
  private readonly files: FileStore;
  constructor(context: common.UIAbilityContext) { this.records = new DownloadRepository(ReaderDatabase.shared(context)); this.files = new FileStore(context.filesDir,'downloads'); }
  async export(taskId: string,uri: string,ctx: CallContext,progress: (done: number,total: number) => void): Promise<void> {
    const task = await this.records.task(taskId); const snapshot = task ? await this.records.snapshot(task.chapterId) : undefined;
    if (!snapshot?.complete || snapshot.task.id !== taskId) { throw new AppError(ErrorCode.CONFLICT,'仅完整离线章节可导出CBZ'); }
    const release: (() => void)[] = []; let target: fs.File | undefined = undefined; let success = false;
    try {
      snapshot.pages.forEach((page) => release.push(FilePins.pin(this.files.localPath(page.fileKey)))); checkCall(ctx);
      target = fs.openSync(uri,fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC); const writer = new StoredComicWriter(new FileSink(target.fd));
      for (let i = 0; i < snapshot.pages.length; i++) {
        checkCall(ctx); const page = snapshot.pages[i]; if (page.ordinal !== i || page.bytes < 12 || page.bytes > 33554432) { throw new AppError(ErrorCode.CORRUPT_FILE,'离线图片顺序或长度无效'); }
        const file = fs.openSync(this.files.localPath(page.fileKey),fs.OpenMode.READ_ONLY); let bytes: ArrayBuffer;
        try {
          if (fs.statSync(file.fd).size !== page.bytes) { throw new AppError(ErrorCode.CORRUPT_FILE,'离线图片长度改变'); }
          bytes = new ArrayBuffer(page.bytes); let offset = 0;
          while (offset < page.bytes) { checkCall(ctx); const buffer = new ArrayBuffer(Math.min(65536,page.bytes - offset)); const count = fs.readSync(file.fd,buffer,{ offset: offset,length: buffer.byteLength }); if (count < 1) { throw new AppError(ErrorCode.CORRUPT_FILE,'离线图片不完整'); } new Uint8Array(bytes).set(new Uint8Array(buffer,0,count),offset); offset += count; }
        } finally { fs.closeSync(file); }
        const digest = cryptoFramework.createMd('SHA256'); await digest.update({ data: new Uint8Array(bytes) }); const hash = Array.from((await digest.digest()).data).map((value: number) => value.toString(16).padStart(2,'0')).join('');
        if (hash !== page.digest) { throw new AppError(ErrorCode.CORRUPT_FILE,'离线图片摘要改变，请先修复'); }
        const h = new Uint8Array(bytes); const extension = h[0] === 137 && h[1] === 80 ? 'png' : h[0] === 255 && h[1] === 216 ? 'jpg' : h[0] === 82 && h[8] === 87 ? 'webp' : '';
        if (!extension) { throw new AppError(ErrorCode.UNSUPPORTED,'离线图片格式不支持CBZ导出'); }
        checkCall(ctx); await writer.add((i + 1).toString().padStart(5,'0') + '.' + extension,bytes); progress(i + 1,snapshot.pages.length);
      }
      checkCall(ctx); await writer.finish(); fs.fsyncSync(target.fd); success = true;
    } finally {
      try { if (target) { try { if (!success) { fs.truncateSync(target.fd,0); } } finally { fs.closeSync(target); } } }
      finally { release.forEach((unpin: () => void) => unpin()); }
    }
  }
}
