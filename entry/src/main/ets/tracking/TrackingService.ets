import { ReaderDatabase } from '../storage/ReaderDatabase';
import { SecretStore } from '../storage/SecretStore';
import { BangumiClient } from './BangumiClient';
import { AppError, ErrorCode } from '../model/ErrorTypes';
export interface TrackingAccount { id: string; name: string; }
export class TrackingService {
  private readonly db: ReaderDatabase;
  private static running: boolean = false;
  constructor(db: ReaderDatabase) { this.db = db; }
  async account(): Promise<TrackingAccount> {
    const rows = await this.db.read((db) => db.rows("SELECT key,value FROM reader_settings WHERE key IN('tracking.bgm.id','tracking.bgm.name')",[],(row): string[] => [row.getString(0),row.getString(1)]));
    return { id: rows.find((row: string[]) => row[0] === 'tracking.bgm.id')?.[1] || '',name: rows.find((row: string[]) => row[0] === 'tracking.bgm.name')?.[1] || '' };
  }
  async login(token: string): Promise<void> {
    if (!token.trim() || token.length > 900) { throw new AppError(ErrorCode.CONFIG_INVALID,'请输入有效的个人访问令牌'); }
    const me = await new BangumiClient().request('/v0/me',token.trim());
    const id = me.members.get('id')?.scalar || ''; const name = me.members.get('nickname')?.scalar || me.members.get('username')?.scalar || id;
    if (!/^[1-9][0-9]*$/.test(id)) { throw new AppError(ErrorCode.PARSE_ERROR,'账号身份无效'); }
    const old = await this.account();
    await SecretStore.save('tracking.bgm.' + id,token.trim());
    await this.db.transaction(async (db) => { await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['tracking.bgm.id',id]); await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['tracking.bgm.name',name]); });
    if (old.id && old.id !== id) { await SecretStore.remove('tracking.bgm.' + old.id); }
  }
  async logout(): Promise<void> { const account = await this.account(); if (account.id) { await SecretStore.remove('tracking.bgm.' + account.id); } await this.db.transaction((db) => db.run("DELETE FROM reader_settings WHERE key IN('tracking.bgm.id','tracking.bgm.name')")); }
  async subject(id: string): Promise<string> {
    if (!/^[1-9][0-9]{0,9}$/.test(id)) { throw new AppError(ErrorCode.CONFIG_INVALID,'请输入 Bangumi 书籍条目数字 ID'); }
    const account = await this.account(); const token = account.id ? await SecretStore.read('tracking.bgm.' + account.id) : '';
    const subject = await new BangumiClient().request('/v0/subjects/' + id,token);
    if (subject.members.get('type')?.scalar !== '1') { throw new AppError(ErrorCode.CONFIG_INVALID,'只允许绑定书籍条目'); }
    return subject.members.get('name_cn')?.scalar || subject.members.get('name')?.scalar || id;
  }
  async binding(manga: string): Promise<string> {
    const account = await this.account(); const rows = await this.db.read((db) => db.rows('SELECT value FROM reader_settings WHERE key=?',['tracking.bind.' + account.id + '.' + manga],(row) => row.getString(0))); return rows[0] || '';
  }
  async queue(manga: string,subject: string,chapters: number,status: number,score: number): Promise<void> {
    const account = await this.account();
    if (!account.id || !/^[a-f0-9]{64}$/.test(manga) || !/^[1-9][0-9]{0,9}$/.test(subject) || !Number.isSafeInteger(chapters) || chapters < 0 || chapters > 100000 || [1,2,3,4,5].indexOf(status) < 0 || !Number.isInteger(score) || score < 0 || score > 10) { throw new AppError(ErrorCode.CONFIG_INVALID,'账号或同步数值无效'); }
    const values: number[] = [Number(subject),chapters,status,score];
    await this.db.transaction(async (db) => {
      await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['tracking.bind.' + account.id + '.' + manga,subject]);
      await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['tracking.pending.' + account.id + '.' + manga,JSON.stringify(values)]);
    });
  }
  async pending(): Promise<number> { const account = await this.account(); return this.db.read(async (db) => (await db.rows('SELECT COUNT(*) FROM reader_settings WHERE key LIKE ?',['tracking.pending.' + account.id + '.%'],(row) => row.getLong(0)))[0]); }
  async flush(): Promise<number> {
    if (TrackingService.running) { return 0; } TrackingService.running = true;
    try {
      const account = await this.account(); if (!account.id) { return 0; }
      const token = await SecretStore.read('tracking.bgm.' + account.id); if (!token) { return 0; }
      const rows = await this.db.read((db) => db.rows('SELECT key,value FROM reader_settings WHERE key LIKE ? ORDER BY key LIMIT 20',['tracking.pending.' + account.id + '.%'],(row): string[] => [row.getString(0),row.getString(1)]));
      let completed = 0;
      for (let i = 0; i < rows.length; i++) {
        if ((await this.account()).id !== account.id) { break; }
        const values = JSON.parse(rows[i][1]) as number[];
        if (!Array.isArray(values) || values.length !== 4 || values.some((n: number) => !Number.isSafeInteger(n) || n < 0)) { throw new AppError(ErrorCode.CORRUPT_FILE,'待同步记录无效'); }
        const body = '{"ep_status":' + values[1].toString() + ',"type":' + values[2].toString() + ',"rate":' + values[3].toString() + '}';
        await new BangumiClient().request('/v0/users/-/collections/' + values[0].toString(),token,body);
        await this.db.transaction((db) => db.run('DELETE FROM reader_settings WHERE key=? AND value=?',rows[i])); completed++;
        if (i + 1 < rows.length) { await new Promise<void>((resolve) => setTimeout(resolve,1000)); }
      }
      return completed;
    } finally { TrackingService.running = false; }
  }
}
