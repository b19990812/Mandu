import { AppError, ErrorCode } from '../model/ErrorTypes';
import { HistoryRecord, ProgressRecord } from '../model/LibraryTypes';
import { CatalogRepository } from './CatalogRepository';
import { ReaderDatabase } from './ReaderDatabase';
import { HistoryDeletePlan, HistoryDeleteTarget, historyDeleteFrom } from '../model/HistoryDeletion';

interface HistoryRow extends ProgressRecord { chapterTitle: string; }
interface SavedProgressState { completed: number; positionAt: number; readAt: number; }

export class ProgressRepository {
  private readonly db: ReaderDatabase;
  private readonly catalog: CatalogRepository;
  constructor(db: ReaderDatabase, catalog: CatalogRepository) { this.db = db; this.catalog = catalog; }
  async get(mangaId: string): Promise<ProgressRecord | undefined> {
    return this.db.read(async (db) => (await db.rows('SELECT manga_id,chapter_id,page_key,page_index,in_page_ratio,completed,updated_at FROM progress WHERE manga_id=?', [mangaId], (row): ProgressRecord => ({
      mangaId: row.getString(0), chapterId: row.getString(1), pageKey: row.getString(2), pageIndex: row.getLong(3), inPageRatio: row.getDouble(4), completed: row.getLong(5) === 1, updatedAt: row.getLong(6)
    })))[0]);
  }
  async chapter(chapterId: string): Promise<ProgressRecord | undefined> {
    return this.db.read(async (db) => (await db.rows('SELECT manga_id,chapter_id,page_key,page_index,in_page_ratio,completed,position_at FROM chapter_progress WHERE chapter_id=? AND position_at>0',[chapterId],(row): ProgressRecord => ({
      mangaId: row.getString(0),chapterId: row.getString(1),pageKey: row.getString(2),pageIndex: row.getLong(3),inPageRatio: row.getDouble(4),completed: row.getLong(5) === 1,updatedAt: row.getLong(6)
    })))[0]);
  }
  async save(progress: ProgressRecord): Promise<void> {
    if (!Number.isSafeInteger(progress.pageIndex) || progress.pageIndex < 0 || !Number.isFinite(progress.inPageRatio) || progress.inPageRatio < 0 || progress.inPageRatio > 1 || progress.pageKey.length > 2048) {
      throw new AppError(ErrorCode.CONFIG_INVALID, '阅读进度参数无效');
    }
    await this.db.transaction(async (db) => {
      const belongs = await db.rows('SELECT id FROM chapters WHERE id=? AND manga_id=?', [progress.chapterId, progress.mangaId], (row) => row.getString(0));
      if (!belongs.length) { throw new AppError(ErrorCode.CONFLICT, '章节不属于当前漫画'); }
      const saved = (await db.rows('SELECT completed,position_at,read_at FROM chapter_progress WHERE chapter_id=?',[progress.chapterId],(row): SavedProgressState => ({ completed: row.getLong(0),positionAt: row.getLong(1),readAt: row.getLong(2) })))[0];
      if (saved && saved.positionAt > progress.updatedAt) { return; }
      // Native RDB queries can use a separate read connection. Derive the latest pointer
      // from the pre-write state instead of querying an uncommitted insert.
      const completed = progress.completed && (!saved || progress.updatedAt >= saved.readAt) ? 1 : saved?.completed || 0;
      await db.run('INSERT INTO chapter_progress(chapter_id,manga_id,page_key,page_index,in_page_ratio,completed,position_at,read_at,last_read_at,history_visible) VALUES(?,?,?,?,?,?,?,?,?,1) ON CONFLICT(chapter_id) DO UPDATE SET page_key=excluded.page_key,page_index=excluded.page_index,in_page_ratio=excluded.in_page_ratio,position_at=excluded.position_at,last_read_at=MAX(chapter_progress.last_read_at,excluded.last_read_at),history_visible=CASE WHEN excluded.position_at>=chapter_progress.history_hidden_at THEN 1 ELSE chapter_progress.history_visible END,completed=CASE WHEN excluded.completed=1 AND excluded.read_at>=chapter_progress.read_at THEN 1 ELSE chapter_progress.completed END,read_at=CASE WHEN excluded.completed=1 AND excluded.read_at>=chapter_progress.read_at THEN excluded.read_at ELSE chapter_progress.read_at END WHERE excluded.position_at>=chapter_progress.position_at',
        [progress.chapterId,progress.mangaId,progress.pageKey,progress.pageIndex,progress.inPageRatio,progress.completed ? 1 : 0,progress.updatedAt,progress.completed ? progress.updatedAt : 0,progress.updatedAt]);
      await db.run('INSERT INTO progress(manga_id,chapter_id,page_key,page_index,in_page_ratio,completed,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(manga_id) DO UPDATE SET chapter_id=excluded.chapter_id,page_key=excluded.page_key,page_index=excluded.page_index,in_page_ratio=excluded.in_page_ratio,completed=excluded.completed,updated_at=excluded.updated_at WHERE excluded.updated_at>=progress.updated_at',
        [progress.mangaId,progress.chapterId,progress.pageKey,progress.pageIndex,progress.inPageRatio,completed,progress.updatedAt]);
    });
  }
  async history(): Promise<HistoryRecord[]> {
    // Group before reading the list, so a long manga cannot crowd other books
    // out of history. Same-millisecond ties prefer the current resume pointer.
    const records = await this.db.read((db) => db.rows('SELECT p.manga_id,p.chapter_id,p.page_key,p.page_index,p.in_page_ratio,p.completed,p.last_read_at,c.title FROM chapter_progress p JOIN chapters c ON c.id=p.chapter_id JOIN (SELECT manga_id,MAX(last_read_at) AS last_read_at FROM chapter_progress WHERE history_visible=1 AND last_read_at>0 GROUP BY manga_id) h ON h.manga_id=p.manga_id AND h.last_read_at=p.last_read_at LEFT JOIN progress latest ON latest.manga_id=p.manga_id WHERE p.history_visible=1 AND p.last_read_at>0 ORDER BY p.last_read_at DESC,p.manga_id,CASE WHEN p.chapter_id=latest.chapter_id THEN 0 ELSE 1 END,p.chapter_id', [], (row): HistoryRow => ({
      mangaId: row.getString(0), chapterId: row.getString(1), pageKey: row.getString(2), pageIndex: row.getLong(3), inPageRatio: row.getDouble(4), completed: row.getLong(5) === 1, updatedAt: row.getLong(6), chapterTitle: row.getString(7)
    })));
    const output: HistoryRecord[] = [];
    const seen: Set<string> = new Set();
    for (let i = 0; i < records.length; i++) {
      if (seen.has(records[i].mangaId)) { continue; } seen.add(records[i].mangaId);
      const manga = await this.catalog.manga(records[i].mangaId); if (manga) { output.push({ manga: manga, progress: records[i], chapterTitle: records[i].chapterTitle }); }
    }
    return output;
  }
  async planHistoryDeletion(range: string,mangaId: string = '',before: number = Date.now()): Promise<HistoryDeletePlan> {
    const from = historyDeleteFrom(range,before);
    const args: (string | number)[] = mangaId ? [mangaId] : [];
    if (range !== 'all') { args.push(from,before); }
    const targets = await this.db.read((db) => db.rows('SELECT manga_id,MAX(last_read_at) FROM chapter_progress WHERE history_visible=1 AND last_read_at>0' +
      (mangaId ? ' AND manga_id=?' : '') + ' GROUP BY manga_id' + (range === 'all' ? '' : ' HAVING MAX(last_read_at)>=? AND MAX(last_read_at)<=?'),args,
      (row): HistoryDeleteTarget => ({ mangaId: row.getString(0),readAt: row.getLong(1) })));
    return { range: range,from: from,before: before,targets: targets };
  }
  async deleteHistory(plan: HistoryDeletePlan): Promise<number> {
    if (historyDeleteFrom(plan.range,plan.before) !== plan.from) { throw new AppError(ErrorCode.CONFIG_INVALID,'历史删除计划无效'); }
    const seen: Set<string> = new Set();
    plan.targets.forEach((target: HistoryDeleteTarget) => {
      if (!target.mangaId || target.mangaId.length > 512 || seen.has(target.mangaId) || !Number.isSafeInteger(target.readAt) || target.readAt < 1 || target.readAt >= Number.MAX_SAFE_INTEGER ||
        plan.range !== 'all' && (target.readAt < plan.from || target.readAt > plan.before)) { throw new AppError(ErrorCode.CONFIG_INVALID,'历史删除目标无效'); }
      seen.add(target.mangaId);
    });
    if (!plan.targets.length) { return 0; }
    return this.db.transaction(async (db) => {
      // Read before writing: native RDB may answer queries on another connection.
      const current = await db.rows('SELECT manga_id,MAX(last_read_at) FROM chapter_progress WHERE history_visible=1 AND last_read_at>0 GROUP BY manga_id',[],
        (row): HistoryDeleteTarget => ({ mangaId: row.getString(0),readAt: row.getLong(1) }));
      const latest: Map<string,number> = new Map(); current.forEach((target: HistoryDeleteTarget) => latest.set(target.mangaId,target.readAt));
      const targets = plan.targets.filter((target: HistoryDeleteTarget) => latest.get(target.mangaId) === target.readAt);
      const hiddenAt = Date.now() + 1;
      for (let i = 0; i < targets.length; i++) {
        const target = targets[i];
        await db.run('UPDATE chapter_progress SET history_visible=0,history_hidden_at=MAX(history_hidden_at,?) WHERE manga_id=? AND last_read_at<=?',
          [Math.max(hiddenAt,target.readAt + 1),target.mangaId,target.readAt]);
      }
      return targets.length;
    });
  }
  async clear(mangaId: string): Promise<void> { await this.deleteHistory(await this.planHistoryDeletion('all',mangaId)); }
  async hideChapter(chapterId: string): Promise<void> { await this.db.transaction((db) => db.run('UPDATE chapter_progress SET history_visible=0,history_hidden_at=? WHERE chapter_id=?',[Date.now(),chapterId])); }
  async mark(ids: string[], read: boolean, updatedAt: number = Date.now()): Promise<void> {
    if (ids.length > 20000) { throw new AppError(ErrorCode.CONFIG_INVALID,'一次最多修改20000章'); }
    await this.db.transaction(async (db) => {
      for (let i = 0; i < ids.length; i++) {
        const rows = await db.rows('SELECT manga_id FROM chapters WHERE id=?',[ids[i]],(row) => row.getString(0));
        if (!rows.length) { throw new AppError(ErrorCode.NOT_FOUND,'章节记录不存在'); }
        await db.run('INSERT OR IGNORE INTO chapter_progress(chapter_id,manga_id) VALUES(?,?)',[ids[i],rows[0]]);
        await db.run('UPDATE chapter_progress SET completed=?,read_at=?,page_key=CASE WHEN ?=0 THEN \'\' ELSE page_key END,page_index=CASE WHEN ?=0 THEN 0 ELSE page_index END,in_page_ratio=CASE WHEN ?=0 THEN 0 ELSE in_page_ratio END,position_at=CASE WHEN ?=0 THEN MAX(position_at,?) ELSE position_at END WHERE chapter_id=? AND read_at<=? AND position_at<=?',
          [read ? 1 : 0,updatedAt,read ? 1 : 0,read ? 1 : 0,read ? 1 : 0,read ? 1 : 0,updatedAt,ids[i],updatedAt,updatedAt]);
        await db.run('UPDATE progress SET completed=?,page_key=CASE WHEN ?=0 THEN \'\' ELSE page_key END,page_index=CASE WHEN ?=0 THEN 0 ELSE page_index END,in_page_ratio=CASE WHEN ?=0 THEN 0 ELSE in_page_ratio END,updated_at=? WHERE chapter_id=? AND updated_at<=?',
          [read ? 1 : 0,read ? 1 : 0,read ? 1 : 0,read ? 1 : 0,updatedAt,ids[i],updatedAt]);
      }
    });
  }
  async bookmark(chapterId: string, value: boolean, updatedAt: number = Date.now()): Promise<void> {
    await this.db.transaction(async (db) => {
      const rows = await db.rows('SELECT manga_id FROM chapters WHERE id=?',[chapterId],(row) => row.getString(0));
      if (!rows.length) { throw new AppError(ErrorCode.NOT_FOUND,'章节记录不存在'); }
      await db.run('INSERT OR IGNORE INTO chapter_progress(chapter_id,manga_id) VALUES(?,?)',[chapterId,rows[0]]);
      await db.run('UPDATE chapter_progress SET bookmarked=?,bookmark_at=? WHERE chapter_id=? AND bookmark_at<=?',[value ? 1 : 0,updatedAt,chapterId,updatedAt]);
    });
  }
}
