import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { url } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContainer } from '../app/AppContainer';
import { UrlPolicy } from '../network/UrlPolicy';
import { SiteSession } from '../network/SiteSession';
import { viewError } from '../vm/ViewOperation';
import { SourceHandle } from '../source/SourceRegistry';
import { CancelScope } from '../model/CancelScope';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { SourceBrowseQuery } from '../model/SourceTypes';
import { CallContext } from '../model/RequestTypes';
import { MyComicBrowserSession } from '../network/MyComicBrowserSession';
import { MyComicBrowserView } from '../ui/MyComicBrowserHost';
import { EHENTAI_BASE, EHENTAI_ID, ehentaiAddress } from '../network/EhentaiAccess';
interface SourceWebParams { sourceId: string; }
@Entry
@Component
struct SourceWebPage {
  @State private address: string = '';
  @State private homeAddress: string = '';
  @State private status: string = '正在读取来源…';
  @State private saving: boolean = false;
  @State private owned: boolean = false;
  private source: string = ''; private policy?: UrlPolicy; private closed: boolean = false;
  private handle?: SourceHandle; private saveScope?: CancelScope;
  private controller: webview.WebviewController = new webview.WebviewController();
  private privateWeb(): boolean { return this.source !== 'org.hsmihon.mycomic' && this.source !== EHENTAI_ID; }
  async aboutToAppear(): Promise<void> {
    try {
      this.source = (this.getUIContext().getRouter().getParams() as SourceWebParams).sourceId;
      const handle = await new AppContainer(this.getUIContext().getHostContext() as common.UIAbilityContext).registry.open(this.source);
      if (this.closed) { return; }
      this.policy = new UrlPolicy(handle.rule.allowedHosts); this.policy.validate(handle.rule.baseUrl);
      if (!SiteSession.acquire(this.source)) { this.status = '请先关闭另一个网站会话'; return; }
      this.owned = true;
      if (this.privateWeb()) { webview.WebCookieManager.clearAllCookiesSync(true); }
      this.handle = handle;
      this.homeAddress = handle.rule.baseUrl; this.address = this.homeAddress;
      this.status = this.source === 'org.hsmihon.mycomic' ? '网站会话会保留；完成网站验证后可返回加载。' : '独立临时浏览；保存会话后仅当前源、当前网址使用，有效期最多24小时。';
      if (this.source === EHENTAI_ID) { this.status = '阅读器会使用这里的浏览器登录状态。可另存会话供原生目录请求使用；退出浏览器登录请在网站操作。'; }
      if (this.source === 'org.hsmihon.mycomic') {
        this.controller = MyComicBrowserView.controller();
        MyComicBrowserView.open(this.getUIContext(),this.verificationAddress(),this.policy,
          (address: string) => { if (!this.closed) { this.address = address; } },
          (message: string) => { if (!this.closed) { this.status = message; } });
        MyComicBrowserSession.attachVisible(this.controller);
      }
    } catch (error) { this.status = viewError(error as Error); }
  }
  aboutToDisappear(): void {
    this.closed = true; this.saveScope?.cancel(); MyComicBrowserSession.detachVisible(this.controller);
    if (this.source === 'org.hsmihon.mycomic') { MyComicBrowserView.detach(); }
    if (this.owned) { if (this.privateWeb()) { webview.WebCookieManager.clearAllCookiesSync(true); } SiteSession.release(this.source); this.owned = false; }
  }
  private allowed(address: string): boolean { try { if (!this.policy) { return false; } const parsed = new url.URL(address); parsed.hash = ''; this.policy.validate(parsed.toString()); return true; } catch (_) { return false; } }
  private allowedResource(request: WebResourceRequest): boolean {
    const address = request.getRequestUrl();
    if (this.allowed(address)) { return true; }
    if (this.source !== EHENTAI_ID || request.isMainFrame() || request.getRequestMethod() !== 'GET') { return false; }
    try { ehentaiAddress(address,true); return true; } catch (_) { return false; }
  }
  private home(): void { if (this.homeAddress) { this.controller.loadUrl(this.homeAddress); this.address = this.homeAddress; } }
  private verificationAddress(): string { return new url.URL('/cn/comics?sort=-id',this.homeAddress).toString(); }
  private async save(): Promise<void> {
    if (this.saving || !this.owned || this.closed) { return; }
    this.saving = true; let clearance = false;
    try {
      if (this.source === 'org.hsmihon.mycomic' && new url.URL(this.address).origin !== new url.URL(this.homeAddress).origin) {
        throw new AppError(ErrorCode.CONFIG_INVALID,'验证网站与漫画源根网址不一致，请先将该源网址改为当前网站根网址再验证');
      }
      if (this.source === EHENTAI_ID && new url.URL(this.address).origin + '/' !== EHENTAI_BASE) {
        throw new AppError(ErrorCode.CONFIG_INVALID,'请完成登录并回到 E-Hentai 首页，再保存原生目录会话');
      }
      const privateMode = this.privateWeb();
      const cookie = this.source === 'org.hsmihon.mycomic' && deviceInfo.sdkApiVersion >= 26 ?
        webview.WebCookieManager.fetchCookieSync(this.address,false,true) : webview.WebCookieManager.fetchCookieSync(this.address,privateMode);
      clearance = /(?:^|;\s*)cf_clearance=[^;\s]+/.test(cookie);
      if (cookie) { await SiteSession.save(this.source,this.address,cookie); }
      else if (this.source !== 'org.hsmihon.mycomic') { throw new AppError(ErrorCode.CONFIG_INVALID,'没有可保存的站点 Cookie'); }
      if (!privateMode) { await webview.WebCookieManager.saveCookieAsync(); }
      if (this.closed) { return; }
      if (this.source !== 'org.hsmihon.mycomic') { this.status = '会话已加密保存；返回来源后可重试加载'; return; }
      const handle = this.handle;
      if (!handle?.source.discovery) { throw new AppError(ErrorCode.CONFIG_INVALID,'来源已关闭，请重新打开网站验证'); }
      const scope = new CancelScope(); this.saveScope = scope;
      this.status = '会话已保存，正在确认漫画源能否正常读取…';
      const query: SourceBrowseQuery = { feed: 'latest',filters: [] };
      const ctx: CallContext = { callId: 'mycomic-session-probe',deadlineMs: Date.now() + 30000,cancel: scope,ruleRevision: handle.source.version };
      await handle.source.discovery.browse(query,undefined,ctx);
      if (!this.closed) { this.status = '会话已验证，漫画源读取正常；返回后可刷新加载'; }
      hilog.info(0x0001,'HSReader','MYCOMIC_SESSION_PROBE result=OK clearance=%{public}d sdk=%{public}d',clearance ? 1 : 0,deviceInfo.sdkApiVersion);
    }
    catch (error) {
      if (this.closed) { return; }
      const failure = error as Error;
      if (this.source === 'org.hsmihon.mycomic' && failure instanceof AppError &&
        [ErrorCode.AUTH_REQUIRED,ErrorCode.ACCESS_DENIED].indexOf(failure.code) >= 0) {
        const hint = failure.code === ErrorCode.AUTH_REQUIRED ? '当前列表仍要求验证，请在当前页面完成后重新保存' : '网站仍拒绝当前访问，请稍后再试';
        this.status = hint + '；' + failure.code + '：' + failure.message;
        if (failure.code === ErrorCode.AUTH_REQUIRED) { this.controller.loadUrl(this.verificationAddress()); }
        hilog.warn(0x0001,'HSReader','MYCOMIC_SESSION_PROBE result=%{public}s clearance=%{public}d sdk=%{public}d',failure.code,clearance ? 1 : 0,deviceInfo.sdkApiVersion);
      } else { this.status = viewError(failure); }
    } finally { this.saving = false; this.saveScope = undefined; }
  }
  private async clear(): Promise<void> {
    if (this.source === EHENTAI_ID) {
      try {
        await SiteSession.clear(this.source,EHENTAI_BASE);
        this.status = '已清除原生目录的保存会话；退出浏览器登录请在网站操作';
      } catch (error) { this.status = viewError(error as Error); }
      return;
    }
    try { await SiteSession.clear(this.source,this.address); webview.WebCookieManager.clearAllCookiesSync(this.source !== 'org.hsmihon.mycomic'); this.controller.refresh(); this.status = '已清除该源当前网址的保存会话'; }
    catch (error) { this.status = viewError(error as Error); }
  }
  build() {
    Column({ space: 8 }) {
      Text('来源网站').fontSize(22)
      Text(this.address).fontSize(12)
      Text(this.status).fontSize(12)
      Row({ space: 8 }) {
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
        Button('网站首页').enabled(this.homeAddress !== '' && !this.saving).onClick(() => this.home())
      }
      Row({ space: 8 }) {
        Button(this.source === EHENTAI_ID ? '保存目录会话' : '保存当前站点会话').enabled(this.owned && this.address !== '' && !this.saving).onClick(() => this.save())
        Button(this.source === EHENTAI_ID ? '清除目录会话' : '清除会话').enabled(this.owned && this.address !== '' && !this.saving).onClick(() => this.clear())
      }
      if (this.address && this.source === 'org.hsmihon.mycomic') {
        NodeContainer(MyComicBrowserView.node()).layoutWeight(1).width('100%')
      } else if (this.address) {
        Web({ src: this.homeAddress,controller: this.controller,incognitoMode: this.privateWeb() })
          .javaScriptAccess(true).domStorageAccess(this.source === 'org.hsmihon.vomic').databaseAccess(false).fileAccess(false)
          .mixedMode(MixedMode.None).multiWindowAccess(false).geolocationAccess(false)
          .onPageBegin((event) => { if (event.url && this.allowed(event.url)) { this.address = event.url; } })
          .onOverrideUrlLoading((request) => !this.allowed(request.getRequestUrl()))
          .onInterceptRequest((event) => {
            if (this.allowedResource(event.request)) { return null; }
            const response = new WebResourceResponse(); response.setResponseCode(403); response.setReasonMessage('Blocked'); response.setResponseData(''); return response;
          })
          .onSslErrorEventReceive((event) => { event.handler.handleCancel(); this.status = '证书验证失败，连接已取消'; })
          .layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%').padding(12).backgroundColor($r('app.color.theme_f7f4ed'))
  }
}
