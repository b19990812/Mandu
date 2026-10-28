import { util } from '@kit.ArkTS';
import { ByteSink } from '../model/ByteSink';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { ComicArchive } from './ComicArchive';

interface StoredEntry { name: Uint8Array; offset: number; size: number; crc: number; }
// Standard non-ZIP64 Stored ZIP: bounded per-image buffers and a small central directory.
export class StoredComicWriter {
  private readonly sink: ByteSink;
  private readonly entries: StoredEntry[] = [];
  private readonly names: Set<string> = new Set();
  private offset: number = 0;
  private finished: boolean = false;
  constructor(sink: ByteSink) { this.sink = sink; }
  private async write(bytes: ArrayBuffer): Promise<void> { await this.sink.write(bytes); this.offset += bytes.byteLength; }
  async add(name: string,bytes: ArrayBuffer): Promise<void> {
    if (this.finished || !/^\d{5}\.(png|jpg|webp)$/.test(name) || this.names.has(name) || this.entries.length >= 2000 || bytes.byteLength < 1 || bytes.byteLength > ComicArchive.MAX_IMAGE || this.offset + bytes.byteLength + 262144 > ComicArchive.MAX_TOTAL) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'CBZ名称、图片或归档大小超限'); }
    const encoded = new util.TextEncoder().encodeInto(name); const crc = ComicArchive.crc(new Uint8Array(bytes)); const header = new ArrayBuffer(30 + encoded.length); const view = new DataView(header);
    view.setUint32(0,0x04034b50,true); view.setUint16(4,20,true); view.setUint16(6,0x800,true); view.setUint16(12,0x21,true); view.setUint32(14,crc,true); view.setUint32(18,bytes.byteLength,true); view.setUint32(22,bytes.byteLength,true); view.setUint16(26,encoded.length,true); new Uint8Array(header,30).set(encoded);
    const entry: StoredEntry = { name: encoded,offset: this.offset,size: bytes.byteLength,crc: crc };
    await this.write(header); await this.write(bytes); this.entries.push(entry); this.names.add(name);
  }
  async finish(): Promise<void> {
    if (this.finished || !this.entries.length) { throw new AppError(ErrorCode.CONFLICT,'CBZ为空或已关闭'); } this.finished = true;
    const start = this.offset;
    for (let i = 0; i < this.entries.length; i++) {
      const entry = this.entries[i]; const header = new ArrayBuffer(46 + entry.name.length); const view = new DataView(header);
      view.setUint32(0,0x02014b50,true); view.setUint16(4,20,true); view.setUint16(6,20,true); view.setUint16(8,0x800,true); view.setUint16(14,0x21,true); view.setUint32(16,entry.crc,true); view.setUint32(20,entry.size,true); view.setUint32(24,entry.size,true); view.setUint16(28,entry.name.length,true); view.setUint32(42,entry.offset,true); new Uint8Array(header,46).set(entry.name); await this.write(header);
    }
    const end = new ArrayBuffer(22); const view = new DataView(end); view.setUint32(0,0x06054b50,true); view.setUint16(8,this.entries.length,true); view.setUint16(10,this.entries.length,true); view.setUint32(12,this.offset - start,true); view.setUint32(16,start,true); await this.write(end);
  }
}
