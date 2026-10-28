import { relationalStore } from '@kit.ArkData';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { ChapterRecord, MangaRecord } from '../model/LibraryTypes';
import { ChapterRef, MangaDetail, MangaSummary } from '../model/SourceTypes';
import { JsonExtractor } from '../parsing/JsonExtractor';
import { DbConnection, ReaderDatabase } from './ReaderDatabase';
import { payloadDigest } from './PayloadDigest';

const MANGA_SELECT = 'SELECT id,source_id,remote_id,locator,title,description,cover,status,authors,tags,favorite,updated_at FROM manga';
const CHAPTER_SELECT = 'SELECT c.id,c.manga_id,c.source_id,c.remote_id,c.locator,c.title,c.ordinal,c.active,CASE WHEN o.chapter_id IS NULL THEN 0 ELSE 1 END,COALESCE(p.completed,0),COALESCE(p.bookmarked,0),COALESCE(p.page_index,0),COALESCE(p.last_read_at,0) FROM chapters c LEFT JOIN offline_manifests o ON o.chapter_id=c.id LEFT JOIN chapter_progress p ON p.chapter_id=c.id';

export class CatalogRepository {
  readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  private strings(raw: string): string[] {
    const node = new JsonExtractor().parse(raw);
    if (node.kind !== 'array' || node.items.some((item) => item.kind !== 'string')) { throw new AppError(ErrorCode.CONFIG_INVALID, '漫画数组字段异常'); }
    return node.items.map((item) => item.scalar);
  }
  mangaRow(row: relationalStore.ResultSet): MangaRecord {
    return { id: row.getString(0), detail: { ref: { sourceId: row.getString(1), remoteId: row.getString(2), locator: row.getString(3) },
      title: row.getString(4), description: row.getString(5), cover: row.getString(6) || undefined, status: row.getString(7),
      authors: this.strings(row.getString(8)), tags: this.strings(row.getString(9)) }, favorite: row.getLong(10) === 1, updatedAt: row.getLong(11) };
  }
  async manga(id: string): Promise<MangaRecord | undefined> {
    return this.db.read(async (db) => (await db.rows(MANGA_SELECT + ' WHERE id=?', [id], (row) => this.mangaRow(row)))[0]);
  }
  async saveSearch(items: MangaSummary[], check: () => void = () => {}): Promise<MangaRecord[]> {
    const ids: string[] = [];
    for (let i = 0; i < items.length; i++) { check(); ids.push(await payloadDigest(JSON.stringify([items[i].ref.sourceId, items[i].ref.remoteId]))); }
    await this.db.transaction(async (db: DbConnection) => {
      for (let i = 0; i < items.length; i++) {
        check();
        const item = items[i]; const id = ids[i];
        await db.run('INSERT OR IGNORE INTO manga(id,source_id,remote_id,locator,title,cover,updated_at) VALUES(?,?,?,?,?,?,?)',
          [id, item.ref.sourceId, item.ref.remoteId, item.ref.locator, item.title, item.cover || '', Date.now()]);
        await db.run('UPDATE manga SET locator=?,title=?,cover=CASE WHEN ? = \'\' THEN cover ELSE ? END,updated_at=? WHERE id=?',
          [item.ref.locator, item.title, item.cover || '', item.cover || '', Date.now(), id]);
      }
      check();
    });
    // Native RDB may route reads through another connection. Read new records only
    // after commit, so a first visit from discovery/search never returns undefined.
    return this.db.read(async (db: DbConnection) => {
      const output: MangaRecord[] = [];
      for (let i = 0; i < ids.length; i++) {
        check(); const row = (await db.rows(MANGA_SELECT + ' WHERE id=?',[ids[i]],(result) => this.mangaRow(result)))[0];
        if (!row) { throw new AppError(ErrorCode.IO_ERROR,'漫画记录保存后不可读，请重试'); } output.push(row);
      }
      check(); return output;
    });
  }
  async saveDetail(mangaId: string, detail: MangaDetail, chapters: ChapterRef[], check: () => void = () => {}, queueNew: boolean = false): Promise<void> {
    const ids: string[] = [];
    for (let i = 0; i < chapters.length; i++) { check(); ids.push(await payloadDigest(JSON.stringify([mangaId, chapters[i].ref.remoteId]))); }
    await this.db.transaction(async (db) => {
      check();
      const old = await db.rows('SELECT id FROM chapters WHERE manga_id=?',[mangaId],(row) => row.getString(0));
      await db.run('UPDATE manga SET locator=?,title=?,description=?,cover=CASE WHEN ?=\'\' THEN cover ELSE ? END,status=?,authors=?,tags=?,updated_at=? WHERE id=?',
        [detail.ref.locator, detail.title, detail.description, detail.cover || '',detail.cover || '', detail.status, JSON.stringify(detail.authors), JSON.stringify(detail.tags), Date.now(), mangaId]);
      await db.run('UPDATE chapters SET active=0 WHERE manga_id=?', [mangaId]);
      for (let i = 0; i < chapters.length; i++) {
        check();
        const chapter = chapters[i];
        await db.run('INSERT OR IGNORE INTO chapters(id,manga_id,source_id,remote_id,locator,title,ordinal,active) VALUES(?,?,?,?,?,?,?,1)',
          [ids[i], mangaId, chapter.ref.sourceId, chapter.ref.remoteId, chapter.ref.locator, chapter.title, i]);
        await db.run('UPDATE chapters SET locator=?,title=?,ordinal=?,active=1 WHERE id=?', [chapter.ref.locator, chapter.title, i, ids[i]]);
        if (old.length > 0 && old.indexOf(ids[i]) < 0) { await db.run('INSERT OR IGNORE INTO chapter_updates(chapter_id,discovered_at) VALUES(?,?)',[ids[i],Date.now()]); if (queueNew) { await db.run('INSERT OR IGNORE INTO reader_settings(key,value) VALUES(?,?)',['updates.pending.' + ids[i],mangaId]); } }
      }
      check();
    });
  }
  private chapterRow(row: relationalStore.ResultSet): ChapterRecord {
    return { id: row.getString(0), mangaId: row.getString(1), ref: { sourceId: row.getString(2), remoteId: row.getString(3), locator: row.getString(4) },
      title: row.getString(5), ordinal: row.getLong(6), active: row.getLong(7) === 1, downloaded: row.getLong(8) === 1,
      read: row.getLong(9) === 1,bookmarked: row.getLong(10) === 1,lastPage: row.getLong(11),lastReadAt: row.getLong(12) };
  }
  async chapters(mangaId: string): Promise<ChapterRecord[]> {
    return this.db.read((db) => db.rows(CHAPTER_SELECT + ' WHERE c.manga_id=? AND (c.active=1 OR o.chapter_id IS NOT NULL) ORDER BY c.ordinal,c.id', [mangaId], (row) => this.chapterRow(row)));
  }
  async chapter(id: string): Promise<ChapterRecord | undefined> {
    return this.db.read(async (db) => (await db.rows(CHAPTER_SELECT + ' WHERE c.id=?', [id], (row) => this.chapterRow(row)))[0]);
  }
  async favorite(mangaId: string, value: boolean): Promise<void> { await this.db.transaction((db) => db.run('UPDATE manga SET favorite=? WHERE id=?', [value ? 1 : 0, mangaId])); }
  async favorites(ids: string[], value: boolean): Promise<void> {
    if (ids.length > 10000) { throw new AppError(ErrorCode.CONFIG_INVALID,'一次最多修改10000部漫画'); }
    await this.db.transaction(async (db) => { for (let i = 0; i < ids.length; i++) { await db.run('UPDATE manga SET favorite=? WHERE id=?',[value ? 1 : 0,ids[i]]); } });
  }
  async library(categoryId: string = ''): Promise<MangaRecord[]> {
    return this.db.read(async (db) => {
      const items = await db.rows(MANGA_SELECT + ' WHERE favorite=1' + (categoryId ? ' AND id IN(SELECT manga_id FROM manga_categories WHERE category_id=?)' : '') + ' ORDER BY updated_at DESC,id', categoryId ? [categoryId] : [], (row) => this.mangaRow(row));
      const stats = await db.rows('SELECT c.manga_id,SUM(CASE WHEN c.active=1 AND COALESCE(p.completed,0)=0 THEN 1 ELSE 0 END),SUM(CASE WHEN o.chapter_id IS NULL THEN 0 ELSE 1 END),MAX(COALESCE(p.last_read_at,0)) FROM chapters c LEFT JOIN chapter_progress p ON p.chapter_id=c.id LEFT JOIN offline_manifests o ON o.chapter_id=c.id GROUP BY c.manga_id',[],(row): string[] => [row.getString(0),row.getLong(1).toString(),row.getLong(2).toString(),row.getLong(3).toString()]);
      const byId: Map<string,string[]> = new Map(); stats.forEach((row: string[]) => byId.set(row[0],row));
      items.forEach((item: MangaRecord) => { const values = byId.get(item.id); item.unreadCount = values ? Number(values[1]) : 0; item.offlineCount = values ? Number(values[2]) : 0; item.lastReadAt = values ? Number(values[3]) : 0; });
      return items;
    });
  }
}
