import { util } from '@kit.ArkTS';
import { ComicArchive } from '../local/ComicArchive';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { common } from '@kit.AbilityKit';
import { ReaderDatabase } from '../storage/ReaderDatabase';

export async function archiveProbe(context: common.UIAbilityContext): Promise<string> {
  const compressed = new Uint8Array([203,72,205,201,201,7,0]); const archive = new ComicArchive();
  const decoded = await archive.image({ size: compressed.length,read: (offset: number,length: number): ArrayBuffer => compressed.buffer.slice(offset,offset + length) as ArrayBuffer },{ name: 'probe.png',offset: 0,compressed: 7,bytes: 5,method: 8,crc: 907060870 });
  if (util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(new Uint8Array(decoded)) !== 'hello') { throw new AppError(ErrorCode.CORRUPT_FILE,'原生归档内容不符'); }
  let rejected = false;
  try { await archive.image({ size: compressed.length,read: (offset: number,length: number): ArrayBuffer => compressed.buffer.slice(offset,offset + length) as ArrayBuffer },{ name: 'false.png',offset: 0,compressed: 7,bytes: 1,method: 8,crc: 907060870 }); } catch (_) { rejected = true; }
  if (!rejected) { throw new AppError(ErrorCode.CORRUPT_FILE,'原生Deflate未拒绝虚假长度'); }
  const counts = await ReaderDatabase.shared(context).read(async (db): Promise<number[]> => {
    const version = (await db.rows('PRAGMA user_version',[],(row) => row.getLong(0)))[0];
    const invalid = await db.rows('PRAGMA foreign_key_check',[],(row) => row.getString(0));
    if (version !== 6 || invalid.length) { throw new AppError(ErrorCode.CORRUPT_FILE,'阅读数据库版本或外键校验失败'); }
    const books = (await db.rows('SELECT COUNT(*) FROM manga WHERE favorite=1',[],(row) => row.getLong(0)))[0];
    const offline = (await db.rows('SELECT COUNT(*) FROM offline_manifests',[],(row) => row.getLong(0)))[0];
    await db.rows('SELECT queue_order FROM downloads LIMIT 1',[],(row) => row.getLong(0)); return [books,offline];
  });
  return '归档探针通过：原生Raw Deflate、实际长度、CRC与虚假长度拒绝；schema6/外键有效，收藏' + counts[0].toString() + '、离线章' + counts[1].toString();
}
