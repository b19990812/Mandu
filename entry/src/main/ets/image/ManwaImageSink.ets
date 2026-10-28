import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { ByteSink } from '../model/ByteSink';
import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkCall } from '../source/SourceHttp';

// Stream the site's public IV-prefixed AES image container into the existing atomic file sink.
// Ordinary images pass through. FileVerifier still validates the decoded file before commit.
export class ManwaImageSink implements ByteSink {
  private readonly sink: ByteSink; private readonly ctx: CallContext; private readonly limit: number;
  private prefix: Uint8Array = new Uint8Array(0); private cipher?: cryptoFramework.Cipher;
  private mode: string = ''; private received: number = 0; private emitted: number = 0; private finished: boolean = false;
  constructor(sink: ByteSink,ctx: CallContext,limit: number) { this.sink = sink; this.ctx = ctx; this.limit = limit; }
  private plain(bytes: Uint8Array): boolean {
    return bytes[0] === 255 && bytes[1] === 216 || bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71 ||
      bytes[0] === 71 && bytes[1] === 73 && bytes[2] === 70 || bytes[0] === 82 && bytes[1] === 73 && bytes[2] === 70 && bytes[3] === 70;
  }
  private async emit(bytes: Uint8Array): Promise<void> {
    checkCall(this.ctx); this.emitted += bytes.length; if (this.emitted > this.limit) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫蛙解码图片超过大小限额'); }
    if (bytes.length) { await this.sink.write(bytes.slice().buffer as ArrayBuffer); }
  }
  async write(chunk: ArrayBuffer): Promise<void> {
    checkCall(this.ctx); if (this.finished) { throw new AppError(ErrorCode.IO_ERROR,'图片解码已结束'); }
    this.received += chunk.byteLength; if (this.received > this.limit) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫蛙编码图片超过大小限额'); }
    let bytes = new Uint8Array(chunk);
    if (!this.mode) {
      const take = Math.min(32 - this.prefix.length,bytes.length); const joined = new Uint8Array(this.prefix.length + take); joined.set(this.prefix); joined.set(bytes.subarray(0,take),this.prefix.length); this.prefix = joined;
      bytes = bytes.subarray(take); if (this.prefix.length < 32) { return; }
      if (this.plain(this.prefix)) { this.mode = 'plain'; await this.emit(this.prefix); }
      else {
        this.mode = 'aes';
        try {
          const key = await cryptoFramework.createSymKeyGenerator('AES256').convertKey({ data: new util.TextEncoder().encodeInto('0B6666A0-BB59-1381-B746-a0E4C9AC') });
          this.cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
          await this.cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE,key,{ algName: 'IvParamsSpec',iv: { data: this.prefix.slice(0,16) } } as cryptoFramework.IvParamsSpec);
          await this.decode(this.prefix.slice(16));
        } catch (error) { if (error instanceof AppError) { throw error; } throw new AppError(ErrorCode.CORRUPT_FILE,'漫蛙图片容器解码失败'); }
      }
      this.prefix = new Uint8Array(0);
    }
    if (bytes.length) { if (this.mode === 'plain') { await this.emit(bytes); } else { await this.decode(bytes); } }
  }
  private async decode(bytes: Uint8Array): Promise<void> {
    let output: cryptoFramework.DataBlob;
    try { output = await this.cipher!.update({ data: bytes }); }
    catch (_) { throw new AppError(ErrorCode.CORRUPT_FILE,'漫蛙图片密文无效'); }
    await this.emit(output.data);
  }
  async finish(): Promise<void> {
    checkCall(this.ctx); if (this.finished) { throw new AppError(ErrorCode.IO_ERROR,'图片解码重复结束'); } this.finished = true;
    if (!this.mode) {
      if (this.prefix.length >= 4 && this.plain(this.prefix)) { await this.emit(this.prefix); return; }
      throw new AppError(ErrorCode.CORRUPT_FILE,'漫蛙图片数据为空或被截断');
    }
    if (this.mode === 'aes') {
      if ((this.received - 16) % 16 !== 0) { throw new AppError(ErrorCode.CORRUPT_FILE,'漫蛙图片密文长度无效'); }
      let output: cryptoFramework.DataBlob;
      try { output = await this.cipher!.doFinal(null); }
      catch (_) { throw new AppError(ErrorCode.CORRUPT_FILE,'漫蛙图片解码校验失败'); }
      await this.emit(output.data);
    }
  }
}
