import { webview } from '@kit.ArkWeb';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext, NetworkPriority } from '../model/RequestTypes';
import { ByteSink } from '../model/ByteSink';
import { FileStore } from '../storage/FileStore';
import { checkCall, requireHttpSuccess } from '../source/SourceHttp';
import { JsonExtractor } from '../parsing/JsonExtractor';
import { EHENTAI_BASE, ehentaiAddress, EhentaiQuota } from './EhentaiAccess';
import { EHENTAI_PORT_CHUNK, ehentaiImagePortScript } from './EhentaiImagePort';
import { TransportResponse } from './Transport';
import { requestPriority } from './RequestPriority';

export interface EhentaiBrowserImage { url: string; bytes: number; }
enum ImageStage { WaitingForBlank, Page, Inspect, Port, Download }
const IMAGE_NODE_IDLE_TIMEOUT_MS: number = 8000;

interface BrowserImageJob {
  page: string;
  retryPage: string;
  address: string;
  key: string;
  limit: number;
  ctx: CallContext;
  sink: ByteSink;
  stage: ImageStage;
  received: number;
  sequence: number;
  ready: boolean;
  settled: boolean;
  handshake: number;
  nodeTimer: number;
  downloaded: number;
  canReassign: boolean;
  port?: webview.WebMessagePort;
  peer?: webview.WebMessagePort;
  writing?: Promise<void>;
  item?: webview.WebDownloadItem;
  finish: (error?: AppError,bytes?: number) => void;
}

const inspectImage: string = "JSON.stringify((()=>{const img=document.querySelector('img#img');" +
  "return {page:location.href,src:img?(img.currentSrc||img.src):'',anonymous:img?.crossOrigin==='anonymous'," +
  "retryAction:document.querySelector('a#loadfail')?.getAttribute('onclick')||''," +
  "notice:!img?(document.body?.textContent||'').slice(0,4000):''};})())";

function retryPage(page: string, action: string): string {
  // The site supplies this token for its same-page “image fails loading” action.
  const token = /^\s*return\s+nl\((['"])([A-Za-z0-9_-]{8,64})\1\)\s*;?\s*$/.exec(action)?.[2];
  return token ? page.split('?',1)[0] + '?nl=' + token : '';
}

function imageLimitError(limit: number): AppError {
  const mib = limit / 1048576;
  const size = Number.isInteger(mib) ? mib.toString() + ' MiB' : limit.toString() + ' 字节';
  return new AppError(ErrorCode.RESPONSE_TOO_LARGE,'E-Hentai 图片超过阅读器安全上限（' + size + '）');
}

export class EhentaiBrowserSession {
  private static hosts: EhentaiBrowserSession[] = [];
  private readonly controller: webview.WebviewController;
  private readonly files: FileStore;
  private active?: BrowserImageJob;
  private blankReady: boolean = false;
  private closed: boolean = false;

  constructor(controller: webview.WebviewController,cacheDir: string) {
    this.controller = controller;
    this.files = new FileStore(cacheDir,'ehentai_web_parts');
    const delegate = new webview.WebDownloadDelegate();
    delegate.onBeforeDownload((item: webview.WebDownloadItem) => this.begin(item));
    delegate.onDownloadUpdated((item: webview.WebDownloadItem) => this.update(item));
    delegate.onDownloadFinish((item: webview.WebDownloadItem) => this.done(item));
    delegate.onDownloadFailed((item: webview.WebDownloadItem) => this.failed(item));
    controller.setDownloadDelegate(delegate);
    EhentaiBrowserSession.hosts.push(this);
  }

  close(): void {
    if (this.closed) { return; }
    this.closed = true;
    const index = EhentaiBrowserSession.hosts.indexOf(this);
    if (index >= 0) { EhentaiBrowserSession.hosts.splice(index,1); }
    this.active?.finish(new AppError(ErrorCode.CANCELLED,'E-Hentai 浏览器会话已关闭'));
  }

  static async read(page: string,limit: number,ctx: CallContext,sink: ByteSink): Promise<EhentaiBrowserImage> {
    const waitUntil = Date.now() + 3000;
    while (true) {
      checkCall(ctx); EhentaiQuota.check();
      const session = EhentaiBrowserSession.hosts[EhentaiBrowserSession.hosts.length - 1];
      if (session && !session.active) { return session.readImage(page,limit,ctx,sink); }
      if (!session && Date.now() >= waitUntil) {
        throw new AppError(ErrorCode.OFFLINE,'E-Hentai 浏览器尚未就绪，请重新打开阅读器');
      }
      await new Promise<void>((resolve) => { setTimeout(resolve,60); });
    }
  }

  allowsNavigation(address: string): boolean {
    const job = this.active;
    return address === 'about:blank' || (!!job && !job.settled && job.stage !== ImageStage.WaitingForBlank && job.page === address);
  }

  allows(address: string): boolean {
    const job = this.active;
    return address === 'about:blank' || (!!job && !job.settled && job.stage !== ImageStage.WaitingForBlank && !!this.canonical(address));
  }

  pageLoaded(address: string): void {
    const job = this.active;
    if (address === 'about:blank' && (!job || job.settled || job.stage === ImageStage.WaitingForBlank)) {
      this.blankReady = true;
      try { this.controller.clearHistory(); } catch (_) { /* The Web component may already be detached. */ }
      if (job && !job.settled) { this.navigate(job); }
      return;
    }
    if (!job || job.settled || job.stage !== ImageStage.Page || address !== job.page) { return; }
    job.stage = ImageStage.Inspect;
    this.openImagePort(job);
  }

  private navigate(job: BrowserImageJob): void {
    // The initial Web navigation and each cleanup navigation must finish before the next page.
    this.blankReady = false;
    job.stage = ImageStage.Page;
    try { this.controller.onActive(); this.controller.loadUrl(job.page); }
    catch (_) { job.finish(new AppError(ErrorCode.NETWORK_ERROR,'ArkWeb 无法打开 E-Hentai 图片页')); }
  }

  httpError(address: string,status: number,main: boolean): void {
    const job = this.active;
    if (!job || job.settled || job.stage === ImageStage.WaitingForBlank || status < 400) { return; }
    if (main) {
      if (address === job.page) { job.finish(this.httpFailure(address,status)); }
      return;
    }
    const image = this.canonical(address);
    if (!image) { return; }
    if (image === job.address) { job.finish(this.httpFailure(image,status,true)); }
  }

  certificateError(): void {
    const job = this.active;
    if (job && job.stage !== ImageStage.WaitingForBlank) {
      job.finish(new AppError(ErrorCode.TLS_HANDSHAKE,'ArkWeb 未能验证 E-Hentai 网页或图片节点的证书'));
    }
  }

  resourceError(address: string,code: number,main: boolean): void {
    const job = this.active;
    if (main && job && job.stage !== ImageStage.WaitingForBlank && address === job.page) {
      job.finish(new AppError(ErrorCode.NETWORK_ERROR,'E-Hentai 正文网页加载失败（ArkWeb ' + code.toString() + '）'));
    }
  }

  renderExited(): void {
    this.active?.finish(new AppError(ErrorCode.BROWSER_MESSAGE_FAILED,'ArkWeb 渲染进程已退出，请重试'));
  }

  private canonical(address: string): string {
    try { return ehentaiAddress(address,true).toString(); }
    catch (_) {
      try {
        const parsed = ehentaiAddress(address,false);
        if (parsed.origin + '/' === EHENTAI_BASE) { return parsed.toString(); }
      } catch (_) { /* Keep the reader WebView on the validated site and image nodes. */ }
      return '';
    }
  }

  private httpFailure(address: string,status: number,image: boolean = false): AppError {
    const response: TransportResponse = { statusCode: status,finalUrl: address,headers: [],body: '',bytes: 0 };
    try {
      EhentaiQuota.observe(response);
      requireHttpSuccess(response);
    } catch (error) {
      if (error instanceof AppError) {
        if (image && status >= 500 && status <= 599 && error.code === ErrorCode.HTTP_SERVER) {
          return new AppError(ErrorCode.BROWSER_DOWNLOAD_FAILED,error.message);
        }
        return error;
      }
    }
    return new AppError(ErrorCode.NETWORK_ERROR,'E-Hentai 未返回完整图片（HTTP ' + status.toString() + '）');
  }

  private async openImagePort(job: BrowserImageJob): Promise<void> {
    try {
      const parser = new JsonExtractor();
      const until = Date.now() + 5000;
      while (!job.settled && Date.now() < until) {
        const raw = await this.controller.runJavaScript(inspectImage);
        if (job.settled) { return; }
        const outer = parser.parse(raw);
        const doc = outer.kind === 'string' ? parser.parse(outer.scalar) : outer;
        if (doc.members.get('page')?.scalar !== job.page) {
          throw new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 网页已离开当前图片页');
        }
        const notice = doc.members.get('notice')?.scalar || '';
        if (notice) {
          EhentaiQuota.observe({ statusCode: 200,finalUrl: job.page,headers: [],body: notice,bytes: 0 });
          if (/this gallery (?:is unavailable|has been removed)|content warning\s*[-–]/i.test(notice)) {
            throw new AppError(ErrorCode.ACCESS_DENIED,'E-Hentai 画廊受限或已移除');
          }
          if (/verify you are human|checking your browser|enable javascript and cookies to continue/i.test(notice)) {
            throw new AppError(ErrorCode.AUTH_REQUIRED,'E-Hentai 要求网站验证，请在来源网站完成后重试');
          }
        }
        const rawAddress = doc.members.get('src')?.scalar || '';
        if (rawAddress) {
          const address = this.canonical(rawAddress);
          if (!address || address !== rawAddress) {
            throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 网页返回了未经验证的图片地址');
          }
          if (/\/(?:509|imglimit)\.gif(?:\?|$)/i.test(address)) { throw this.httpFailure(address,509); }
          if (/\/om\/.*\/x\/0\//.test(address)) {
            throw new AppError(ErrorCode.ACCESS_DENIED,'E-Hentai 未向当前网页提供可读取的图片');
          }
          job.address = address;
          job.retryPage = retryPage(job.page,doc.members.get('retryAction')?.scalar || '');
          this.watchNode(job);
          await this.connect(job,doc.members.get('anonymous')?.scalar === 'true');
          return;
        }
        await new Promise<void>((resolve) => { setTimeout(resolve,100); });
      }
      job.finish(new AppError(ErrorCode.NETWORK_ERROR,'E-Hentai 网页未提供正文图片，请在来源网站检查'));
    } catch (error) {
      job.finish(error instanceof AppError ? error : new AppError(ErrorCode.BROWSER_MESSAGE_FAILED,'ArkWeb 无法检查当前图片页'));
    }
  }

  private async connect(job: BrowserImageJob,anonymous: boolean): Promise<void> {
    job.stage = ImageStage.Port;
    const token = 'hs-ehentai-image:' + job.key;
    const reply = await this.controller.runJavaScript(ehentaiImagePortScript(job.page,job.address,token,job.limit,anonymous));
    if (job.settled) { return; }
    if (reply !== token && reply !== JSON.stringify(token)) {
      throw new AppError(ErrorCode.BROWSER_MESSAGE_FAILED,'ArkWeb 未能在当前图片页安装消息监听器');
    }
    const ports = this.controller.createWebMessagePorts();
    job.port = ports[0];
    job.peer = ports[1];
    if (!job.port || !job.peer) { throw new AppError(ErrorCode.BROWSER_MESSAGE_FAILED,'ArkWeb 未能创建图片消息端口'); }
    job.port.onMessageEvent((message: webview.WebMessage) => this.onMessage(job,message));
    this.controller.postMessage(token,[job.peer],EHENTAI_BASE);
    job.peer = undefined;
    job.handshake = setTimeout(() => job.finish(new AppError(ErrorCode.BROWSER_MESSAGE_FAILED,'ArkWeb 图片消息端口握手超时')),4000);
  }

  private onMessage(job: BrowserImageJob,message: webview.WebMessage): void {
    if (job.settled || job.stage !== ImageStage.Port) { return; }
    const badFrame = (): void => job.finish(new AppError(ErrorCode.BROWSER_MESSAGE_FAILED,'ArkWeb 图片消息不完整、重复或顺序错误'));
    if (!job.ready) {
      if (message === 'changed') {
        job.finish(new AppError(ErrorCode.CONTENT_CHANGED,'E-Hentai 网页切换了正文图片，请重试'));
      } else if (message === 'ready') {
        job.ready = true; clearTimeout(job.handshake);
      } else { badFrame(); }
      return;
    }
    if (job.writing) { badFrame(); return; }
    if (message instanceof ArrayBuffer) {
      const bytes = message.byteLength - 4;
      if (bytes < 1 || bytes > EHENTAI_PORT_CHUNK || new DataView(message).getUint32(0) !== job.sequence) {
        badFrame(); return;
      }
      if (job.received + bytes > job.limit) {
        job.finish(imageLimitError(job.limit)); return;
      }
      clearTimeout(job.nodeTimer);
      job.writing = this.writeFrame(job,message.slice(4));
      return;
    }
    if (typeof message !== 'string') { badFrame(); return; }
    if (message.startsWith('end:')) {
      if (job.received < 1 || message !== 'end:' + job.received.toString()) { badFrame(); }
      else { job.finish(undefined,job.received); }
    } else if (message === 'unreadable' && job.received === 0) {
      this.startDownload(job);
    } else if (/^http:[1-5][0-9]{2}$/.test(message)) {
      job.finish(this.httpFailure(job.address,Number(message.substring(5)),true));
    } else if (message === 'limit') {
      job.finish(imageLimitError(job.limit));
    } else if (message === 'redirect') {
      job.finish(new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 图片请求发生重定向'));
    } else if (message === 'format') {
      job.finish(new AppError(ErrorCode.UNSUPPORTED,'E-Hentai 网页未返回受支持的图片格式'));
    } else if (message === 'network') {
      job.finish(new AppError(job.received ? ErrorCode.NETWORK_ERROR : ErrorCode.BROWSER_DOWNLOAD_FAILED,
        'ArkWeb 无法加载完整的 E-Hentai 图片'));
    } else { badFrame(); }
  }

  private async writeFrame(job: BrowserImageJob,data: ArrayBuffer): Promise<void> {
    try {
      await job.sink.write(data);
      if (job.settled) { return; }
      checkCall(job.ctx);
      job.received += data.byteLength;
      const ack = 'ack:' + job.sequence.toString();
      job.sequence++;
      job.writing = undefined;
      try { job.port?.postMessageEvent(ack); }
      catch (_) { job.finish(new AppError(ErrorCode.BROWSER_MESSAGE_FAILED,'ArkWeb 图片消息确认发送失败')); }
    } catch (error) {
      job.finish(error instanceof AppError ? error : new AppError(ErrorCode.IO_ERROR,'E-Hentai 图片缓存写入失败'));
    }
  }

  private closePorts(job: BrowserImageJob): void {
    clearTimeout(job.handshake);
    try { job.port?.close(); } catch (_) { /* The page or renderer may already be gone. */ }
    try { job.peer?.close(); } catch (_) { /* A port might have been transferred already. */ }
    job.port = undefined;
    job.peer = undefined;
  }

  private watchNode(job: BrowserImageJob): void {
    if (!job.canReassign || !job.retryPage || job.retryPage === job.page) { return; }
    clearTimeout(job.nodeTimer);
    // Browser downloads are staged separately, so stalled downloads can be discarded before writing to the sink.
    job.nodeTimer = setTimeout(() => job.finish(new AppError(ErrorCode.BROWSER_DOWNLOAD_FAILED,
      'E-Hentai 图片节点停止传输')),IMAGE_NODE_IDLE_TIMEOUT_MS);
  }

  private downloadFailure(): AppError {
    return new AppError(ErrorCode.BROWSER_IMAGE_UNREADABLE,'网页脚本无法读取图片（可能受 CORS 或 CSP 限制），浏览器下载也失败；可在来源网站查看');
  }

  private startDownload(job: BrowserImageJob): void {
    // Use the normal browser download for the validated image URL when script reads are unavailable.
    this.closePorts(job);
    job.stage = ImageStage.Download;
    try { this.controller.startDownload(job.address); }
    catch (_) { job.finish(this.downloadFailure()); }
  }

  private matching(item: webview.WebDownloadItem,job: BrowserImageJob): boolean {
    return this.canonical(item.getOriginalUrl()) === job.address && this.canonical(item.getUrl()) === job.address;
  }

  private cancel(item?: webview.WebDownloadItem): void {
    try { item?.cancel(); } catch (_) { /* The browser may have already ended the download. */ }
  }

  private begin(item: webview.WebDownloadItem): void {
    const job = this.active;
    if (!job || job.settled || job.stage !== ImageStage.Download || job.item ||
      this.canonical(item.getOriginalUrl()) !== job.address) { this.cancel(item); return; }
    job.item = item;
    try {
      if (!this.matching(item,job)) {
        job.finish(new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 浏览器拒绝了图片下载重定向'));
      } else if (item.getTotalBytes() > job.limit) {
        job.finish(imageLimitError(job.limit));
      } else { item.start(this.files.localPath(job.key)); }
    } catch (_) { job.finish(this.downloadFailure()); }
  }

  private update(item: webview.WebDownloadItem): void {
    const job = this.active;
    if (!job || job.settled || job.item?.getGuid() !== item.getGuid()) { return; }
    if (!this.matching(item,job)) {
      job.finish(new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 浏览器拒绝了图片下载重定向'));
    } else if (item.getReceivedBytes() > job.limit || item.getTotalBytes() > job.limit) {
      job.finish(imageLimitError(job.limit));
    } else if (item.getReceivedBytes() > job.downloaded) {
      job.downloaded = item.getReceivedBytes();
      this.watchNode(job);
    }
  }

  private done(item: webview.WebDownloadItem): void {
    const job = this.active;
    if (!job || job.settled || job.item?.getGuid() !== item.getGuid()) { return; }
    if (!this.matching(item,job) || item.getFullPath() !== this.files.localPath(job.key)) {
      job.finish(new AppError(ErrorCode.POLICY_DENIED,'ArkWeb 返回的图片地址或文件路径无效'));
    } else { job.finish(); }
  }

  private failed(item: webview.WebDownloadItem): void {
    const job = this.active;
    if (!job || job.settled || job.stage !== ImageStage.Download ||
      (job.item ? job.item.getGuid() !== item.getGuid() : this.canonical(item.getOriginalUrl()) !== job.address)) { return; }
    const code = item.getLastErrorCode();
    if (code === webview.WebDownloadErrorCode.SERVER_CERT_PROBLEM) { this.certificateError(); }
    else if (code === webview.WebDownloadErrorCode.SERVER_FORBIDDEN) {
      job.finish(new AppError(ErrorCode.ACCESS_DENIED,'网页脚本无法读取图片，浏览器下载也被站点拒绝（403）'));
    } else if (code === webview.WebDownloadErrorCode.FILE_NO_SPACE) {
      job.finish(new AppError(ErrorCode.STORAGE_FULL,'存储空间不足，无法保存浏览器图片'));
    } else if (code === webview.WebDownloadErrorCode.FILE_TOO_LARGE) {
      job.finish(imageLimitError(job.limit));
    } else if (code === webview.WebDownloadErrorCode.NETWORK_FAILED || code === webview.WebDownloadErrorCode.NETWORK_TIMEOUT ||
      code === webview.WebDownloadErrorCode.NETWORK_DISCONNECTED || code === webview.WebDownloadErrorCode.NETWORK_SERVER_DOWN ||
      code === webview.WebDownloadErrorCode.SERVER_UNREACHABLE) {
      job.finish(new AppError(ErrorCode.BROWSER_DOWNLOAD_FAILED,'E-Hentai 图片节点连接失败（ArkWeb ' + code.toString() + '）'));
    } else { job.finish(this.downloadFailure()); }
  }

  private async copyDownload(job: BrowserImageJob): Promise<number> {
    const size = this.files.size(job.key) || 0;
    if (!size) { throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 返回的图片为空'); }
    if (size > job.limit) { throw imageLimitError(job.limit); }
    const file = fs.openSync(this.files.localPath(job.key),fs.OpenMode.READ_ONLY);
    try {
      let copied = 0;
      while (copied < size) {
        checkCall(job.ctx);
        if (this.closed) { throw new AppError(ErrorCode.CANCELLED,'E-Hentai 浏览器会话已关闭'); }
        const buffer = new ArrayBuffer(Math.min(EHENTAI_PORT_CHUNK,size - copied));
        const read = await fs.read(file.fd,buffer);
        if (read <= 0) { throw new AppError(ErrorCode.CORRUPT_FILE,'ArkWeb 返回的图片文件不完整'); }
        checkCall(job.ctx);
        await job.sink.write(buffer.slice(0,read));
        copied += read;
      }
      return copied;
    } finally { fs.closeSync(file); }
  }

  private async readImage(page: string,limit: number,ctx: CallContext,sink: ByteSink): Promise<EhentaiBrowserImage> {
    const deadline = Math.min(ctx.deadlineMs,Date.now() + 28000);
    const visited = new Set<string>([page]);
    let address = page;
    try {
      while (true) {
        try { return await this.readAttempt(address,limit,ctx,sink,deadline,visited.size < 3); }
        catch (error) {
          const job = this.active;
          if (!job || this.closed || (job.stage !== ImageStage.Port && job.stage !== ImageStage.Download) ||
            !(error instanceof AppError) ||
            (error.code !== ErrorCode.BROWSER_DOWNLOAD_FAILED && error.code !== ErrorCode.TLS_HANDSHAKE)) {
            throw error as Error;
          }
          checkCall(ctx);
          // Site reloads consume quota. Defer them until the reader requests the page.
          if (requestPriority(ctx) > NetworkPriority.Interactive) {
            throw new AppError(ErrorCode.BROWSER_RETRY_ON_DISPLAY,error.message);
          }
          if (!job.retryPage || visited.size >= 3 || visited.has(job.retryPage) || Date.now() >= deadline ||
            job.received || job.writing) { throw error; }
          EhentaiQuota.check();
          hilog.info(0x0001,'HSReader','EHENTAI_ARKWEB_REASSIGN attempt=%{public}d code=%{public}s',visited.size,error.code);
          address = job.retryPage;
          visited.add(address);
        }
      }
    } finally { this.active = undefined; }
  }

  private async readAttempt(page: string,limit: number,ctx: CallContext,sink: ByteSink,deadline: number,
    canReassign: boolean): Promise<EhentaiBrowserImage> {
    const key = util.generateRandomUUID().replace(/-/g,'');
    let unsubscribe: () => void = () => {};
    let timer = -1;
    let finish: (error?: AppError,bytes?: number) => void = () => {};
    const result = new Promise<number>((resolve,reject) => {
      finish = (error?: AppError,bytes?: number): void => { if (error) { reject(error); } else { resolve(bytes || 0); } };
    });
    const job: BrowserImageJob = {
      page: page,retryPage: '',address: '',key: key,limit: limit,ctx: ctx,sink: sink,stage: ImageStage.WaitingForBlank,
      received: 0,sequence: 0,ready: false,settled: false,handshake: -1,nodeTimer: -1,downloaded: 0,canReassign: canReassign,
      finish: (error?: AppError,bytes?: number): void => {
        if (job.settled) { return; }
        job.settled = true;
        clearTimeout(timer); clearTimeout(job.nodeTimer); unsubscribe(); this.closePorts(job);
        if (error) { this.cancel(job.item); }
        if (job.stage !== ImageStage.WaitingForBlank) {
          try {
            this.controller.stop();
            this.controller.loadUrl('about:blank');
          } catch (_) { /* The Web component may already be detached. */ }
        }
        finish(error,bytes);
      }
    };
    this.active = job;
    try {
      timer = setTimeout(() => {
        job.finish(job.stage === ImageStage.Download ? this.downloadFailure() :
          new AppError(ErrorCode.TIMEOUT,job.stage === ImageStage.Port ? 'ArkWeb 图片二进制传输超时' : 'E-Hentai 图片页加载超时'));
      },Math.max(1,deadline - Date.now()));
      unsubscribe = ctx.cancel.subscribe(() => job.finish(new AppError(ErrorCode.CANCELLED,'E-Hentai 浏览器取图已取消')));
      if (!job.settled && this.blankReady) { this.navigate(job); }
      const transferred = await result;
      checkCall(ctx);
      const bytes = transferred || await this.copyDownload(job);
      checkCall(ctx);
      hilog.info(0x0001,'HSReader','EHENTAI_ARKWEB_IMAGE_READY route=%{public}s bytes=%{public}d',transferred ? 'port' : 'download',bytes);
      return { url: job.address,bytes: bytes };
    } finally {
      await job.writing;
      if (job.stage === ImageStage.Download) {
        try { this.files.remove(key); } catch (_) { /* App cache cleanup can retry. */ }
      }
    }
  }
}
