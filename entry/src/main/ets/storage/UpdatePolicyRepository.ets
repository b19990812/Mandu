import { ReaderDatabase } from './ReaderDatabase';

@Observed
export class UpdatePolicy {
  hours: number = 0;
  category: string = '';
  wifiOnly: boolean = true;
  skipUnread: boolean = false;
  autoDownload: boolean = false;
}

// Separate primitive keys: no migration and no opaque serialized settings object.
export class UpdatePolicyRepository {
  private readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  async read(): Promise<UpdatePolicy> {
    const value = new UpdatePolicy();
    const rows = await this.db.read((db) => db.rows("SELECT key,value FROM reader_settings WHERE key LIKE 'updates.%'", [], (row): string[] => [row.getString(0),row.getString(1)]));
    rows.forEach((row: string[]) => {
      if (row[0] === 'updates.hours' && [0,6,12,24,48].indexOf(Number(row[1])) >= 0) { value.hours = Number(row[1]); }
      if (row[0] === 'updates.category') { value.category = row[1]; }
      if (row[0] === 'updates.wifi') { value.wifiOnly = row[1] === 'true'; }
      if (row[0] === 'updates.skipUnread') { value.skipUnread = row[1] === 'true'; }
      if (row[0] === 'updates.download') { value.autoDownload = row[1] === 'true'; }
    });
    return value;
  }
  async save(value: UpdatePolicy): Promise<void> {
    if ([0,6,12,24,48].indexOf(value.hours) < 0) { throw new Error('Invalid update interval'); }
    const rows: string[][] = [['updates.hours',value.hours.toString()],['updates.category',value.category],['updates.wifi',value.wifiOnly.toString()],['updates.skipUnread',value.skipUnread.toString()],['updates.download',value.autoDownload.toString()]];
    await this.db.transaction(async (db) => { for (let i = 0; i < rows.length; i++) { await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',rows[i]); } });
  }
  async pending(): Promise<string[]> { return this.db.read((db) => db.rows("SELECT substr(key,17) FROM reader_settings WHERE key LIKE 'updates.pending.%' ORDER BY key LIMIT 1000",[],(row) => row.getString(0))); }
  async clearPending(id: string): Promise<void> { await this.db.transaction((db) => db.run('DELETE FROM reader_settings WHERE key=?',['updates.pending.' + id])); }
  async lastAttempt(): Promise<number> {
    const rows = await this.db.read((db) => db.rows("SELECT value FROM reader_settings WHERE key='updates.lastAttempt'",[],(row) => row.getString(0)));
    return Number(rows[0]) || 0;
  }
  async stamp(): Promise<void> { await this.db.transaction((db) => db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['updates.lastAttempt',Date.now().toString()])); }
}
