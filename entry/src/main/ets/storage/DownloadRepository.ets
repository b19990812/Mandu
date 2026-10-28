import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { DownloadTaskRecord, DownloadedPage, OfflineSnapshot } from '../model/DownloadTypes';
import { ChapterRecord } from '../model/LibraryTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { ManifestCodec } from '../parsing/ManifestCodec';
import { DbConnection, ReaderDatabase } from './ReaderDatabase';

const TASK = 'SELECT d.id,d.chapter_id,d.source_id,d.rule_key,d.state,d.desired_state,d.manifest,d.error_code,d.total,d.completed,d.updated_at,m.title,c.title,d.queue_order FROM downloads d JOIN chapters c ON c.id=d.chapter_id JOIN manga m ON m.id=c.manga_id';
const STATES: string[] = ['queued','running','paused','failed','completed','cancelled'];

export class DownloadRepository {
  private readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  private row(row: relationalStore.ResultSet): DownloadTaskRecord {
    const state = row.getString(4); const desired = row.getString(5);
    if (STATES.indexOf(state) < 0 || ['run','paused','cancelled'].indexOf(desired) < 0) { throw new AppError(ErrorCode.CONFIG_INVALID, '下载状态不受支持'); }
    return { id: row.getString(0), chapterId: row.getString(1), sourceId: row.getString(2), ruleKey: row.getString(3), state: state,
      desiredState: desired, manifest: row.getString(6), errorCode: row.getString(7), total: row.getLong(8), completed: row.getLong(9), updatedAt: row.getLong(10), mangaTitle: row.getString(11), chapterTitle: row.getString(12),queueOrder: row.getLong(13) };
  }
  async task(id: string): Promise<DownloadTaskRecord | undefined> { return this.db.read(async (db) => (await db.rows(TASK + ' WHERE d.id=?', [id], (row) => this.row(row)))[0]); }
  async list(): Promise<DownloadTaskRecord[]> {
    return this.db.read((db) => db.rows(TASK.replace('d.manifest', "''") + " ORDER BY CASE d.state WHEN 'running' THEN 0 WHEN 'queued' THEN 1 WHEN 'paused' THEN 2 WHEN 'failed' THEN 3 WHEN 'completed' THEN 4 ELSE 5 END,CASE WHEN d.state IN ('queued','running') THEN d.queue_order ELSE -d.updated_at END,d.id", [], (row) => this.row(row)));
  }
  async enqueue(chapter: ChapterRecord, ruleKey: string): Promise<DownloadTaskRecord> {
    const id = await this.db.transaction(async (db) => {
      const existing = (await db.rows(TASK + ' WHERE d.chapter_id=?', [chapter.id], (row) => this.row(row)))[0];
      if (existing) {
        if (existing.state === 'completed' || existing.state === 'running' && existing.desiredState === 'run') { return existing.id; }
        if (existing.state === 'cancelled') {
          await db.run('UPDATE downloads SET rule_key=?,manifest=\'\',total=0,completed=0,error_code=\'\' WHERE id=?', [ruleKey, existing.id]);
        }
        await db.run('UPDATE downloads SET state=\'queued\',desired_state=\'run\',error_code=\'\',updated_at=? WHERE id=?', [Date.now(), existing.id]); return existing.id;
      }
      const id = util.generateRandomUUID();
      const order = (await db.rows('SELECT COALESCE(MAX(queue_order),0)+1 FROM downloads',[],(row) => row.getLong(0)))[0];
      await db.run('INSERT INTO downloads(id,chapter_id,source_id,rule_key,state,desired_state,updated_at,queue_order) VALUES(?,?,?,?,\'queued\',\'run\',?,?)', [id, chapter.id, chapter.ref.sourceId, ruleKey, Date.now(),order]);
      return id;
    });
    return (await this.task(id))!;
  }
  async claim(id: string): Promise<boolean> {
    return this.db.transaction(async (db) => {
      const task = (await db.rows(TASK + ' WHERE d.id=?', [id], (row) => this.row(row)))[0];
      if (!task || task.state !== 'queued' || task.desiredState !== 'run') { return false; }
      await db.run('UPDATE downloads SET state=\'running\',error_code=\'\',updated_at=? WHERE id=?', [Date.now(), id]); return true;
    });
  }
  async move(id: string,direction: number): Promise<void> {
    if (direction !== -1 && direction !== 1) { throw new AppError(ErrorCode.CONFIG_INVALID,'队列方向无效'); }
    await this.db.transaction(async (db) => {
      const tasks = await db.rows("SELECT id FROM downloads WHERE state='queued' AND desired_state='run' ORDER BY queue_order,id",[],(row) => row.getString(0));
      const current = tasks.indexOf(id); const target = current + direction;
      if (current < 0) { throw new AppError(ErrorCode.CONFLICT,'只有排队中的章节可以重排'); }
      if (target < 0 || target >= tasks.length) { return; }
      const swap = tasks[target]; tasks[target] = id; tasks[current] = swap;
      // Renumbering the pending queue also resolves equal timestamps from older schemas.
      for (let i = 0; i < tasks.length; i++) { await db.run('UPDATE downloads SET queue_order=?,updated_at=? WHERE id=?',[i + 1,Date.now(),tasks[i]]); }
    });
  }
  async desired(id: string, desired: string): Promise<void> {
    if (['run','paused','cancelled'].indexOf(desired) < 0) { throw new AppError(ErrorCode.CONFIG_INVALID, '下载操作无效'); }
    await this.db.transaction(async (db) => {
      const task = (await db.rows(TASK + ' WHERE d.id=?', [id], (row) => this.row(row)))[0]; if (!task) { return; }
      if (task.state === 'completed') { return; }
      const state = task.state === 'running' ? 'running' : desired === 'run' ? 'queued' : desired === 'paused' ? 'paused' : 'cancelled';
      await db.run('UPDATE downloads SET desired_state=?,state=?,updated_at=? WHERE id=?', [desired, state, Date.now(), id]);
    });
  }
  async stop(id: string, code: string): Promise<void> {
    await this.db.transaction(async (db) => {
      const task = (await db.rows(TASK + ' WHERE d.id=?', [id], (row) => this.row(row)))[0]; if (!task || task.state === 'completed') { return; }
      const disabled = code === 'DISABLED' || code === 'CONTENT_CHANGED';
      const state = task.desiredState === 'cancelled' ? 'cancelled' : task.desiredState === 'paused' || disabled || ['OFFLINE','WAITING_WIFI','STORAGE_FULL'].indexOf(code) >= 0 ? 'paused' : 'failed';
      await db.run('UPDATE downloads SET state=?,desired_state=?,error_code=?,updated_at=? WHERE id=?', [state, disabled ? 'paused' : task.desiredState, code, Date.now(), id]);
    });
  }
  async manifest(id: string, raw: string): Promise<void> {
    const manifest = new ManifestCodec().decode(raw);
    await this.db.transaction(async (db) => {
      const current = (await db.rows(TASK + ' WHERE d.id=?', [id], (row) => this.row(row)))[0];
      if (!current || current.ruleKey !== manifest.ruleKey || current.manifest && current.manifest !== raw) { throw new AppError(ErrorCode.CONTENT_CHANGED, '章节清单已改变，请取消旧任务后重新下载'); }
      await db.run('UPDATE downloads SET manifest=?,total=?,updated_at=? WHERE id=?', [raw, manifest.pageKeys.length, Date.now(), id]);
    });
  }
  async pages(taskId: string): Promise<DownloadedPage[]> {
    return this.db.read((db) => db.rows('SELECT task_id,page_key,ordinal,file_key,bytes,width,height,digest FROM download_pages WHERE task_id=? ORDER BY ordinal', [taskId], (row): DownloadedPage => ({
      taskId: row.getString(0), pageKey: row.getString(1), ordinal: row.getLong(2), fileKey: row.getString(3), bytes: row.getLong(4), width: row.getLong(5), height: row.getLong(6), digest: row.getString(7)
    })));
  }
  async savePage(page: DownloadedPage): Promise<void> {
    await this.db.transaction(async (db) => {
      const task = (await db.rows(TASK + ' WHERE d.id=?', [page.taskId], (row) => this.row(row)))[0];
      if (!task || !task.manifest) { throw new AppError(ErrorCode.CONFLICT, '下载任务或清单不存在'); }
      const manifest = new ManifestCodec().decode(task.manifest);
      if (manifest.pageKeys[page.ordinal] !== page.pageKey || page.bytes <= 0 || !/^[a-f0-9]{64}$/.test(page.digest)) { throw new AppError(ErrorCode.CORRUPT_FILE, '下载图像与完整清单不符'); }
      await db.run('INSERT OR REPLACE INTO download_pages(task_id,page_key,ordinal,file_key,bytes,width,height,digest) VALUES(?,?,?,?,?,?,?,?)',
        [page.taskId,page.pageKey,page.ordinal,page.fileKey,page.bytes,page.width,page.height,page.digest]);
      await db.run('UPDATE downloads SET completed=(SELECT COUNT(*) FROM download_pages WHERE task_id=?),updated_at=? WHERE id=?', [page.taskId,Date.now(),page.taskId]);
    });
  }
  async dropPage(taskId: string, pageKey: string, pause: boolean = true): Promise<void> {
    await this.db.transaction(async (db) => {
      await db.run('DELETE FROM download_pages WHERE task_id=? AND page_key=?', [taskId,pageKey]);
      await db.run('DELETE FROM offline_manifests WHERE task_id=?', [taskId]);
      await db.run('UPDATE downloads SET completed=(SELECT COUNT(*) FROM download_pages WHERE task_id=?),error_code=\'CORRUPT_FILE\',updated_at=?' + (pause ? ',state=\'paused\',desired_state=\'paused\'' : '') + ' WHERE id=?', [taskId,Date.now(),taskId]);
    });
  }
  async complete(id: string): Promise<void> {
    await this.db.transaction(async (db) => {
      const task = (await db.rows(TASK + ' WHERE d.id=?', [id], (row) => this.row(row)))[0];
      if (!task || task.state !== 'running' || task.desiredState !== 'run' || task.total < 1 || task.total !== task.completed || new ManifestCodec().decode(task.manifest).pageKeys.length !== task.total) {
        throw new AppError(ErrorCode.CONFLICT, '下载尚未完整或已请求暂停，不能提交离线章节');
      }
      await db.run('INSERT OR REPLACE INTO offline_manifests(chapter_id,task_id,total,updated_at) VALUES(?,?,?,?)', [task.chapterId,id,task.total,Date.now()]);
      await db.run('UPDATE downloads SET state=\'completed\',error_code=\'\',updated_at=? WHERE id=?', [Date.now(),id]);
    });
  }
  async snapshot(chapterId: string): Promise<OfflineSnapshot | undefined> {
    const task = await this.db.read(async (db) => (await db.rows(TASK + ' WHERE d.chapter_id=?', [chapterId], (row) => this.row(row)))[0]);
    if (!task || !task.manifest) { return undefined; }
    const manifest = new ManifestCodec().decode(task.manifest); const pages = await this.pages(task.id);
    if (manifest.ruleKey !== task.ruleKey || pages.some((page: DownloadedPage) => manifest.pageKeys[page.ordinal] !== page.pageKey)) { throw new AppError(ErrorCode.CORRUPT_FILE, '离线版本或图像次序不符'); }
    if (pages.length === 0) { return undefined; }
    const complete = await this.db.read(async (db) => (await db.rows('SELECT total FROM offline_manifests WHERE chapter_id=? AND task_id=?', [chapterId, task.id], (row) => row.getLong(0)))[0] === manifest.pageKeys.length);
    return { task: task, manifest: manifest, pages: pages, complete: complete && pages.length === manifest.pageKeys.length };
  }
  async clear(id: string): Promise<void> {
    await this.db.transaction(async (db) => {
      await db.run('DELETE FROM offline_manifests WHERE task_id=?', [id]); await db.run('DELETE FROM download_pages WHERE task_id=?', [id]);
      await db.run('DELETE FROM agent_transfers WHERE task_id=?', [id]);
      await db.run('UPDATE downloads SET state=\'cancelled\',desired_state=\'cancelled\',manifest=\'\',total=0,completed=0,error_code=\'\',updated_at=? WHERE id=?', [Date.now(),id]);
    });
  }
  async recover(): Promise<void> {
    await this.db.transaction(async (db) => {
      await db.run('UPDATE downloads SET state=CASE WHEN desired_state=\'run\' THEN \'queued\' WHEN desired_state=\'paused\' THEN \'paused\' ELSE \'cancelled\' END,updated_at=? WHERE state=\'running\'', [Date.now()]);
    });
  }
  async park(id: string): Promise<void> { await this.db.transaction((db) => db.run('UPDATE downloads SET state=\'queued\',error_code=\'WAITING_FOREGROUND\',updated_at=? WHERE id=? AND desired_state=\'run\' AND state=\'running\'', [Date.now(),id])); }
  async repair(id: string): Promise<void> {
    await this.db.transaction(async (db) => {
      await db.run('DELETE FROM offline_manifests WHERE task_id=?', [id]);
      await db.run('UPDATE downloads SET state=\'queued\',desired_state=\'run\',error_code=\'\',updated_at=? WHERE id=?', [Date.now(),id]);
    });
  }
}
