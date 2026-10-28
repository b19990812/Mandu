import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { AppError, ErrorCode } from '../model/ErrorTypes';

export interface ProbeRecord { value: string; updatedAt: number; }

// Dedicated P0 table, not the production schema or migration implementation.
export class Database {
  private store?: relationalStore.RdbStore;
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) { this.context = context; }

  private async open(): Promise<relationalStore.RdbStore> {
    if (this.store) { return this.store; }
    const store = await relationalStore.getRdbStore(this.context, {
      name: 'foundation_probe.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    if (store.version > 1) {
      store.close();
      throw new AppError(ErrorCode.DATABASE_VERSION, '数据库版本较新，已拒绝写入');
    }
    await store.executeSql('CREATE TABLE IF NOT EXISTS probe (id INTEGER PRIMARY KEY CHECK (id = 1), value TEXT NOT NULL, updated_at INTEGER NOT NULL)');
    store.version = 1;
    this.store = store;
    return store;
  }

  async writeProbe(record: ProbeRecord): Promise<void> {
    const store = await this.open();
    store.beginTransaction();
    try {
      await store.executeSql('INSERT OR REPLACE INTO probe (id, value, updated_at) VALUES (1, ?, ?)',
        [record.value, record.updatedAt]);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new AppError(ErrorCode.IO_ERROR, '探针事务写入失败，已尝试回滚');
    }
  }

  async readProbe(): Promise<ProbeRecord | undefined> {
    const store = await this.open();
    const result = await store.querySql('SELECT value, updated_at FROM probe WHERE id = ?', [1]);
    try {
      if (!result.goToFirstRow()) { return undefined; }
      return { value: result.getString(0), updatedAt: result.getLong(1) };
    } finally { result.close(); }
  }

  close(): void {
    if (this.store) { this.store.close(); this.store = undefined; }
  }
}
