import { CallContext } from '../model/RequestTypes';
import { ChapterPageSource, PageRef, SourceRef } from '../model/SourceTypes';
import { ReaderAsset } from './ReaderAssetCache';

export interface AssetProvider {
  load(source: ChapterPageSource | undefined, chapter: SourceRef, page: PageRef, ctx: CallContext): Promise<ReaderAsset>;
  forget(index: number): void;
  dispose(): void;
  park(): void;
  prioritize?(index: number): void;
}
