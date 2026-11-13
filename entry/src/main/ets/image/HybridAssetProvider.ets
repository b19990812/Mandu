import { CallContext } from '../model/RequestTypes';
import { ChapterPageSource, PageRef, SourceRef } from '../model/SourceTypes';
import { ReaderAsset } from './ReaderAssetCache';
import { AssetProvider } from './AssetProvider';

export class HybridAssetProvider implements AssetProvider {
  private readonly offline: AssetProvider;
  private readonly online: AssetProvider;
  private readonly available: Set<string>;
  constructor(offline: AssetProvider, online: AssetProvider, pageKeys: string[]) { this.offline = offline; this.online = online; this.available = new Set(pageKeys); }
  load(source: ChapterPageSource | undefined, chapter: SourceRef, page: PageRef, ctx: CallContext): Promise<ReaderAsset> {
    return (this.available.has(page.pageKey) ? this.offline : this.online).load(source, chapter, page, ctx);
  }
  forget(index: number): void { this.online.forget(index); this.offline.forget(index); }
  dispose(): void { this.offline.dispose(); this.online.dispose(); }
  park(): void { this.offline.park(); this.online.park(); }
  prioritize(index: number): void { this.online.prioritize?.(index); }
}
