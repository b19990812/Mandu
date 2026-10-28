import { MangaDetail, SourceRef } from './SourceTypes';

export interface MangaRecord { id: string; detail: MangaDetail; favorite: boolean; updatedAt: number; unreadCount?: number; offlineCount?: number; lastReadAt?: number; }
export interface ChapterRecord {
  id: string; mangaId: string; ref: SourceRef; title: string; ordinal: number;
  active: boolean; downloaded: boolean;
  read: boolean; bookmarked: boolean; lastPage: number; lastReadAt: number;
}
export interface CategoryRecord { id: string; name: string; }
export interface ProgressRecord {
  mangaId: string; chapterId: string; pageKey: string; pageIndex: number;
  inPageRatio: number; completed: boolean; updatedAt: number;
}
export interface HistoryRecord { manga: MangaRecord; progress: ProgressRecord; chapterTitle: string; }
