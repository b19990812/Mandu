export interface DownloadTaskRecord {
  id: string; chapterId: string; sourceId: string; ruleKey: string; state: string; desiredState: string;
  manifest: string; errorCode: string; total: number; completed: number; updatedAt: number; queueOrder: number;
  mangaTitle: string; chapterTitle: string;
}
export interface DownloadedPage {
  taskId: string; pageKey: string; ordinal: number; fileKey: string; bytes: number; width: number; height: number; digest: string;
}
export interface DownloadManifest { ruleKey: string; pageKeys: string[]; }
export interface OfflineSnapshot { task: DownloadTaskRecord; manifest: DownloadManifest; pages: DownloadedPage[]; complete: boolean; }
