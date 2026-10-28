import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ReaderDatabase } from '../storage/ReaderDatabase';
export class AppTheme {
  static async read(context: common.Context): Promise<string> {
    const rows = await ReaderDatabase.shared(context).read((db) => db.rows("SELECT value FROM reader_settings WHERE key='app.theme'",[],(row) => row.getString(0)));
    return ['light','dark','system'].indexOf(rows[0]) >= 0 ? rows[0] : 'system';
  }
  static apply(context: common.Context,value: string): void {
    context.getApplicationContext().setColorMode(value === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : value === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }
  static async save(context: common.Context,value: string): Promise<void> {
    if (['light','dark','system'].indexOf(value) < 0) { return; }
    await ReaderDatabase.shared(context).transaction((db) => db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['app.theme',value]));
    AppTheme.apply(context,value);
  }
}
