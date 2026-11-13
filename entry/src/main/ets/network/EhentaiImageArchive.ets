import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { ByteSink } from '../model/ByteSink';
import { checkCall } from '../source/SourceHttp';
import { ehentaiAddress } from './EhentaiAccess';

class ImageMimePart {
  private boundary: string = '';
  private headers: string = '';
  private readingHeaders: boolean = true;
  private selected: boolean = false;
  private padded: boolean = false;
  private data: string = '';
  private size: number = 0;
  private readonly address: string;
  private readonly limit: number;
  private readonly sink: ByteSink;
  complete: boolean = false;

  constructor(address: string,limit: number,sink: ByteSink) {
    this.address = address;
    this.limit = limit;
    this.sink = sink;
  }

  private select(): boolean {
    const location = /^Content-Location:[ \t]*(\S+)[ \t]*$/im.exec(this.headers)?.[1] || '';
    let address: string;
    try { address = ehentaiAddress(location,true).toString(); }
    catch (_) { return false; }
    if (address !== this.address) { return false; }
    if (!/^Content-Type:[ \t]*image\/(?:png|jpe?g|webp)(?:[ \t]*;.*)?[ \t]*$/im.test(this.headers) ||
      !/^Content-Transfer-Encoding:[ \t]*base64[ \t]*$/im.test(this.headers)) {
      throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 页面归档的图片格式无效');
    }
    return true;
  }

  async flush(last: boolean): Promise<void> {
    const length = last ? this.data.length : Math.floor(this.data.length / 4) * 4;
    if (!length) { return; }
    if (length % 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(this.data.substring(0,length))) {
      throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 页面归档的图片编码不完整');
    }
    const bytes = new util.Base64Helper().decodeSync(this.data.substring(0,length));
    if (this.size + bytes.byteLength > this.limit) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'E-Hentai 图片超过下载大小限制'); }
    await this.sink.write(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
    this.size += bytes.byteLength;
    this.data = this.data.substring(length);
  }

  line(line: string): void {
    if (this.boundary && (line === this.boundary || line === this.boundary + '--')) {
      if (this.selected) { this.complete = true; return; }
      this.readingHeaders = line === this.boundary;
      this.headers = '';
      return;
    }
    if (this.readingHeaders) {
      if (line) {
        this.headers += line + '\n';
        if (this.headers.length > 32768) { throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 页面归档头超过限制'); }
        return;
      }
      if (!this.boundary) {
        const match = /\bboundary\s*=\s*(?:"([^"\r\n]+)"|([^;\s]+))/i.exec(this.headers);
        const boundary = match?.[1] || match?.[2] || '';
        if (!boundary || boundary.length > 200) { throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 页面归档缺少分隔符'); }
        this.boundary = '--' + boundary;
      } else { this.selected = this.select(); }
      this.readingHeaders = false;
      return;
    }
    if (this.selected && line) {
      if (this.padded || !/^[A-Za-z0-9+/]+={0,2}$/.test(line)) {
        throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 页面归档的图片编码无效');
      }
      this.padded = line.endsWith('=');
      this.data += line;
    }
  }

  bytes(): number { return this.size; }
}

// Parse only the selected image's MIME part. Never open the archive as a webpage.
export async function readEhentaiArchiveImage(path: string,address: string,limit: number,ctx: CallContext,sink: ByteSink): Promise<number> {
  const ceiling = Math.ceil(limit * 1.5) + 1048576;
  const file = fs.openSync(path,fs.OpenMode.READ_ONLY);
  try {
    if (fs.statSync(file.fd).size > ceiling) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'ArkWeb 页面归档超过大小限制'); }
    const part = new ImageMimePart(address,limit,sink);
    const decoder = util.TextDecoder.create('utf-8');
    const buffer = new ArrayBuffer(65536);
    let tail = '';
    let total = 0;
    while (!part.complete) {
      checkCall(ctx);
      const bytes = await fs.read(file.fd,buffer);
      if (!bytes) { break; }
      total += bytes;
      if (total > ceiling) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'ArkWeb 页面归档超过大小限制'); }
      const text = tail + decoder.decodeToString(new Uint8Array(buffer,0,bytes));
      const lines = text.split('\n');
      tail = lines.pop() || '';
      if (tail.length > 32768) { throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 页面归档的行超过限制'); }
      for (const line of lines) {
        part.line(line.endsWith('\r') ? line.substring(0,line.length - 1) : line);
        if (part.complete) { break; }
      }
      await part.flush(part.complete);
    }
    if (!part.complete && tail) { part.line(tail); await part.flush(part.complete); }
    if (!part.complete || !part.bytes()) { throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 页面归档缺少完整的正文图片'); }
    return part.bytes();
  } finally { fs.closeSync(file); }
}
