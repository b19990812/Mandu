import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CategoryRecord } from '../model/LibraryTypes';
import { ReaderDatabase } from './ReaderDatabase';

export class LibraryRepository {
  private readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  async categories(): Promise<CategoryRecord[]> {
    return this.db.read((db) => db.rows('SELECT id,name FROM categories ORDER BY name,id', [], (row): CategoryRecord => ({ id: row.getString(0), name: row.getString(1) })));
  }
  private name(value: string): string {
    const name = value.trim(); if (!name || name.length > 32 || /[\u0000-\u001f\u007f]/.test(name)) { throw new AppError(ErrorCode.CONFIG_INVALID, '分类名需为1～32个可见字符'); } return name;
  }
  async addCategory(value: string): Promise<void> {
    const name = this.name(value);
    await this.db.transaction(async (db) => {
      const existing = await db.rows('SELECT id FROM categories WHERE name=?', [name], (row) => row.getString(0));
      if (existing.length) { throw new AppError(ErrorCode.CONFLICT, '已有同名分类'); }
      await db.run('INSERT INTO categories(id,name) VALUES(?,?)', [util.generateRandomUUID(), name]);
    });
  }
  async renameCategory(id: string, value: string): Promise<void> {
    const name = this.name(value);
    await this.db.transaction(async (db) => {
      const existing = await db.rows('SELECT id FROM categories WHERE name=? AND id<>?', [name, id], (row) => row.getString(0));
      if (existing.length) { throw new AppError(ErrorCode.CONFLICT, '已有同名分类'); }
      await db.run('UPDATE categories SET name=? WHERE id=?', [name, id]);
    });
  }
  async deleteCategory(id: string): Promise<void> { await this.db.transaction((db) => db.run('DELETE FROM categories WHERE id=?', [id])); }
  async categoryIds(mangaId: string): Promise<string[]> {
    return this.db.read((db) => db.rows('SELECT category_id FROM manga_categories WHERE manga_id=?', [mangaId], (row) => row.getString(0)));
  }
  async assign(mangaId: string, categoryId: string, selected: boolean): Promise<void> {
    await this.db.transaction((db) => db.run(selected ? 'INSERT OR IGNORE INTO manga_categories(manga_id,category_id) VALUES(?,?)' : 'DELETE FROM manga_categories WHERE manga_id=? AND category_id=?', [mangaId, categoryId]));
  }
  async assignMany(ids: string[], categoryId: string, selected: boolean): Promise<void> {
    if (ids.length > 10000 || !categoryId) { throw new AppError(ErrorCode.CONFIG_INVALID,'批量分类参数无效'); }
    await this.db.transaction(async (db) => {
      const exists = await db.rows('SELECT id FROM categories WHERE id=?',[categoryId],(row) => row.getString(0));
      if (!exists.length) { throw new AppError(ErrorCode.NOT_FOUND,'分类不存在'); }
      for (let i = 0; i < ids.length; i++) { await db.run(selected ? 'INSERT OR IGNORE INTO manga_categories(manga_id,category_id) VALUES(?,?)' : 'DELETE FROM manga_categories WHERE manga_id=? AND category_id=?',[ids[i],categoryId]); }
    });
  }
}
