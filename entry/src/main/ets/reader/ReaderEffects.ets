import { common } from '@kit.AbilityKit';
import { ReaderDatabase } from '../storage/ReaderDatabase';
@Observed
export class ReaderEffects {
  filter: string = 'none'; brightness: number = -1; orientation: string = 'system';
  async read(context: common.Context): Promise<void> {
    const rows = await ReaderDatabase.shared(context).read((db) => db.rows("SELECT key,value FROM reader_settings WHERE key LIKE 'reader.effect.%'",[],(row): string[] => [row.getString(0),row.getString(1)]));
    rows.forEach((row: string[]) => {
      if (row[0] === 'reader.effect.filter' && ['none','gray','invert','sepia'].indexOf(row[1]) >= 0) { this.filter = row[1]; }
      if (row[0] === 'reader.effect.orientation' && ['system','portrait','landscape'].indexOf(row[1]) >= 0) { this.orientation = row[1]; }
      const number = Number(row[1]); if (row[0] === 'reader.effect.brightness' && (number === -1 || number >= 0.05 && number <= 1)) { this.brightness = number; }
    });
  }
  async save(context: common.Context): Promise<void> {
    const rows: string[][] = [['reader.effect.filter',this.filter],['reader.effect.brightness',this.brightness.toString()],['reader.effect.orientation',this.orientation]];
    await ReaderDatabase.shared(context).transaction(async (db) => { for (let i = 0; i < rows.length; i++) { await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',rows[i]); } });
  }
}
