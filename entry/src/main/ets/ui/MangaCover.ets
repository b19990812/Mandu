import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { CancelScope } from '../model/CancelScope';
import { ChapterPageSource, ImageRequest, PageRef, PageToken, SourceBatch, SourceRef } from '../model/SourceTypes';
import { CallContext } from '../model/RequestTypes';
import { SourceHandle } from '../source/SourceRegistry';
import { UrlPolicy } from '../network/UrlPolicy';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { ReaderAssetCache } from '../image/ReaderAssetCache';

class CoverSource implements ChapterPageSource {
  readonly id: string; readonly version: number; private readonly handle: SourceHandle; private readonly address: string;
  constructor(handle: SourceHandle,address: string) { this.handle = handle; this.address = address; this.id = handle.source.id; this.version = handle.source.version; }
  pages(_chapter: SourceRef,_token: PageToken | undefined,_ctx: CallContext): Promise<SourceBatch<PageRef>> { return Promise.reject(new AppError(ErrorCode.UNSUPPORTED,'封面没有章节页清单')); }
  async resolveImage(_chapter: SourceRef,_page: PageRef,_refresh: boolean,_ctx: CallContext): Promise<ImageRequest> {
    return { url: new UrlPolicy(this.handle.rule.allowedHosts).validate(this.address).toString(),headers: this.handle.rule.definition.imageHeaders || [],contentRevision: this.handle.snapshotKey };
  }
}

@Component
export struct MangaCover {
  @Prop sourceId: string;
  @Prop mangaId: string;
  @Prop address: string = '';
  @Prop title: string = '';
  @State private uri: string = '';
  private scope?: CancelScope;
  private cache?: ReaderAssetCache;
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; this.scope?.cancel(); this.cache?.dispose(); }
  private async load(): Promise<void> {
    if (!this.address) { return; } const scope = new CancelScope(); this.scope = scope;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext; const app = new AppContainer(context);
      const handle = await app.registry.open(this.sourceId); if (!this.active) { return; }
      const cache = new ReaderAssetCache(context.cacheDir,handle.transport,4194304,2097152,handle.snapshotKey); this.cache = cache;
      const asset = await cache.load(new CoverSource(handle,this.address),{ sourceId: this.sourceId,remoteId: this.mangaId,locator: '' },
        { pageKey: 'cover',ordinal: 0,locator: this.address },{ callId: 'cover',deadlineMs: Date.now() + 30000,cancel: scope,ruleRevision: handle.source.version });
      if (this.active && !scope.cancelled) { this.uri = asset.uri; }
    } catch (_) { /* The title placeholder remains; an optional cover never blocks navigation. */ }
  }
  build() {
    Stack() {
      if (this.uri) { Image(this.uri).width('100%').height('100%').objectFit(ImageFit.Cover).sourceSize({ width: 256,height: 384 }) }
      else { Text(this.title.substring(0,2)).fontSize(30).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_526651')) }
    }.width('100%').aspectRatio(0.68).backgroundColor($r('app.color.theme_e4ebdf')).borderRadius(10).clip(true)
  }
}
