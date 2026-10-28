import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';

export async function fileDigest(path: string, ctx?: CallContext): Promise<string> {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const size = fs.statSync(file.fd).size;
    if (size < 1 || size > 33554432) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '图像文件超过32MiB校验限额'); }
    const digest = cryptoFramework.createMd('SHA256'); const buffer = new ArrayBuffer(65536); let offset = 0;
    while (offset < size) {
      if (ctx && (ctx.cancel.cancelled || Date.now() >= ctx.deadlineMs)) { throw new AppError(ctx.cancel.cancelled ? ErrorCode.CANCELLED : ErrorCode.TIMEOUT, '文件校验已取消或超时'); }
      const count = fs.readSync(file.fd, buffer, { offset: offset, length: Math.min(buffer.byteLength, size - offset) });
      if (count <= 0) { throw new AppError(ErrorCode.CORRUPT_FILE, '图像文件提前结束'); }
      await digest.update({ data: new Uint8Array(buffer, 0, count) }); offset += count;
    }
    if (fs.statSync(file.fd).size !== size) { throw new AppError(ErrorCode.CONTENT_CHANGED, '校验期间图像文件发生变化'); }
    const result = await digest.digest(); return Array.from(result.data).map((value: number) => value.toString(16).padStart(2, '0')).join('');
  } finally { fs.closeSync(file); }
}
