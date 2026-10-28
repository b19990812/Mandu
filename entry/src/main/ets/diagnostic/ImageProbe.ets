import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { ReaderAsset } from '../image/ReaderAssetCache';
import { DecodedTile, TileDecoder } from '../image/TileDecoder';
import { checkCall } from '../source/SourceHttp';
import { FileStore } from '../storage/FileStore';
import { FileVerifier } from '../download/FileVerifier';
import { JsonExtractor } from '../parsing/JsonExtractor';

const GLYPHS: string[][] = [
  ['111','101','101','101','111'], ['010','110','010','010','111'], ['111','001','111','100','111'],
  ['111','001','111','001','111'], ['101','101','111','001','001'], ['111','100','111','001','111'],
  ['111','100','111','101','111'], ['111','001','010','010','010'], ['111','101','111','101','111'], ['111','101','111','001','111']
];

// Fixture labels encode the ORIGINAL y coordinate. This catches a decoder returning
// a correctly sized but wrong crop; thresholding tolerates JPEG/WebP compression.
async function verifyMarker(tile: DecodedTile, sourceTop: number, sourceWidth: number): Promise<void> {
  const info = await tile.map.getImageInfo(); const buffer = new ArrayBuffer(tile.bytes); await tile.map.readPixelsToBuffer(buffer);
  const bytes = new Uint8Array(buffer); const stride = info.stride > 0 ? info.stride : info.size.width * 4;
  const scale = info.size.width / sourceWidth; const digits = sourceTop.toString();
  for (let position = 0; position < digits.length; position++) {
    const glyph = GLYPHS[Number(digits.charAt(position))];
    for (let row = 0; row < 5; row++) {
      for (let column = 0; column < 3; column++) {
        const x = Math.floor((24 + position * 32 + column * 8 + 4) * scale); const y = Math.floor((28 + row * 8) * scale);
        const offset = y * stride + x * 4;
        const dark = bytes[offset] < 128 && bytes[offset + 1] < 160;
        if (dark !== (glyph[row].charAt(column) === '1')) { throw new AppError(ErrorCode.CORRUPT_FILE, '分块标记不符：期望源行' + sourceTop.toString()); }
      }
    }
  }
}

export async function runImageProbe(context: common.UIAbilityContext, ctx: CallContext, long: boolean,
  progress: (text: string) => void): Promise<string> {
  const ordinary = ['ordinary.png', 'ordinary.jpg', 'ordinary.webp'];
  const names = long ? ['long_1080.png', 'long_1080.jpg', 'long_webp.webp', 'long_2160.png', 'long_2160.jpg'] : ordinary;
  const files = new FileStore(context.cacheDir, 'image_probe'); let operations = 0;
  const index = new JsonExtractor().parse(util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(context.resourceManager.getRawFileContentSync('image-matrix/index.json')));
  const iterations = long ? names.length : 20;
  for (let i = 0; i < iterations; i++) {
    checkCall(ctx); const filename = names[i % names.length]; const key = 'sample_' + i.toString();
    progress((long ? '长图区域：' : '普通图：') + filename + ' · ' + (i + 1).toString() + '/' + iterations.toString());
    const bytes = context.resourceManager.getRawFileContentSync('image-matrix/' + filename);
    try {
      await files.writeStream(key, async (sink) => { await sink.write(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer); });
      const source = image.createImageSource(files.localPath(key)); let width = 0; let height = 0;
      try { const info = await source.getImageInfo(); width = info.size.width; height = info.size.height; }
      finally { await source.release(); }
      const asset: ReaderAsset = { uri: 'file://' + files.localPath(key), width: width, height: height, bytes: bytes.byteLength };
      if (long || i < 3) {
        const expected = index.items.find((item) => item.members.get('file')?.scalar === filename)?.members.get('sha256')?.scalar;
        const verified = await new FileVerifier().verify(files.localPath(key), ctx);
        if (!expected || verified.digest !== expected) { throw new AppError(ErrorCode.CORRUPT_FILE, '原生分块SHA256与自有样本标准摘要不符'); }
      }
      const count = Math.ceil(height / TileDecoder.BLOCK_HEIGHT); const positions = long ? [0, Math.floor(count / 2), count - 1] : [0];
      for (let n = 0; n < positions.length; n++) {
        checkCall(ctx);
        const tile = await new TileDecoder().decode(asset, positions[n], Math.min(width, 1080), ctx);
        try {
          if (tile.bytes <= 0 || tile.bytes > 8388608) { throw new AppError(ErrorCode.CORRUPT_FILE, '像素分块大小异常'); }
          await verifyMarker(tile, positions[n] * TileDecoder.BLOCK_HEIGHT, width); operations++;
        }
        finally { await tile.release(); }
      }
    } finally { files.remove(key); }
  }
  if (!long) {
    const bytes = new util.TextEncoder().encodeInto('<html>not an image</html>');
    await files.writeStream('bad', async (sink) => { await sink.write(bytes.buffer as ArrayBuffer); });
    let source: image.ImageSource | undefined = undefined; let rejected = false;
    try { source = image.createImageSource(files.localPath('bad')); await source.getImageInfo(); }
    catch (_) { rejected = true; }
    finally { if (source) { await source.release(); } files.remove('bad'); }
    if (!rejected) { throw new AppError(ErrorCode.CORRUPT_FILE, '假图没有被拒绝'); }
  }
  if (TileDecoder.liveBytes() !== 0) { throw new AppError(ErrorCode.IO_ERROR, '离开图像后仍持有像素租约'); }
  return (long ? '长图区域' : 'JPEG/PNG/WebP普通图') + operations.toString() + '项通过；活跃像素0；像素高水位' + TileDecoder.peakBytes().toString() + '字节（系统峰值另记）';
}
