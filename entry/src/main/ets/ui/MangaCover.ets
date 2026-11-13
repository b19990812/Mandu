import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { CancelScope } from '../model/CancelScope';
import { CoverService, CoverLease } from '../image/CoverService';

@Component
export struct MangaCover {
  @Prop sourceId: string;
  @Prop mangaId: string;
  @Prop address: string = '';
  @Prop title: string = '';
  @State private uri: string = '';
  private scope?: CancelScope;
  private lease?: CoverLease;
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; this.scope?.cancel(); this.lease?.release(); this.lease = undefined; }
  private async load(): Promise<void> {
    if (!this.address) { return; } const scope = new CancelScope(); this.scope = scope;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const lease = await CoverService.load(context.cacheDir,this.sourceId,this.mangaId,this.address,scope,() => new AppContainer(context).registry.open(this.sourceId));
      if (this.active && this.scope === scope && !scope.cancelled) { this.lease?.release(); this.lease = lease; this.uri = lease.asset.uri; } else { lease.release(); }
    } catch (_) { /* The title placeholder remains; an optional cover never blocks navigation. */ }
  }
  build() {
    Stack() {
      if (this.uri) { Image(this.uri).width('100%').height('100%').objectFit(ImageFit.Cover).sourceSize({ width: 256,height: 384 }) }
      else { Text(this.title.substring(0,2)).fontSize(30).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_526651')) }
    }.width('100%').aspectRatio(0.68).backgroundColor($r('app.color.theme_e4ebdf')).borderRadius(10).clip(true)
  }
}
