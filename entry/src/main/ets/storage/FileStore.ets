import { fileIo as fs, statfs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { ByteSink } from '../model/ByteSink';
import { AppError, ErrorCode } from '../model/ErrorTypes';

export class FileSink implements ByteSink {
  private readonly fd: number;

  constructor(fd: number) { this.fd = fd; }

  async write(chunk: ArrayBuffer): Promise<void> {
    let offset = 0;
    while (offset < chunk.byteLength) {
      const remaining = chunk.slice(offset);
      let written = 0;
      try { written = await fs.write(this.fd, remaining); }
      catch (error) {
        const code = (error as BusinessError).code;
        throw new AppError(code === 13900025 || code === 13900041 ? ErrorCode.STORAGE_FULL : ErrorCode.IO_ERROR,
          code === 13900025 || code === 13900041 ? '存储空间不足，请释放空间后重试' : '本地文件写入失败');
      }
      if (written <= 0) { throw new AppError(ErrorCode.IO_ERROR, '文件写入没有进展'); }
      offset += written;
    }
  }
}

export class FileStore {
  private readonly root: string;

  constructor(filesDir: string, namespace: string = 'foundation') {
    if (!/^[a-z0-9_-]{1,64}$/.test(namespace)) { throw new AppError(ErrorCode.POLICY_DENIED, '私有目录标识无效'); }
    this.root = filesDir + '/' + namespace;
    if (!fs.accessSync(this.root)) { fs.mkdirSync(this.root); }
  }

  private path(key: string): string {
    if (!/^[a-z0-9_-]{1,64}$/.test(key)) { throw new AppError(ErrorCode.POLICY_DENIED, '本地资源标识无效'); }
    return this.root + '/' + key;
  }

  localPath(key: string): string { return this.path(key); }
  exists(key: string): boolean { return fs.accessSync(this.path(key)); }
  size(key: string): number | undefined { const path = this.path(key); return fs.accessSync(path) ? fs.statSync(path).size : undefined; }
  keys(): string[] { return fs.listFileSync(this.root); }
  async freeBytes(): Promise<number> { return statfs.getFreeSize(this.root); }
  removePart(key: string): void { const path = this.path(key) + '.part'; if (fs.accessSync(path)) { fs.unlinkSync(path); } }

  remove(key: string): void {
    const target = this.path(key);
    if (fs.accessSync(target)) { fs.unlinkSync(target); }
    if (fs.accessSync(target + '.part')) { fs.unlinkSync(target + '.part'); }
  }

  async writeText(key: string, value: string): Promise<void> {
    const target = this.path(key);
    const file = fs.openSync(target + '.part', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      const bytes = new util.TextEncoder().encodeInto(value);
      await new FileSink(file.fd).write(bytes.buffer as ArrayBuffer);
      fs.fsyncSync(file.fd);
    } finally { fs.closeSync(file); }
    fs.renameSync(target + '.part', target);
  }

  readText(key: string, maxBytes: number = 2097152): string | undefined {
    const path = this.path(key);
    if (!fs.accessSync(path)) { return undefined; }
    if (fs.statSync(path).size > maxBytes) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '本地文件超过读取限额'); }
    return fs.readTextSync(path);
  }

  async writeStream(key: string, writer: (sink: ByteSink) => Promise<void>, verify?: (partPath: string) => Promise<void>): Promise<number> {
    const target = this.path(key);
    const file = fs.openSync(target + '.part', fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    let closed = false;
    try {
      await writer(new FileSink(file.fd));
      fs.fsyncSync(file.fd);
      const bytes = fs.statSync(file.fd).size;
      fs.closeSync(file);
      closed = true;
      if (verify) { await verify(target + '.part'); }
      fs.renameSync(target + '.part', target);
      return bytes;
    } catch (error) {
      if (!closed) { fs.closeSync(file); closed = true; }
      if (fs.accessSync(target + '.part')) { fs.unlinkSync(target + '.part'); }
      if (error instanceof AppError) { throw error; }
      throw new AppError(ErrorCode.IO_ERROR, '本地文件写入或提交失败');
    } finally { if (!closed) { fs.closeSync(file); } }
  }

  async commitPart(key: string, verify: (partPath: string) => Promise<void>): Promise<number> {
    const target = this.path(key); const part = target + '.part';
    const file = fs.openSync(part, fs.OpenMode.READ_WRITE);
    let bytes = 0;
    try { fs.fsyncSync(file.fd); bytes = fs.statSync(file.fd).size; } finally { fs.closeSync(file); }
    await verify(part); fs.renameSync(part, target); return bytes;
  }
}
