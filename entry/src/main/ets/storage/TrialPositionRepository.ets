import { PageRef, SourceRef } from '../model/SourceTypes';
import { ReaderDatabase } from './ReaderDatabase';
import { payloadDigest } from './PayloadDigest';

export interface TrialPosition { index: number; ratio: number; }

// Trials have no catalogue rows. Store only bounded stable keys and positions, never image URLs.
export class TrialPositionRepository {
  private readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  private async key(ref: SourceRef): Promise<string> { return 'trial.position:' + await payloadDigest(ref.sourceId + '\n' + ref.remoteId); }
  async read(ref: SourceRef,pages: PageRef[]): Promise<TrialPosition> {
    const key = await this.key(ref);
    const raw = await this.db.read(async (db) => (await db.rows('SELECT value FROM reader_settings WHERE key=?',[key],(row) => row.getString(0)))[0]);
    if (!raw || raw.length > 8192) { return { index: 0,ratio: 0 }; }
    const fields = raw.split('\t');
    if (fields.length !== 4 || !Number.isSafeInteger(Number(fields[1])) || Number(fields[1]) < 0 || !Number.isFinite(Number(fields[2])) || Number(fields[2]) < 0 || Number(fields[2]) > 1) { return { index: 0,ratio: 0 }; }
    let pageKey: string;
    try { pageKey = decodeURIComponent(fields[3]); } catch (_) { return { index: 0,ratio: 0 }; }
    const matched = pages.findIndex((page: PageRef) => page.pageKey === pageKey);
    return { index: matched >= 0 ? matched : Math.max(0,Math.min(Number(fields[1]),pages.length - 1)),ratio: matched >= 0 ? Number(fields[2]) : 0 };
  }
  async save(ref: SourceRef,pageKey: string,index: number,ratio: number,updatedAt: number): Promise<void> {
    if (pageKey.length > 2048 || !Number.isSafeInteger(index) || index < 0 || !Number.isFinite(ratio) || ratio < 0 || ratio > 1) { return; }
    const key = await this.key(ref); const value = updatedAt.toString() + '\t' + index.toString() + '\t' + ratio.toString() + '\t' + encodeURIComponent(pageKey);
    await this.db.transaction(async (db) => {
      const old = await db.rows('SELECT value FROM reader_settings WHERE key=?',[key],(row) => row.getString(0));
      if (old.length && Number(old[0].split('\t')[0]) > updatedAt) { return; }
      await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',[key,value]);
      await db.run("DELETE FROM reader_settings WHERE key LIKE 'trial.position:%' AND key NOT IN (SELECT key FROM reader_settings WHERE key LIKE 'trial.position:%' ORDER BY rowid DESC LIMIT 200)");
    });
  }
}
