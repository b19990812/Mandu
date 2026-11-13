import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { EhentaiBrowserSession } from '../network/EhentaiBrowserSession';

@Component
export struct EhentaiBrowserHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private session?: EhentaiBrowserSession;

  aboutToDisappear(): void { this.session?.close(); this.session = undefined; }

  build() {
    Web({ src: 'about:blank',controller: this.controller,incognitoMode: false })
      .javaScriptAccess(true).imageAccess(false).domStorageAccess(false).databaseAccess(false).fileAccess(false)
      .mixedMode(MixedMode.None).multiWindowAccess(false).geolocationAccess(false)
      .onControllerAttached(() => {
        this.session?.close();
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        this.session = new EhentaiBrowserSession(this.controller,context.cacheDir);
      })
      .onPageEnd((event) => this.session?.pageLoaded(event.url))
      .onHttpErrorReceive((event) => this.session?.httpError(event.request.getRequestUrl(),event.response.getResponseCode(),event.request.isMainFrame()))
      .onErrorReceive((event) => this.session?.resourceError(event.request.getRequestUrl(),event.error.getErrorCode(),event.request.isMainFrame()))
      .onRenderExited(() => this.session?.renderExited())
      .onOverrideUrlLoading((request) => request.getRequestUrl() !== 'about:blank' && !this.session?.allowsNavigation(request.getRequestUrl()))
      .onInterceptRequest((event) => {
        const address = event.request.getRequestUrl();
        const allowed = event.request.isMainFrame() ? this.session?.allowsNavigation(address) : this.session?.allows(address);
        if (address === 'about:blank' || event.request.getRequestMethod() === 'GET' && allowed) { return null; }
        const blocked = new WebResourceResponse();
        blocked.setResponseCode(403); blocked.setReasonMessage('Blocked'); blocked.setResponseData('');
        return blocked;
      })
      .onSslErrorEventReceive((event) => { event.handler.handleCancel(); this.session?.certificateError(); })
      .width('100%').height('100%').opacity(0).hitTestBehavior(HitTestMode.None)
  }
}
