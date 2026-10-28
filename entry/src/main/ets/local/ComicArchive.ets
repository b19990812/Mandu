import { util } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';

export interface ArchiveInput { size: number; read: (offset: number, length: number) => ArrayBuffer; }
export interface ComicEntry { name: string; offset: number; compressed: number; bytes: number; method: number; crc: number; }
export function naturalName(a: string,b: string): number {
  const left = a.toLowerCase().match(/[0-9]+|[^0-9]+/g) || []; const right = b.toLowerCase().match(/[0-9]+|[^0-9]+/g) || [];
  for (let i = 0; i < Math.min(left.length,right.length); i++) {
    if (left[i] === right[i]) { continue; }
    if (/^[0-9]+$/.test(left[i]) && /^[0-9]+$/.test(right[i])) {
      const x = left[i].replace(/^0+/,'') || '0'; const y = right[i].replace(/^0+/,'') || '0';
      const compared = x.length - y.length || x.localeCompare(y); if (compared) { return compared; }
    } else { return left[i].localeCompare(right[i]); }
  }
  return left.length - right.length || a.localeCompare(b);
}
export class ComicArchive {
  static readonly MAX_IMAGE: number = 33554432;
  static readonly MAX_TOTAL: number = 536870912;
  static image(name: string): boolean { return /\.(?:png|jpe?g|webp)$/i.test(name); }
  static crc(bytes: Uint8Array): number {
    const table: number[] = [];
    for (let i = 0; i < 256; i++) { let value = i; for (let bit = 0; bit < 8; bit++) { value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1; } table.push(value >>> 0); }
    let crc = 0xffffffff; for (let i = 0; i < bytes.length; i++) { crc = table[(crc ^ bytes[i]) & 255] ^ (crc >>> 8); } return (crc ^ 0xffffffff) >>> 0;
  }
  entries(input: ArchiveInput, metadata: boolean = false): ComicEntry[] {
    if (input.size < 22 || input.size > ComicArchive.MAX_TOTAL) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'CBZ/ZIP必须在512MiB以内'); }
    const tail = new DataView(input.read(Math.max(0,input.size - 65557),Math.min(input.size,65557))); let end = -1;
    for (let i = tail.byteLength - 22; i >= 0; i--) { if (tail.getUint32(i,true) === 0x06054b50 && i + 22 + tail.getUint16(i + 20,true) === tail.byteLength) { end = i; break; } }
    if (end < 0 || tail.getUint16(end + 4,true) !== 0 || tail.getUint16(end + 6,true) !== 0 || tail.getUint16(end + 8,true) !== tail.getUint16(end + 10,true)) { throw new AppError(ErrorCode.UNSUPPORTED,'不支持分卷或缺少目录的ZIP'); }
    const count = tail.getUint16(end + 10,true); const size = tail.getUint32(end + 12,true); const offset = tail.getUint32(end + 16,true);
    const directoryEnd = input.size - tail.byteLength + end;
    if (count > 4096 || count < 1 || size > 2097152 || offset + size !== directoryEnd) { throw new AppError(ErrorCode.UNSUPPORTED,'不支持ZIP64、超大目录或附加记录'); }
    const raw = input.read(offset,size); const view = new DataView(raw); let cursor = 0; let total = 0;
    const entries: ComicEntry[] = []; const names: Set<string> = new Set();
    for (let i = 0; i < count; i++) {
      if (cursor + 46 > size || view.getUint32(cursor,true) !== 0x02014b50) { throw new AppError(ErrorCode.CORRUPT_FILE,'ZIP目录不完整'); }
      const flags = view.getUint16(cursor + 8,true); const method = view.getUint16(cursor + 10,true);
      const nameLength = view.getUint16(cursor + 28,true); const extra = view.getUint16(cursor + 30,true); const comment = view.getUint16(cursor + 32,true);
      if (nameLength < 1 || nameLength > 1024 || cursor + 46 + nameLength + extra + comment > size || view.getUint16(cursor + 34,true) !== 0) { throw new AppError(ErrorCode.CORRUPT_FILE,'ZIP文件名或目录长度无效'); }
      let name = ''; try { name = util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(new Uint8Array(raw,cursor + 46,nameLength)); } catch (_) { throw new AppError(ErrorCode.UNSUPPORTED,'请使用UTF-8文件名的CBZ/ZIP'); }
      const parts = name.replace(/\/$/,'').split('/');
      if (name.startsWith('/') || /^[a-z]:/i.test(name) || /[\\\u0000-\u001f\u007f]/.test(name) || parts.some((part: string) => part === '..' || part === '.' || part === '') || (view.getUint32(cursor + 38,true) >>> 16 & 0xf000) === 0xa000) { throw new AppError(ErrorCode.POLICY_DENIED,'ZIP包含越界路径或符号链接'); }
      if (names.has(name)) { throw new AppError(ErrorCode.CONFLICT,'ZIP存在重复文件名'); } names.add(name);
      if (!name.endsWith('/') && (ComicArchive.image(name) || metadata && /\.(?:xml|opf|xhtml|html)$/i.test(name)) && !name.startsWith('__MACOSX/')) {
        const bytes = view.getUint32(cursor + 24,true); const compressed = view.getUint32(cursor + 20,true); const local = view.getUint32(cursor + 42,true);
        if (flags & 1 || method !== 0 && method !== 8) { throw new AppError(ErrorCode.UNSUPPORTED,'仅支持未加密的Stored/Deflate图片'); }
        if (bytes < 1 || bytes > ComicArchive.MAX_IMAGE || compressed < 1 || compressed > ComicArchive.MAX_IMAGE || method === 0 && bytes !== compressed || local + 30 >= offset) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'ZIP单张图片超过32MiB或长度无效'); }
        const header = new DataView(input.read(local,30)); const localName = header.getUint16(26,true); const localExtra = header.getUint16(28,true);
        if (header.getUint32(0,true) !== 0x04034b50 || header.getUint16(8,true) !== method || header.getUint16(6,true) !== flags || localName !== nameLength) { throw new AppError(ErrorCode.CORRUPT_FILE,'ZIP本地头与目录不符'); }
        const named = util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(new Uint8Array(input.read(local + 30,localName)));
        const dataOffset = local + 30 + localName + localExtra;
        if (named !== name || dataOffset + compressed > offset) { throw new AppError(ErrorCode.CORRUPT_FILE,'ZIP图片数据范围无效'); }
        if (!(flags & 8) && (header.getUint32(14,true) !== view.getUint32(cursor + 16,true) || header.getUint32(18,true) !== compressed || header.getUint32(22,true) !== bytes)) { throw new AppError(ErrorCode.CORRUPT_FILE,'ZIP图片长度声明不一致'); }
        total += bytes; if (total > ComicArchive.MAX_TOTAL || entries.length >= 2000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'每章最多2000张或512MiB'); }
        entries.push({ name: name,offset: dataOffset,compressed: compressed,bytes: bytes,method: method,crc: view.getUint32(cursor + 16,true) });
      }
      cursor += 46 + nameLength + extra + comment;
    }
    if (cursor !== size || entries.length === 0) { throw new AppError(ErrorCode.UNSUPPORTED,'压缩包没有可读的JPEG/PNG/WebP图片'); }
    const ranges = entries.slice().sort((a: ComicEntry,b: ComicEntry) => a.offset - b.offset);
    for (let i = 1; i < ranges.length; i++) { if (ranges[i - 1].offset + ranges[i - 1].compressed > ranges[i].offset) { throw new AppError(ErrorCode.CORRUPT_FILE,'ZIP图片数据重叠'); } }
    return entries.sort((a: ComicEntry,b: ComicEntry) => naturalName(a.name,b.name));
  }
  async image(input: ArchiveInput, entry: ComicEntry): Promise<ArrayBuffer> {
    const compressed = input.read(entry.offset,entry.compressed); let output = compressed;
    if (entry.method === 8) {
      const zip = await zlib.createZip(); const target = new ArrayBuffer(entry.bytes + 1);
      const stream: zlib.ZStream = { nextIn: compressed,availableIn: entry.compressed,nextOut: target,availableOut: target.byteLength,totalIn: 0,totalOut: 0 };
      let initialized = false;
      try {
        if (await zip.inflateInit2(stream,-15) !== zlib.ReturnStatus.OK) { throw new AppError(ErrorCode.CORRUPT_FILE,'Deflate初始化失败'); } initialized = true;
        const status = await zip.inflate(stream,zlib.CompressFlushMode.FINISH);
        const actual = await zip.getZStream();
        if (status !== zlib.ReturnStatus.STREAM_END || actual.totalOut !== entry.bytes || actual.totalIn !== entry.compressed) { throw new AppError(ErrorCode.CORRUPT_FILE,'Deflate实际输出长度不符或超过限额'); }
        output = target.slice(0,entry.bytes);
      } finally { if (initialized) { await zip.inflateEnd(stream); } }
    }
    if (output.byteLength !== entry.bytes || ComicArchive.crc(new Uint8Array(output)) !== entry.crc) { throw new AppError(ErrorCode.CORRUPT_FILE,'ZIP图片CRC32或实际长度不符'); }
    return output;
  }
}
