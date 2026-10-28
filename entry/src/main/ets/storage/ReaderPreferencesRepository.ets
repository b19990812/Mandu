import { ReaderPreferences, defaultReaderPreferences, PREFETCH_PAGE_CHOICES } from '../model/ReaderPreferences';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { ReaderDatabase } from './ReaderDatabase';
import { ReaderDisplay, READER_MODES, validDisplay } from '../model/ReaderDisplay';

// Primitive keys are a durable contract; no obfuscated object is serialized.
export class ReaderPreferencesRepository {
  private readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  async reading(mode: string,direction: string,mangaId: string = '',display?: ReaderDisplay): Promise<void> {
    if (READER_MODES.indexOf(mode) < 0 || ['ltr','rtl'].indexOf(direction) < 0 || display && !validDisplay(display)) { throw new AppError(ErrorCode.CONFIG_INVALID,'阅读设置无效'); }
    await this.db.transaction(async (db) => {
      await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['reader.mode' + (mangaId ? ':' + mangaId : ''),mode]);
      await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['reader.direction' + (mangaId ? ':' + mangaId : ''),direction]);
      if (display) {
        const rows: string[][] = [['background',display.background],['scale',display.scale],['tap.zones',display.tapZones],['tap.invert',display.invertTap.toString()]];
        for (let i = 0; i < rows.length; i++) { await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['reader.' + rows[i][0] + (mangaId ? ':' + mangaId : ''),rows[i][1]]); }
      }
    });
  }
  async read(mangaId: string = ''): Promise<ReaderPreferences> {
    const prefs = defaultReaderPreferences();
    await this.db.read(async (db) => {
      const rows = await db.rows('SELECT key,value FROM reader_settings', [], (row): string[] => [row.getString(0),row.getString(1)]);
      rows.forEach((row: string[]) => {
        if (row[0] === 'reader.mode' && READER_MODES.indexOf(row[1]) >= 0) { prefs.mode = row[1]; }
        if (row[0] === 'reader.direction' && ['ltr','rtl'].indexOf(row[1]) >= 0) { prefs.direction = row[1]; }
        if (row[0] === 'reader.prefetch') { prefs.prefetch = row[1] === 'true'; }
        if (row[0] === 'reader.auto.next') { prefs.autoNext = row[1] === 'true'; }
        if (row[0] === 'reader.preload.next') { prefs.preloadNext = row[1] === 'true'; }
        if (row[0] === 'reader.skip.read') { prefs.skipRead = row[1] === 'true'; }
        if (row[0] === 'reader.prefetch.wifi') { prefs.prefetchWifi = row[1] === 'true'; }
        if (row[0] === 'reader.incognito') { prefs.incognito = row[1] === 'true'; }
        this.displayValue(prefs,row[0],row[1]);
        if (row[0] === 'reader.prefetch.pages' && PREFETCH_PAGE_CHOICES.indexOf(Number(row[1])) >= 0) { prefs.prefetchPages = Number(row[1]); }
        if (row[0] === 'download.wifi') { prefs.wifiOnly = row[1] === 'true'; }
        if (row[0] === 'cache.mib' && [128,256,512,1024].indexOf(Number(row[1])) >= 0) { prefs.cacheMiB = Number(row[1]); }
      });
      if (mangaId) {
        const mode = rows.find((row: string[]) => row[0] === 'reader.mode:' + mangaId);
        const direction = rows.find((row: string[]) => row[0] === 'reader.direction:' + mangaId);
        if (mode && READER_MODES.indexOf(mode[1]) >= 0) { prefs.mode = mode[1]; }
        if (direction && ['ltr','rtl'].indexOf(direction[1]) >= 0) { prefs.direction = direction[1]; }
        rows.filter((row: string[]) => row[0].endsWith(':' + mangaId)).forEach((row: string[]) => this.displayValue(prefs,row[0].split(':')[0],row[1]));
      }
    });
    return prefs;
  }
  private displayValue(prefs: ReaderPreferences,key: string,value: string): void {
    if (key === 'reader.background' && ['dark','gray','light'].indexOf(value) >= 0) { prefs.background = value; }
    if (key === 'reader.scale' && ['auto','width','height'].indexOf(value) >= 0) { prefs.scale = value; }
    if (key === 'reader.tap.zones' && ['sides','thirds','menu'].indexOf(value) >= 0) { prefs.tapZones = value; }
    if (key === 'reader.tap.invert') { prefs.invertTap = value === 'true'; }
  }
  async resetReading(mangaId: string): Promise<void> { if (mangaId) { await this.db.transaction(async (db) => { const keys: string[] = ['mode','direction','background','scale','tap.zones','tap.invert']; for (let i = 0; i < keys.length; i++) { await db.run('DELETE FROM reader_settings WHERE key=?',['reader.' + keys[i] + ':' + mangaId]); } }); } }
  async save(prefs: ReaderPreferences): Promise<void> {
    if (READER_MODES.indexOf(prefs.mode) < 0 || !validDisplay(prefs) || ['ltr','rtl'].indexOf(prefs.direction) < 0 || [128,256,512,1024].indexOf(prefs.cacheMiB) < 0 || PREFETCH_PAGE_CHOICES.indexOf(prefs.prefetchPages) < 0) { throw new AppError(ErrorCode.CONFIG_INVALID, '阅读设置无效'); }
    await this.db.transaction(async (db) => {
      const rows: string[][] = [['reader.mode',prefs.mode],['reader.direction',prefs.direction],['reader.prefetch',prefs.prefetch.toString()],['reader.prefetch.pages',prefs.prefetchPages.toString()],['download.wifi',prefs.wifiOnly.toString()],['cache.mib',prefs.cacheMiB.toString()],['reader.auto.next',prefs.autoNext.toString()],['reader.preload.next',prefs.preloadNext.toString()],['reader.skip.read',prefs.skipRead.toString()],['reader.prefetch.wifi',prefs.prefetchWifi.toString()]];
      rows.push(['reader.background',prefs.background],['reader.scale',prefs.scale],['reader.tap.zones',prefs.tapZones],['reader.tap.invert',prefs.invertTap.toString()],['reader.incognito',prefs.incognito.toString()]);
      for (let i = 0; i < rows.length; i++) { await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)', rows[i]); }
    });
  }
}
