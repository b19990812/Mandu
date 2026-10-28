import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';

function databaseFailure(error: Error, operation: string): AppError {
  if (error instanceof AppError) { return error; }
  const code = (error as BusinessError).code;
  const kind = error.name === 'TypeError' ? 'TypeError' : error.name === 'RangeError' ? 'RangeError' : 'native';
  hilog.error(0x0001, 'HSReader', 'DB_FAILURE op=%{public}s code=%{public}d kind=%{public}s', operation, Number.isFinite(code) ? code : 0, kind);
  return new AppError(ErrorCode.IO_ERROR, '阅读数据操作失败（' + operation + ' / ' + (Number.isFinite(code) ? code.toString() : kind) + '）');
}

const SCHEMA: string[] = [
  'CREATE TABLE IF NOT EXISTS manga (id TEXT PRIMARY KEY, source_id TEXT NOT NULL, remote_id TEXT NOT NULL, locator TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT \'\', cover TEXT NOT NULL DEFAULT \'\', status TEXT NOT NULL DEFAULT \'unknown\', authors TEXT NOT NULL DEFAULT \'[]\', tags TEXT NOT NULL DEFAULT \'[]\', favorite INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL, UNIQUE(source_id, remote_id))',
  'CREATE TABLE IF NOT EXISTS chapters (id TEXT PRIMARY KEY, manga_id TEXT NOT NULL REFERENCES manga(id), source_id TEXT NOT NULL, remote_id TEXT NOT NULL, locator TEXT NOT NULL, title TEXT NOT NULL, ordinal INTEGER NOT NULL, active INTEGER NOT NULL DEFAULT 1, UNIQUE(manga_id, remote_id))',
  'CREATE INDEX IF NOT EXISTS chapter_order ON chapters(manga_id, ordinal)',
  'CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE)',
  'CREATE TABLE IF NOT EXISTS manga_categories (manga_id TEXT NOT NULL REFERENCES manga(id), category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE, PRIMARY KEY(manga_id, category_id))',
  'CREATE TABLE IF NOT EXISTS progress (manga_id TEXT PRIMARY KEY REFERENCES manga(id), chapter_id TEXT NOT NULL REFERENCES chapters(id), page_key TEXT NOT NULL, page_index INTEGER NOT NULL, in_page_ratio REAL NOT NULL, completed INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS progress_time ON progress(updated_at DESC)',
  'CREATE TABLE IF NOT EXISTS downloads (id TEXT PRIMARY KEY, chapter_id TEXT NOT NULL UNIQUE REFERENCES chapters(id), source_id TEXT NOT NULL, state TEXT NOT NULL, desired_state TEXT NOT NULL, manifest TEXT NOT NULL DEFAULT \'\', error_code TEXT NOT NULL DEFAULT \'\', total INTEGER NOT NULL DEFAULT 0, completed INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS download_pages (task_id TEXT NOT NULL REFERENCES downloads(id) ON DELETE CASCADE, page_key TEXT NOT NULL, ordinal INTEGER NOT NULL, file_key TEXT NOT NULL, bytes INTEGER NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL, digest TEXT NOT NULL, PRIMARY KEY(task_id, page_key))',
  'CREATE TABLE IF NOT EXISTS offline_manifests (chapter_id TEXT PRIMARY KEY REFERENCES chapters(id), task_id TEXT NOT NULL REFERENCES downloads(id), total INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS reader_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)'
];

export class DbConnection {
  private readonly store: relationalStore.RdbStore;
  constructor(store: relationalStore.RdbStore) { this.store = store; }
  async run(sql: string, args: relationalStore.ValueType[] = []): Promise<void> {
    try { await this.store.executeSql(sql, args); } catch (error) { throw databaseFailure(error as Error, 'write'); }
  }
  async rows<T>(sql: string, args: relationalStore.ValueType[], map: (row: relationalStore.ResultSet) => T): Promise<T[]> {
    let result: relationalStore.ResultSet;
    try { result = await this.store.querySql(sql, args); } catch (error) { throw databaseFailure(error as Error, 'query'); }
    try { const output: T[] = []; while (result.goToNextRow()) { output.push(map(result)); } return output; }
    finally { result.close(); }
  }
}

// All operations on this shared connection are serialized, including reads during transactions.
export class ReaderDatabase {
  private static instances: Map<string, ReaderDatabase> = new Map();
  private readonly context: common.Context;
  private opening?: Promise<relationalStore.RdbStore>;
  private tail: Promise<void> = Promise.resolve();
  private constructor(context: common.Context) { this.context = context; }
  static shared(context: common.Context): ReaderDatabase {
    let instance = ReaderDatabase.instances.get(context.filesDir);
    if (!instance) { instance = new ReaderDatabase(context.getApplicationContext()); ReaderDatabase.instances.set(context.filesDir, instance); }
    return instance;
  }
  private async open(): Promise<relationalStore.RdbStore> {
    if (!this.opening) { this.opening = this.initialize(); }
    try { return await this.opening; } catch (error) { this.opening = undefined; throw this.failure(error as Error); }
  }
  private async initialize(): Promise<relationalStore.RdbStore> {
    const store = await relationalStore.getRdbStore(this.context, { name: 'reader.db', securityLevel: relationalStore.SecurityLevel.S1 });
    try {
      if (store.version > 6) { throw new AppError(ErrorCode.DATABASE_VERSION, '阅读数据库版本较新，拒绝写入'); }
      await store.executeSql('PRAGMA foreign_keys = ON');
      if (store.version === 0) {
        store.beginTransaction();
        try { for (let i = 0; i < SCHEMA.length; i++) { await store.executeSql(SCHEMA[i]); } store.version = 1; store.commit(); }
        catch (error) { store.rollBack(); throw this.failure(error as Error); }
      }
      if (store.version === 1) {
        store.beginTransaction();
        try {
          await store.executeSql('ALTER TABLE downloads ADD COLUMN rule_key TEXT NOT NULL DEFAULT \'\'');
          await store.executeSql('CREATE TABLE IF NOT EXISTS agent_transfers (task_id TEXT NOT NULL REFERENCES downloads(id) ON DELETE CASCADE,page_key TEXT NOT NULL,agent_id TEXT NOT NULL,agent_token TEXT NOT NULL,file_key TEXT NOT NULL,deadline_at INTEGER NOT NULL,http_status INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(task_id,page_key))');
          store.version = 2;
          store.commit();
        } catch (error) { store.rollBack(); throw this.failure(error as Error); }
      }
      if (store.version === 2) {
        store.beginTransaction();
        try { await store.executeSql('CREATE TABLE IF NOT EXISTS chapter_updates(chapter_id TEXT PRIMARY KEY REFERENCES chapters(id), discovered_at INTEGER NOT NULL)'); store.version = 3; store.commit(); }
        catch (error) { store.rollBack(); throw this.failure(error as Error); }
      }
      if (store.version === 3) {
        store.beginTransaction();
        try { await store.executeSql('ALTER TABLE agent_transfers ADD COLUMN expected_bytes INTEGER NOT NULL DEFAULT 0'); store.version = 4; store.commit(); }
        catch (error) { store.rollBack(); throw this.failure(error as Error); }
      }
      if (store.version === 4) {
        store.beginTransaction();
        try {
          await store.executeSql('CREATE TABLE chapter_progress (chapter_id TEXT PRIMARY KEY REFERENCES chapters(id),manga_id TEXT NOT NULL REFERENCES manga(id),page_key TEXT NOT NULL DEFAULT \'\',page_index INTEGER NOT NULL DEFAULT 0,in_page_ratio REAL NOT NULL DEFAULT 0,completed INTEGER NOT NULL DEFAULT 0,bookmarked INTEGER NOT NULL DEFAULT 0,position_at INTEGER NOT NULL DEFAULT 0,read_at INTEGER NOT NULL DEFAULT 0,bookmark_at INTEGER NOT NULL DEFAULT 0,last_read_at INTEGER NOT NULL DEFAULT 0,history_visible INTEGER NOT NULL DEFAULT 0,history_hidden_at INTEGER NOT NULL DEFAULT 0)');
          await store.executeSql('CREATE INDEX chapter_progress_manga ON chapter_progress(manga_id)');
          await store.executeSql('CREATE INDEX chapter_history_time ON chapter_progress(history_visible,last_read_at DESC)');
          await store.executeSql('INSERT INTO chapter_progress(chapter_id,manga_id,page_key,page_index,in_page_ratio,completed,position_at,read_at,last_read_at,history_visible) SELECT chapter_id,manga_id,page_key,page_index,in_page_ratio,completed,updated_at,updated_at,updated_at,1 FROM progress');
          store.version = 5; store.commit();
        } catch (error) { store.rollBack(); throw this.failure(error as Error); }
      }
      if (store.version === 5) {
        store.beginTransaction();
        try {
          await store.executeSql('ALTER TABLE downloads ADD COLUMN queue_order INTEGER NOT NULL DEFAULT 0');
          await store.executeSql('UPDATE downloads SET queue_order=updated_at');
          await store.executeSql('CREATE INDEX download_queue_order ON downloads(state,queue_order,id)');
          store.version = 6; store.commit();
        } catch (error) { store.rollBack(); throw this.failure(error as Error); }
      }
      return store;
    } catch (error) { store.close(); throw this.failure(error as Error); }
  }
  private async exclusive<T>(work: (store: relationalStore.RdbStore) => Promise<T>): Promise<T> {
    const before = this.tail; let release: () => void = () => {};
    this.tail = new Promise<void>((resolve) => { release = resolve; }); await before;
    try { return await work(await this.open()); }
    catch (error) {
      if (error instanceof AppError) { throw error; }
      throw databaseFailure(error as Error, 'read');
    } finally { release(); }
  }
  read<T>(work: (db: DbConnection) => Promise<T>): Promise<T> { return this.exclusive((store) => work(new DbConnection(store))); }
  transaction<T>(work: (db: DbConnection) => Promise<T>): Promise<T> {
    return this.exclusive(async (store) => {
      store.beginTransaction();
      try { const result = await work(new DbConnection(store)); store.commit(); return result; }
      catch (error) { store.rollBack(); throw this.failure(error as Error); }
    });
  }
  private failure(error: Error): AppError {
    return databaseFailure(error, 'transaction');
  }
}
