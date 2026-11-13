import { webview } from '@kit.ArkWeb';
import { BuilderNode, FrameNode, NodeController, UIContext } from '@kit.ArkUI';
import { MyComicBrowserSession } from '../network/MyComicBrowserSession';
import { MYCOMIC_USER_AGENT } from '../source/MyComicAccess';
import { UrlPolicy } from '../network/UrlPolicy';

class MyComicWebData {
  controller: webview.WebviewController = new webview.WebviewController();
  policy: UrlPolicy = new UrlPolicy([]);
  ready: boolean = false;
  pending: string = '';
  page?: (address: string) => void;
  failure?: (message: string) => void;
  allowed(address: string): boolean { if (address === 'about:blank') { return true; } try { this.policy.validate(address); return true; } catch (_) { return false; } }
  attached(): void {
    this.controller.setCustomUserAgent(MYCOMIC_USER_AGENT); this.ready = true;
    MyComicBrowserSession.attachHost(this.controller);
    if (this.pending) { this.controller.loadUrl(this.pending); this.pending = ''; }
  }
}

@Builder
function myComicWebBuilder(data: MyComicWebData) {
  Column() {
    Web({ src: 'about:blank',controller: data.controller,incognitoMode: false })
      .javaScriptAccess(true).domStorageAccess(true).databaseAccess(false).fileAccess(false)
      .mixedMode(MixedMode.None).multiWindowAccess(false).geolocationAccess(false)
      .onControllerAttached(() => data.attached())
      .onPageBegin((event) => { if (data.allowed(event.url) && event.url !== 'about:blank') { data.page?.(event.url); } })
      .onOverrideUrlLoading((request) => !data.allowed(request.getRequestUrl()))
      .onInterceptRequest((event) => {
        if (data.allowed(event.request.getRequestUrl())) { return null; }
        const response = new WebResourceResponse(); response.setResponseCode(403); response.setReasonMessage('Blocked'); response.setResponseData(''); return response;
      })
      .onSslErrorEventReceive((event) => { event.handler.handleCancel(); data.failure?.('证书验证失败，连接已取消'); })
      .width('100%').height('100%')
  }.width('100%').height('100%')
}

class MyComicWebNode extends NodeController {
  private root?: BuilderNode<MyComicWebData[]>;
  initialize(context: UIContext,data: MyComicWebData): void {
    if (this.root) { return; }
    this.root = new BuilderNode<MyComicWebData[]>(context);
    this.root.build(wrapBuilder<MyComicWebData[]>(myComicWebBuilder),data);
  }
  makeNode(_context: UIContext): FrameNode | null { return this.root?.getFrameNode() || null; }
  close(): void { this.root?.dispose(); this.root = undefined; }
}

// The BuilderNode owns one Web for the whole HomePage lifetime. Closing the
// website only unmounts its NodeContainer; metadata keeps the verified Web alive.
export class MyComicBrowserView {
  private static data: MyComicWebData = new MyComicWebData();
  private static container: MyComicWebNode = new MyComicWebNode();
  static initialize(context: UIContext): void { MyComicBrowserView.container.initialize(context,MyComicBrowserView.data); }
  static controller(): webview.WebviewController { return MyComicBrowserView.data.controller; }
  static node(): NodeController { return MyComicBrowserView.container; }
  static open(context: UIContext,home: string,policy: UrlPolicy,page: (address: string) => void,failure: (message: string) => void): void {
    const data = MyComicBrowserView.data; data.policy = policy; data.page = page; data.failure = failure;
    MyComicBrowserView.initialize(context);
    if (!data.ready) { data.pending = home; return; }
    data.controller.onActive();
    data.controller.loadUrl(home);
  }
  static detach(): void { MyComicBrowserView.data.page = undefined; MyComicBrowserView.data.failure = undefined; }
  static close(): void {
    MyComicBrowserView.detach(); MyComicBrowserView.container.close(); MyComicBrowserSession.close();
    MyComicBrowserView.data = new MyComicWebData(); MyComicBrowserView.container = new MyComicWebNode();
  }
}

@Component
export struct MyComicBrowserHost {
  aboutToAppear(): void { MyComicBrowserView.initialize(this.getUIContext()); }
  aboutToDisappear(): void { MyComicBrowserView.close(); }
  build() { Blank().width(0).height(0) }
}
