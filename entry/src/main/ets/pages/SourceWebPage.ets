import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { url } from '@kit.ArkTS';
import { AppContainer } from '../app/AppContainer';
import { UrlPolicy } from '../network/UrlPolicy';
import { SiteSession } from '../network/SiteSession';
import { viewError } from '../vm/ViewOperation';
interface SourceWebParams { sourceId: string; }
@Entry
@Component
struct SourceWebPage {
  @State private address: string = '';
  @State private homeAddress: string = '';
  @State private status: string = '正在读取来源…';
  private source: string = ''; private policy?: UrlPolicy; private owned: boolean = false; private closed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  async aboutToAppear(): Promise<void> {
    try {
      this.source = (this.getUIContext().getRouter().getParams() as SourceWebParams).sourceId;
      const handle = await new AppContainer(this.getUIContext().getHostContext() as common.UIAbilityContext).registry.open(this.source);
      if (this.closed) { return; }
      this.policy = new UrlPolicy(handle.rule.allowedHosts); this.policy.validate(handle.rule.baseUrl);
      if (!SiteSession.acquire(this.source)) { this.status = '请先关闭另一个网站会话'; return; }
      this.owned = true; webview.WebCookieManager.clearAllCookiesSync(true);
      this.homeAddress = handle.rule.baseUrl; this.address = this.homeAddress; this.status = '独立临时浏览；保存会话后仅当前源、当前网址使用，有效期最多24小时。';
    } catch (error) { this.status = viewError(error as Error); }
  }
  aboutToDisappear(): void { this.closed = true; if (this.owned) { webview.WebCookieManager.clearAllCookiesSync(true); SiteSession.release(this.source); this.owned = false; } }
  private allowed(address: string): boolean { try { if (!this.policy) { return false; } const parsed = new url.URL(address); parsed.hash = ''; this.policy.validate(parsed.toString()); return true; } catch (_) { return false; } }
  private home(): void { if (this.homeAddress) { this.controller.loadUrl(this.homeAddress); this.address = this.homeAddress; } }
  private async save(): Promise<void> {
    try { await SiteSession.save(this.source,this.address,webview.WebCookieManager.fetchCookieSync(this.address,true)); this.status = '会话已加密保存；返回来源后可重试加载'; }
    catch (error) { this.status = viewError(error as Error); }
  }
  private async clear(): Promise<void> {
    try { await SiteSession.clear(this.source,this.address); webview.WebCookieManager.clearAllCookiesSync(true); this.controller.refresh(); this.status = '已清除该源当前网址的保存会话'; }
    catch (error) { this.status = viewError(error as Error); }
  }
  build() {
    Column({ space: 8 }) {
      Text('来源网站').fontSize(22)
      Text(this.address).fontSize(12)
      Text(this.status).fontSize(12)
      Row({ space: 8 }) {
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
        Button('网站首页').enabled(this.homeAddress !== '').onClick(() => this.home())
      }
      Row({ space: 8 }) {
        Button('保存当前站点会话').enabled(this.address !== '').onClick(() => this.save())
        Button('清除会话').enabled(this.address !== '').onClick(() => this.clear())
      }
      if (this.address) {
        Web({ src: this.homeAddress,controller: this.controller,incognitoMode: true })
          .javaScriptAccess(true).domStorageAccess(this.source === 'org.hsmihon.vomic').databaseAccess(false).fileAccess(false)
          .mixedMode(MixedMode.None).multiWindowAccess(false).geolocationAccess(false)
          .onPageBegin((event) => { if (event.url && this.allowed(event.url)) { this.address = event.url; } })
          .onOverrideUrlLoading((request) => !this.allowed(request.getRequestUrl()))
          .onInterceptRequest((event) => {
            if (this.allowed(event.request.getRequestUrl())) { return null; }
            const response = new WebResourceResponse(); response.setResponseCode(403); response.setReasonMessage('Blocked'); response.setResponseData(''); return response;
          })
          .onSslErrorEventReceive((event) => { event.handler.handleCancel(); this.status = '证书验证失败，连接已取消'; })
          .layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%').padding(12).backgroundColor($r('app.color.theme_f7f4ed'))
  }
}
