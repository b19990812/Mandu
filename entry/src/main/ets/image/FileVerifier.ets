import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { fileDigest } from '../storage/FileDigest';
import { checkCall } from '../source/SourceHttp';

export interface VerifiedImage { bytes: number; width: number; height: number; digest: string; }

export class FileVerifier {
  async verify(path: string, ctx: CallContext): Promise<VerifiedImage> {
    checkCall(ctx); const bytes = fs.statSync(path).size;
    if (bytes < 1 || bytes > 33554432) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '图像文件为空或超过32MiB'); }
    this.container(path, bytes);
    const source = image.createImageSource(path);
    let preview: image.PixelMap | undefined = undefined;
    try {
      const info = await source.getImageInfo(); const width = info.size.width; const height = info.size.height;
      if (['image/png','image/jpeg','image/jpg','image/webp'].indexOf(info.mimeType) < 0 || width < 1 || height < 1 || width > 8192 || height > 60000 || width * height > 134217728) {
        throw new AppError(ErrorCode.UNSUPPORTED, '图像格式或尺寸超过离线支持范围');
      }
      const scale = Math.min(1, 256 / width, 1024 / height);
      preview = await source.createPixelMap({ desiredSize: { width: Math.max(1, Math.round(width * scale)), height: Math.max(1, Math.round(height * scale)) }, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      if (preview.getPixelBytesNumber() > 4194304) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '校验预览超过像素预算'); }
      checkCall(ctx); const digest = await fileDigest(path, ctx); checkCall(ctx);
      return { bytes: bytes, width: width, height: height, digest: digest };
    } catch (error) {
      if (error instanceof AppError) { throw error; }
      throw new AppError(ErrorCode.CORRUPT_FILE, '下载文件不能正确解码');
    } finally { if (preview) { await preview.release(); } await source.release(); }
  }
  private container(path: string, size: number): void {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const header = new ArrayBuffer(16); const count = fs.readSync(file.fd, header, { offset: 0, length: Math.min(16, size) });
      const h = new Uint8Array(header); const tail = new ArrayBuffer(Math.min(12, size)); fs.readSync(file.fd, tail, { offset: size - tail.byteLength, length: tail.byteLength }); const t = new Uint8Array(tail);
      const jpeg = count >= 3 && h[0] === 255 && h[1] === 216 && h[2] === 255 && size >= 4 && t[t.length - 2] === 255 && t[t.length - 1] === 217;
      const png = count >= 8 && h[0] === 137 && h[1] === 80 && h[2] === 78 && h[3] === 71 && h[4] === 13 && h[5] === 10 && h[6] === 26 && h[7] === 10 && t.length === 12 &&
        t[0] === 0 && t[1] === 0 && t[2] === 0 && t[3] === 0 && t[4] === 73 && t[5] === 69 && t[6] === 78 && t[7] === 68;
      const webp = count >= 12 && h[0] === 82 && h[1] === 73 && h[2] === 70 && h[3] === 70 && h[8] === 87 && h[9] === 69 && h[10] === 66 && h[11] === 80 && new DataView(header).getUint32(4, true) + 8 === size;
      if (!jpeg && !png && !webp) { throw new AppError(ErrorCode.CORRUPT_FILE, '图像容器不完整或格式不支持'); }
    } finally { fs.closeSync(file); }
  }
}
