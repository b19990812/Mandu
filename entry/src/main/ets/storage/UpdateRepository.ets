import { ReaderDatabase } from './ReaderDatabase';
export interface ChapterUpdate { chapterId: string; mangaId: string; title: string; chapter: string; discoveredAt: number; }
export class UpdateRepository {
  private readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  async list(): Promise<ChapterUpdate[]> { return this.db.read((db) => db.rows('SELECT c.id,m.id,m.title,c.title,u.discovered_at FROM chapter_updates u JOIN chapters c ON c.id=u.chapter_id JOIN manga m ON m.id=c.manga_id WHERE m.favorite=1 AND c.active=1 ORDER BY u.discovered_at DESC,c.ordinal DESC LIMIT 500',[],(row): ChapterUpdate => ({ chapterId: row.getString(0),mangaId: row.getString(1),title: row.getString(2),chapter: row.getString(3),discoveredAt: row.getLong(4) }))); }
}
