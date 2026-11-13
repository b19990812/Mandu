import { CallContext, HeaderPair } from './RequestTypes';

export interface SourceRef { sourceId: string; remoteId: string; locator: string; }
export interface PageToken { kind: string; value: string; binding: string; }
export interface SourceBatch<T> { items: T[]; next?: PageToken; label?: string; }
export interface MangaSummary { ref: SourceRef; title: string; cover?: string; }
export interface MangaDetail {
  ref: SourceRef; title: string; authors: string[]; description: string;
  tags: string[]; cover?: string; status: string;
}
export interface ChapterRef {
  ref: SourceRef; mangaRemoteId: string; title: string; ordinal: number;
}
export interface PageRef {
  pageKey: string; ordinal: number; locator: string; imageUrl?: string; width?: number; height?: number;
}
export interface ImageRequest { url: string; headers: HeaderPair[]; contentRevision: string; encoding?: string; }
export interface SourceFeed { id: string; title: string; }
export interface SourceFilterChoice { value: string; title: string; }
export interface SourceFilter { id: string; title: string; choices: SourceFilterChoice[]; }
export interface SourceFilterValue { id: string; value: string; }
export interface SourceBrowseQuery { feed: string; filters: SourceFilterValue[]; }
export interface SourceBrowseItem { manga: MangaSummary; subtitle: string; }
export interface SourceBrowseBatch { items: SourceBrowseItem[]; filters: SourceFilter[]; next?: PageToken; }
// Optional source capability. Existing imported search-only rules remain compatible.
export interface SourceDiscovery {
  readonly feeds: SourceFeed[];
  browse(query: SourceBrowseQuery, token: PageToken | undefined, ctx: CallContext): Promise<SourceBrowseBatch>;
}
export interface SourceCatalogSnapshot { detail: MangaDetail; chapters: ChapterRef[]; }
// Optional combined load: sources whose details and catalog share a response.
export interface SourceCatalog {
  loadCatalog(manga: SourceRef,ctx: CallContext): Promise<SourceCatalogSnapshot>;
}
export interface ChapterPageSource {
  id: string;
  version: number;
  pages(chapter: SourceRef, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<PageRef>>;
  resolveImage(chapter: SourceRef, page: PageRef, forceRefresh: boolean, ctx: CallContext): Promise<ImageRequest>;
}
export interface Source extends ChapterPageSource {
  discovery?: SourceDiscovery;
  catalog?: SourceCatalog;
  search(query: string, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<MangaSummary>>;
  details(manga: SourceRef, ctx: CallContext): Promise<MangaDetail>;
  chapters(manga: SourceRef, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<ChapterRef>>;
}
