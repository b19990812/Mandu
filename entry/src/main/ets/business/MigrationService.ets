import { CatalogRepository } from '../storage/CatalogRepository';
import { ChapterRecord } from '../model/LibraryTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';

export interface ChapterMatch { from: string; to: string; title: string; }
export interface MigrationPreview { from: string; to: string; sourceTitle: string; targetTitle: string; fingerprint: string; matches: ChapterMatch[]; unmatched: number; }
export class MigrationService {
  private readonly catalog: CatalogRepository;
  constructor(catalog: CatalogRepository) { this.catalog = catalog; }
  private signature(a: ChapterRecord[],b: ChapterRecord[]): string { return JSON.stringify([a.map((c: ChapterRecord) => [c.id,c.title,c.active.toString()]),b.map((c: ChapterRecord) => [c.id,c.title,c.active.toString()])]); }
  private title(value: string): string { return value.trim().replace(/\s+/g,' ').toLowerCase(); }
  async preview(from: string,to: string): Promise<MigrationPreview> {
    const source = await this.catalog.manga(from); const target = await this.catalog.manga(to);
    if (!source || !target || from === to || source.detail.ref.sourceId === target.detail.ref.sourceId) { throw new AppError(ErrorCode.CONFIG_INVALID,'请选择不同来源的目标作品'); }
    const a = (await this.catalog.chapters(from)).filter((c: ChapterRecord) => c.active);
    const b = (await this.catalog.chapters(to)).filter((c: ChapterRecord) => c.active);
    if (!a.length || !b.length) { throw new AppError(ErrorCode.CONFIG_INVALID,'请先获取原作品和目标作品的完整目录'); }
    const matches: ChapterMatch[] = [];
    a.forEach((chapter: ChapterRecord) => {
      const key = this.title(chapter.title);
      const same = b.filter((other: ChapterRecord) => this.title(other.title) === key);
      if (key && same.length === 1 && a.filter((other: ChapterRecord) => this.title(other.title) === key).length === 1) { matches.push({ from: chapter.id,to: same[0].id,title: chapter.title }); }
    });
    return { from: from,to: to,sourceTitle: source.detail.title,targetTitle: target.detail.title,fingerprint: this.signature(a,b),matches: matches,unmatched: a.length - matches.length };
  }
  async apply(preview: MigrationPreview): Promise<void> {
    const checked = await this.preview(preview.from,preview.to);
    if (checked.fingerprint !== preview.fingerprint || JSON.stringify(checked.matches) !== JSON.stringify(preview.matches)) { throw new AppError(ErrorCode.CONFLICT,'目录已变化，请重新预览迁移'); }
    await this.catalog.db.transaction(async (db) => {
      const rows = await db.rows('SELECT id,title FROM chapters WHERE manga_id=? AND active=1 ORDER BY ordinal,id',[preview.from],(row): string[] => [row.getString(0),row.getString(1)]);
      const targets = await db.rows('SELECT id,title FROM chapters WHERE manga_id=? AND active=1 ORDER BY ordinal,id',[preview.to],(row): string[] => [row.getString(0),row.getString(1)]);
      const expected = await Promise.resolve(checked.fingerprint);
      const actual = JSON.stringify([rows.map((row: string[]) => [row[0],row[1],'true']),targets.map((row: string[]) => [row[0],row[1],'true'])]);
      if (actual !== expected) { throw new AppError(ErrorCode.CONFLICT,'目录已变化，迁移已取消'); }
      await db.run('UPDATE manga SET favorite=1 WHERE id=?',[preview.to]);
      await db.run('INSERT OR IGNORE INTO manga_categories(manga_id,category_id) SELECT ?,category_id FROM manga_categories WHERE manga_id=?',[preview.to,preview.from]);
      for (let i = 0; i < checked.matches.length; i++) {
        const match = checked.matches[i];
        // Different image lists cannot share page keys, offsets or downloaded file pointers.
        await db.run('INSERT INTO chapter_progress(chapter_id,manga_id,completed,read_at,bookmarked,bookmark_at) SELECT ?,?,completed,read_at,bookmarked,bookmark_at FROM chapter_progress WHERE chapter_id=? ON CONFLICT(chapter_id) DO UPDATE SET completed=CASE WHEN excluded.read_at>chapter_progress.read_at THEN excluded.completed ELSE chapter_progress.completed END,read_at=MAX(chapter_progress.read_at,excluded.read_at),bookmarked=CASE WHEN excluded.bookmark_at>chapter_progress.bookmark_at THEN excluded.bookmarked ELSE chapter_progress.bookmarked END,bookmark_at=MAX(chapter_progress.bookmark_at,excluded.bookmark_at)',[match.to,preview.to,match.from]);
      }
      const latest = await db.rows('SELECT chapter_id,updated_at FROM progress WHERE manga_id=?',[preview.from],(row): string[] => [row.getString(0),row.getLong(1).toString()]);
      const match = latest.length ? checked.matches.find((item: ChapterMatch) => item.from === latest[0][0]) : undefined;
      if (match) { await db.run("INSERT OR IGNORE INTO progress(manga_id,chapter_id,page_key,page_index,in_page_ratio,completed,updated_at) SELECT ?,?,'',0,0,COALESCE(completed,0),? FROM chapter_progress WHERE chapter_id=?",[preview.to,match.to,Number(latest[0][1]),match.to]); }
    });
  }
}
