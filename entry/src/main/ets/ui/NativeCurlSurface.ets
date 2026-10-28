import { CurlGpuBridge } from '../reader/CurlGpuBridge';

@Component
export struct NativeCurlSurface {
  controller: CurlGpuBridge = new CurlGpuBridge();
  onReady: () => void = () => {};
  build() {
    XComponent({ id: this.controller.id,type: XComponentType.TEXTURE,libraryname: 'pagecurl' })
      .width('100%').height('100%').backgroundColor(Color.Transparent).hitTestBehavior(HitTestMode.None)
      .onLoad(() => { this.controller.attach(); this.onReady(); })
      .onDestroy(() => this.controller.detach())
  }
}
