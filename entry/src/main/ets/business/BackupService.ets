import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { JsonExtractor } from '../parsing/JsonExtractor';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { payloadDigest } from '../storage/PayloadDigest';

interface BackupTable { name: string; columns: string[]; numeric: number[]; primary: number[]; }
interface BackupRow { table: BackupTable; values: (string | number)[]; }
export interface BackupPreview { manga: number; chapters: number; positions: number; categories: number; }
const TABLES: BackupTable[] = [
  { name: 'manga',columns: ['id','source_id','remote_id','locator','title','description','cover','status','authors','tags','favorite','updated_at'],numeric: [10,11],primary: [0] },
  { name: 'chapters',columns: ['id','manga_id','source_id','remote_id','locator','title','ordinal','active'],numeric: [6,7],primary: [0] },
  { name: 'categories',columns: ['id','name'],numeric: [],primary: [0] },
  { name: 'manga_categories',columns: ['manga_id','category_id'],numeric: [],primary: [0,1] },
  { name: 'progress',columns: ['manga_id','chapter_id','page_key','page_index','in_page_ratio','completed','updated_at'],numeric: [3,4,5,6],primary: [0] },
  { name: 'chapter_progress',columns: ['chapter_id','manga_id','page_key','page_index','in_page_ratio','completed','bookmarked','position_at','read_at','bookmark_at','last_read_at','history_visible','history_hidden_at'],numeric: [3,4,5,6,7,8,9,10,11,12],primary: [0] },
  { name: 'reader_settings',columns: ['key','value'],numeric: [],primary: [0] }
];

// Versioned line arrays avoid property-obfuscation contracts and keep each JSON
// parse bounded. Download paths, rule payloads, cookies and credentials are excluded.
export class BackupService {
  static readonly MAX_BYTES: number = 16777216;
  private readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  private setting(key: string): boolean {
    return /^(?:reader\.(?:mode|direction|background|scale|tap\.zones|tap\.invert)(?::[a-f0-9]{64})?|reader\.(?:prefetch|prefetch\.pages|auto\.next|preload\.next|skip\.read|prefetch\.wifi|incognito)|app\.theme|download\.wifi|cache\.mib|trial\.position:[a-f0-9]{64})$/.test(key);
  }
  async export(): Promise<string> {
    const lines = await this.db.read(async (db) => {
      const lines: string[] = ['["HS_MIHON_BACKUP",1,' + Date.now().toString() + ']']; let count = 0; let bytes = 0;
      for (let i = 0; i < TABLES.length; i++) {
        const table = TABLES[i];
        for (let offset = 0; offset <= 100000; offset += 256) {
          const rows = await db.rows('SELECT ' + table.columns.join(',') + ' FROM ' + table.name + ' ORDER BY ' + table.primary.map((index: number) => table.columns[index]).join(',') + ' LIMIT 256 OFFSET ?',[offset],(row): (string | number)[] => table.columns.map((_column: string,index: number): string | number => table.numeric.indexOf(index) >= 0 ? row.getDouble(index) : row.getString(index)));
          for (let j = 0; j < rows.length; j++) {
            if (table.name === 'reader_settings' && !this.setting(rows[j][0] as string)) { continue; }
            const line = JSON.stringify([table.name,...rows[j]]); bytes += new util.TextEncoder().encodeInto(line).byteLength + 1;
            if (++count > 100000 || bytes > BackupService.MAX_BYTES - 1024 || line.length > 262144) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'备份超过16MiB或100000行上限'); }
            lines.push(line);
          }
          if (rows.length < 256) { break; }
        }
      }
      return lines;
    });
    const body = lines.join('\n'); return body + '\n["END",' + (lines.length - 1).toString() + ',' + JSON.stringify(await payloadDigest(body)) + ']\n';
  }
  private async parse(text: string): Promise<BackupRow[]> {
    if (text.length > BackupService.MAX_BYTES || new util.TextEncoder().encodeInto(text).byteLength > BackupService.MAX_BYTES) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'备份最大16MiB'); }
    const lines = text.trimEnd().split('\n');
    if (lines.length < 2 || lines.length > 100002) { throw new AppError(ErrorCode.CONFIG_INVALID,'备份记录数量无效'); }
    const parser = new JsonExtractor(); const header = parser.parse(lines[0]); const footer = parser.parse(lines[lines.length - 1]);
    if (header.kind !== 'array' || header.items.length !== 3 || header.items[0].scalar !== 'HS_MIHON_BACKUP' || header.items[1].kind !== 'number' || header.items[1].scalar !== '1' || footer.kind !== 'array' || footer.items.length !== 3 || footer.items[0].scalar !== 'END' || footer.items[1].kind !== 'number' || Number(footer.items[1].scalar) !== lines.length - 2 || footer.items[2].scalar !== await payloadDigest(lines.slice(0,-1).join('\n'))) { throw new AppError(ErrorCode.CORRUPT_FILE,'备份版本、记录数或SHA256不符'); }
    const output: BackupRow[] = []; const keys: Set<string> = new Set();
    for (let i = 1; i < lines.length - 1; i++) {
      if (lines[i].length > 262144) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'单条备份记录过大'); }
      const node = parser.parse(lines[i]); const table = TABLES.find((table: BackupTable) => table.name === node.items[0]?.scalar);
      if (node.kind !== 'array' || !table || node.items.length !== table.columns.length + 1) { throw new AppError(ErrorCode.CONFIG_INVALID,'备份表或字段不受支持'); }
      const values: (string | number)[] = [];
      for (let j = 0; j < table.columns.length; j++) {
        const field = node.items[j + 1]; const numeric = table.numeric.indexOf(j) >= 0;
        if (numeric ? field.kind !== 'number' || !Number.isFinite(Number(field.scalar)) || Number(field.scalar) < 0 || Number(field.scalar) > Number.MAX_SAFE_INTEGER : field.kind !== 'string' || field.scalar.length > (table.columns[j] === 'description' ? 65536 : 8192)) { throw new AppError(ErrorCode.CONFIG_INVALID,'备份字段类型或范围无效'); }
        if (numeric && table.columns[j] !== 'in_page_ratio' && !Number.isSafeInteger(Number(field.scalar))) { throw new AppError(ErrorCode.CONFIG_INVALID,'备份整数字段无效'); }
        if (table.columns[j] === 'in_page_ratio' && Number(field.scalar) > 1 || ['favorite','active','completed','bookmarked','history_visible'].indexOf(table.columns[j]) >= 0 && Number(field.scalar) > 1) { throw new AppError(ErrorCode.CONFIG_INVALID,'备份状态字段无效'); }
        values.push(numeric ? Number(field.scalar) : field.scalar);
      }
      const key = table.name + ':' + JSON.stringify(table.primary.map((index: number): string | number => values[index]));
      if (keys.has(key)) { throw new AppError(ErrorCode.CONFLICT,'备份存在重复身份'); } keys.add(key);
      if (table.name === 'manga') {
        if (values[0] !== await payloadDigest(JSON.stringify([values[1],values[2]]))) { throw new AppError(ErrorCode.CONFIG_INVALID,'漫画身份与来源不符'); }
        for (const index of [8,9]) { const list = parser.parse(values[index] as string); if (list.kind !== 'array' || list.items.some((item) => item.kind !== 'string')) { throw new AppError(ErrorCode.CONFIG_INVALID,'漫画数组字段无效'); } }
      }
      if (table.name === 'chapters' && values[0] !== await payloadDigest(JSON.stringify([values[1],values[3]]))) { throw new AppError(ErrorCode.CONFIG_INVALID,'章节身份不符'); }
      if (table.name === 'reader_settings' && !this.setting(values[0] as string)) { throw new AppError(ErrorCode.POLICY_DENIED,'备份含不允许恢复的设置'); }
      if (table.name === 'categories' && (!(values[0] as string) || !(values[1] as string).trim() || (values[1] as string).length > 32)) { throw new AppError(ErrorCode.CONFIG_INVALID,'分类记录无效'); }
      output.push({ table: table,values: values });
    }
    return output;
  }
  async preview(text: string): Promise<BackupPreview> {
    const rows = await this.parse(text); return { manga: rows.filter((row: BackupRow) => row.table.name === 'manga').length,chapters: rows.filter((row: BackupRow) => row.table.name === 'chapters').length,positions: rows.filter((row: BackupRow) => row.table.name === 'chapter_progress').length,categories: rows.filter((row: BackupRow) => row.table.name === 'categories').length };
  }
  async restore(text: string): Promise<BackupPreview> {
    const preview = await this.preview(text); const rows = await this.parse(text);
    await this.db.transaction(async (db) => {
      const categories: Map<string,string> = new Map();
      for (let tableIndex = 0; tableIndex < TABLES.length; tableIndex++) {
        const table = TABLES[tableIndex]; const selected = rows.filter((row: BackupRow) => row.table.name === table.name);
        for (let index = 0; index < selected.length; index++) {
          const values = selected[index].values.slice();
          if (table.name === 'categories') {
            const same = await db.rows('SELECT id FROM categories WHERE name=?',[values[1]],(row) => row.getString(0));
            if (same.length) { categories.set(values[0] as string,same[0]); continue; }
            const used = await db.rows('SELECT id FROM categories WHERE id=?',[values[0]],(row) => row.getString(0));
            const id = used.length ? util.generateRandomUUID() : values[0] as string; categories.set(values[0] as string,id); values[0] = id;
          }
          if (table.name === 'manga_categories') { values[1] = categories.get(values[1] as string) || values[1]; }
          let suffix = '';
          if (table.name === 'manga') { suffix = ' ON CONFLICT(id) DO UPDATE SET favorite=MAX(manga.favorite,excluded.favorite)'; }
          if (table.name === 'progress') { suffix = ' ON CONFLICT(manga_id) DO UPDATE SET ' + table.columns.slice(1).map((column: string) => column + '=excluded.' + column).join(',') + ' WHERE excluded.updated_at>progress.updated_at'; }
          if (table.name === 'chapter_progress') { suffix = this.positionMerge(); }
          await db.run('INSERT ' + (suffix ? '' : 'OR IGNORE ') + 'INTO ' + table.name + '(' + table.columns.join(',') + ') VALUES(' + table.columns.map(() => '?').join(',') + ')' + suffix,values);
        }
      }
      await db.run('UPDATE progress SET completed=COALESCE((SELECT completed FROM chapter_progress WHERE chapter_progress.chapter_id=progress.chapter_id),completed)');
      const invalid = await db.rows('SELECT c.id FROM chapters c JOIN manga m ON m.id=c.manga_id WHERE c.source_id<>m.source_id LIMIT 1',[],(row) => row.getString(0));
      if (invalid.length) { throw new AppError(ErrorCode.CONFLICT,'章节与漫画来源不一致，恢复已回滚'); }
      const positions = await db.rows('SELECT p.chapter_id FROM chapter_progress p JOIN chapters c ON c.id=p.chapter_id WHERE p.manga_id<>c.manga_id UNION ALL SELECT p.chapter_id FROM progress p JOIN chapters c ON c.id=p.chapter_id WHERE p.manga_id<>c.manga_id LIMIT 1',[],(row) => row.getString(0));
      if (positions.length) { throw new AppError(ErrorCode.CONFLICT,'进度与漫画归属不一致，恢复已回滚'); }
    });
    return preview;
  }
  private positionMerge(): string {
    return ' ON CONFLICT(chapter_id) DO UPDATE SET ' +
      ['page_key','page_index','in_page_ratio'].map((column: string) => column + '=CASE WHEN excluded.position_at>chapter_progress.position_at THEN excluded.' + column + ' ELSE chapter_progress.' + column + ' END').join(',') +
      ',position_at=MAX(chapter_progress.position_at,excluded.position_at),completed=CASE WHEN excluded.read_at>chapter_progress.read_at THEN excluded.completed ELSE chapter_progress.completed END,read_at=MAX(chapter_progress.read_at,excluded.read_at),bookmarked=CASE WHEN excluded.bookmark_at>chapter_progress.bookmark_at THEN excluded.bookmarked ELSE chapter_progress.bookmarked END,bookmark_at=MAX(chapter_progress.bookmark_at,excluded.bookmark_at),last_read_at=MAX(chapter_progress.last_read_at,excluded.last_read_at),history_visible=CASE WHEN excluded.history_hidden_at>chapter_progress.history_hidden_at AND excluded.history_hidden_at>=chapter_progress.last_read_at THEN 0 WHEN excluded.last_read_at>MAX(chapter_progress.last_read_at,chapter_progress.history_hidden_at) THEN excluded.history_visible ELSE chapter_progress.history_visible END,history_hidden_at=MAX(chapter_progress.history_hidden_at,excluded.history_hidden_at)';
  }
}
