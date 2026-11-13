import { webview } from '@kit.ArkWeb';
import { url, util } from '@kit.ArkTS';
import { RequestPlan, TransportResponse } from './Transport';
import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { JsonExtractor, JsonNode } from '../parsing/JsonExtractor';
import { SiteSession } from './SiteSession';
import { UrlPolicy } from './UrlPolicy';

// MyComic metadata stays in ArkWeb. No native JS proxy or arbitrary script API is
// exposed to the site. The visible verification view and retained host share only
// MyComic's regular browser context. Other sources use private contexts. All
// metadata requests remain on the selected origin.
export class MyComicBrowserSession {
  private static host?: webview.WebviewController;
  private static visible?: webview.WebviewController;
  private static busy: boolean = false;
  private static foreground: boolean = true;
  private static sequence: number = 0;
  private static policy: UrlPolicy = new UrlPolicy([]);
  static attachHost(controller: webview.WebviewController): void { MyComicBrowserSession.host = controller; }
  static attachVisible(controller: webview.WebviewController): void { MyComicBrowserSession.visible = controller; }
  static detachVisible(controller: webview.WebviewController): void { if (MyComicBrowserSession.visible === controller) { MyComicBrowserSession.visible = undefined; } }
  static setForeground(active: boolean): void { MyComicBrowserSession.foreground = active; }
  static close(): void { MyComicBrowserSession.host = undefined; MyComicBrowserSession.visible = undefined; }
  private static check(ctx: CallContext): void {
    if (ctx.cancel.cancelled) { throw new AppError(ErrorCode.CANCELLED,'浏览器请求已取消'); }
    if (Date.now() >= ctx.deadlineMs) { throw new AppError(ErrorCode.TIMEOUT,'浏览器请求已超时'); }
    if (!MyComicBrowserSession.foreground) { throw new AppError(ErrorCode.OFFLINE,'MYCOMIC需要在应用前台读取网站数据'); }
    if (!SiteSession.availableFor('org.hsmihon.mycomic')) { throw new AppError(ErrorCode.CONFLICT,'请先关闭另一个来源的网站会话'); }
  }
  private static pause(): Promise<void> { return new Promise<void>((resolve) => { setTimeout(resolve,100); }); }
  private static parse(raw: string): JsonNode { const node = new JsonExtractor().parse(raw); return node.kind === 'string' ? new JsonExtractor().parse(node.scalar) : node; }
  private static scalar(node: JsonNode,name: string): string { return node.members.get(name)?.scalar || ''; }
  static validate(plan: RequestPlan,base: string): string {
    const target = MyComicBrowserSession.policy.validate(plan.url);
    const origin = MyComicBrowserSession.policy.validate(base).origin;
    if (plan.sourceId !== 'org.hsmihon.mycomic' || plan.responseKind !== 'metadata' || plan.method && plan.method !== 'GET' ||
      target.origin !== origin || !/^\/cn\/(?:comics(?:\/[1-9][0-9]{0,18})?|chapters\/[1-9][0-9]{0,18})$/.test(target.pathname) ||
      !Number.isInteger(plan.maxBytes) || plan.maxBytes < 1 || plan.maxBytes > 2097152) {
      throw new AppError(ErrorCode.POLICY_DENIED,'浏览器通道仅支持当前MYCOMIC网站的页面元数据');
    }
    return origin;
  }
  private static async prepare(controller: webview.WebviewController,origin: string,address: string,ctx: CallContext): Promise<void> {
    controller.onActive();
    let current = '';
    try { current = new url.URL(controller.getUrl()).origin; } catch (_) {}
    if (current !== origin) { controller.loadUrl(address); }
    for (let index = 0; index < 150; index++) {
      MyComicBrowserSession.check(ctx);
      try {
        const ready = MyComicBrowserSession.parse(await controller.runJavaScript('JSON.stringify({origin:location.origin,ready:document.readyState,challenge:!!window._cf_chl_opt || /^(Just a moment|Attention Required!)/i.test(document.title || "")})'));
        if (MyComicBrowserSession.scalar(ready,'origin') === origin && MyComicBrowserSession.scalar(ready,'challenge') !== 'true' &&
          ['interactive','complete'].indexOf(MyComicBrowserSession.scalar(ready,'ready')) >= 0) { return; }
      } catch (_) { /* A navigation can briefly replace the execution context. */ }
      await MyComicBrowserSession.pause();
    }
    throw new AppError(ErrorCode.AUTH_REQUIRED,'请先在MYCOMIC网站完成验证，再返回刷新');
  }
  static async read(plan: RequestPlan,base: string,ctx: CallContext): Promise<TransportResponse> {
    const origin = MyComicBrowserSession.validate(plan,base);
    while (MyComicBrowserSession.busy) { MyComicBrowserSession.check(ctx); await MyComicBrowserSession.pause(); }
    MyComicBrowserSession.check(ctx); MyComicBrowserSession.busy = true;
    const controller = MyComicBrowserSession.visible || MyComicBrowserSession.host;
    const key = '__hsMyComicMetadata' + (++MyComicBrowserSession.sequence).toString();
    try {
      if (!controller) { throw new AppError(ErrorCode.AUTH_REQUIRED,'请打开MYCOMIC网站完成验证，再返回刷新'); }
      await MyComicBrowserSession.prepare(controller,origin,plan.url,ctx);
      const timeout = Math.max(1,Math.min(30000,ctx.deadlineMs - Date.now()));
      const script = `(() => {
        const key=${JSON.stringify(key)};
        if(location.origin!==${JSON.stringify(origin)}) return 'wrong-origin';
        const abort=new AbortController();window[key]={state:'pending',abort};
        (async()=>{const timer=setTimeout(()=>abort.abort(),${timeout});try{
          const response=await fetch(${JSON.stringify(plan.url)},{credentials:'same-origin',cache:'no-store',redirect:'follow',signal:abort.signal,
            referrer:${JSON.stringify(origin + '/')},referrerPolicy:'same-origin',headers:{Accept:'text/html,application/xhtml+xml','Accept-Language':'zh-CN,zh;q=0.9'}});
          if(new URL(response.url).origin!==${JSON.stringify(origin)}) throw new Error('origin');
          const reader=response.body.getReader(),chunks=[];let bytes=0;
          while(true){const item=await reader.read();if(item.done)break;bytes+=item.value.byteLength;if(bytes>${plan.maxBytes}){abort.abort();throw new Error('size');}chunks.push(item.value);}
          const data=new Uint8Array(bytes);let offset=0;for(const item of chunks){data.set(item,offset);offset+=item.byteLength;}
          const body=new TextDecoder('utf-8',{fatal:true}).decode(data);
          if(window[key]?.abort===abort)window[key]={state:'done',abort,status:response.status,url:response.url,challenge:response.headers.get('cf-mitigated')||'',
            contentType:response.headers.get('content-type')||'',retryAfter:response.headers.get('retry-after')||'',bytes,textBytes:new TextEncoder().encode(body).byteLength,length:body.length,body};
        }catch(error){if(window[key]?.abort===abort)window[key]={state:'error',abort,error:error.message==='size'?'size':error.message==='origin'?'origin':error.name};}finally{clearTimeout(timer);}})();
        return 'started';
      })()`;
      await controller.runJavaScript(script);
      let result: JsonNode | undefined = undefined;
      while (!result) {
        MyComicBrowserSession.check(ctx);
        const state = MyComicBrowserSession.parse(await controller.runJavaScript('JSON.stringify((()=>{const job=window[' + JSON.stringify(key) + '];if(!job)return null;const {body,abort,...metadata}=job;return metadata;})())'));
        const stage = MyComicBrowserSession.scalar(state,'state');
        if (stage === 'error') {
          const reason = MyComicBrowserSession.scalar(state,'error');
          throw new AppError(reason === 'size' ? ErrorCode.RESPONSE_TOO_LARGE : reason === 'origin' ? ErrorCode.POLICY_DENIED : ErrorCode.NETWORK_ERROR,'MYCOMIC浏览器请求失败，请打开网站检查验证状态');
        }
        if (stage === 'done') { result = state; break; }
        await MyComicBrowserSession.pause();
      }
      const status = Number(MyComicBrowserSession.scalar(result,'status')); const length = Number(MyComicBrowserSession.scalar(result,'length'));
      const bytes = Number(MyComicBrowserSession.scalar(result,'bytes')); const textBytes = Number(MyComicBrowserSession.scalar(result,'textBytes')); const finalUrl = MyComicBrowserSession.scalar(result,'url');
      if (!Number.isInteger(status) || status < 200 || status > 599 || !Number.isInteger(length) || length < 0 || length > plan.maxBytes ||
        !Number.isInteger(bytes) || bytes < 0 || bytes > plan.maxBytes || !Number.isInteger(textBytes) || textBytes < 0 || textBytes > bytes ||
        bytes - textBytes !== 0 && bytes - textBytes !== 3 || MyComicBrowserSession.policy.validate(finalUrl).origin !== origin) {
        throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC浏览器返回的页面元数据无效');
      }
      let body = '';
      for (let offset = 0; offset < length; offset += 8192) {
        MyComicBrowserSession.check(ctx);
        const chunk = MyComicBrowserSession.parse(await controller.runJavaScript('JSON.stringify({chunk:window[' + JSON.stringify(key) + '].body.substring(' + offset.toString() + ',' + Math.min(offset + 8192,length).toString() + ')})'));
        body += MyComicBrowserSession.scalar(chunk,'chunk');
      }
      if (body.length !== length || new util.TextEncoder().encodeInto(body).length !== textBytes) { throw new AppError(ErrorCode.PARSE_ERROR,'MYCOMIC浏览器返回的页面不完整'); }
      return { statusCode: status,finalUrl: finalUrl,body: body,bytes: bytes,headers: [
        { name: 'cf-mitigated',value: MyComicBrowserSession.scalar(result,'challenge') },{ name: 'content-type',value: MyComicBrowserSession.scalar(result,'contentType') },
        { name: 'retry-after',value: MyComicBrowserSession.scalar(result,'retryAfter') }
      ] };
    } catch (error) {
      if (error instanceof AppError) { throw error; }
      throw new AppError(ErrorCode.AUTH_REQUIRED,'MYCOMIC浏览器会话不可用，请重新打开来源网站验证');
    } finally {
      if (controller) { try { await controller.runJavaScript('(()=>{const job=window[' + JSON.stringify(key) + '];if(job?.abort)job.abort.abort();delete window[' + JSON.stringify(key) + '];})()'); } catch (_) {} }
      MyComicBrowserSession.busy = false;
    }
  }
}
