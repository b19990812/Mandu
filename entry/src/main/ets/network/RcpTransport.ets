import { SiteSession } from './SiteSession';
import { rcp } from '@kit.RemoteCommunicationKit';
import { url, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext, HeaderPair, RequestPlan, Transport, TransportResponse } from './Transport';
import { ByteSink } from '../model/ByteSink';
import { UrlPolicy } from './UrlPolicy';
import { RequestScheduler } from './RequestScheduler';
import { BusinessError } from '@kit.BasicServicesKit';
import { CopyApiPolicy } from './CopyApiPolicy';
import { isDirectoryPost } from './ReadPostPolicy';

export class RcpTransport implements Transport {
  private static tls12Hosts: Set<string> = new Set();
  private readonly policy: UrlPolicy;
  private readonly anonymous: boolean;
  private readonly allowRedirects: boolean;
  private readonly copyApi: CopyApiPolicy;

  constructor(policy: UrlPolicy,anonymous: boolean = false,allowRedirects: boolean = true,copyApiOrigin: string = '') { this.policy = policy; this.anonymous = anonymous; this.allowRedirects = allowRedirects; this.copyApi = new CopyApiPolicy(copyApiOrigin); }

  async send(plan: RequestPlan, ctx: CallContext): Promise<TransportResponse> {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const response = await this.execute(plan, ctx);
        if (attempt < 2 && (response.statusCode === 429 || response.statusCode >= 500 && response.statusCode <= 599)) { continue; }
        return response;
      } catch (error) { if (attempt === 2 || !(error instanceof AppError) || [ErrorCode.NETWORK_ERROR,ErrorCode.TIMEOUT].indexOf(error.code) < 0) { throw error as Error; } this.check(ctx); }
    }
    throw new AppError(ErrorCode.NETWORK_ERROR,'请求重试预算已耗尽');
  }

  async streamToFile(plan: RequestPlan, ctx: CallContext, sink: ByteSink): Promise<TransportResponse> {
    return this.execute(plan, ctx, sink);
  }

  private check(ctx: CallContext): void {
    if (ctx.cancel.cancelled) { throw new AppError(ErrorCode.CANCELLED, '操作已取消'); }
    if (Date.now() >= ctx.deadlineMs) { throw new AppError(ErrorCode.TIMEOUT, '请求已超时'); }
  }

  private headers(pairs: HeaderPair[]): rcp.RequestHeaders {
    const result: rcp.RequestHeaders = {};
    const allowed = ['accept', 'accept-language', 'referer', 'user-agent'];
    pairs.forEach((pair: HeaderPair) => {
      if (allowed.indexOf(pair.name.toLowerCase()) < 0 || /[\r\n]/.test(pair.value)) {
        throw new AppError(ErrorCode.POLICY_DENIED, '请求头不在允许清单中');
      }
      result[pair.name] = pair.value;
    });
    return result;
  }

  private async execute(plan: RequestPlan, ctx: CallContext, sink?: ByteSink): Promise<TransportResponse> {
    const ceiling = plan.responseKind === 'image' && sink ? 33554432 : 2097152;
    if (plan.responseKind && plan.responseKind !== 'image' && plan.responseKind !== 'metadata' || !Number.isInteger(plan.maxBytes) || plan.maxBytes <= 0 || plan.maxBytes > ceiling) {
      throw new AppError(ErrorCode.POLICY_DENIED, '请求响应限额不受支持');
    }
    const headers = this.headers(plan.headers);
    if (!Object.keys(headers).some((key: string) => key.toLowerCase() === 'user-agent')) { headers['User-Agent'] = 'HS-Mihon/0.3 (HarmonyOS; anonymous-reader)'; }
    if (!Object.keys(headers).some((key: string) => key.toLowerCase() === 'accept-language')) { headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.5'; }
    let address = this.policy.validate(plan.url).toString();
    const directoryPost = isDirectoryPost(plan,sink !== undefined);
    const visited: string[] = [];
    for (let hop = 0; hop <= 5; hop++) {
      this.check(ctx);
      if (visited.indexOf(address) >= 0) { throw new AppError(ErrorCode.POLICY_DENIED, '检测到循环跳转'); }
      visited.push(address);
      // Re-evaluate destination-specific headers after every redirect.
      const apiRequest = this.copyApi.matches(plan.sourceId,address);
      const host = new url.URL(address).hostname; const release = await RequestScheduler.acquire(plan.sourceId,host,ctx);
      let response: TransportResponse;
      try {
        let cookie: string;
        try { cookie = this.anonymous ? '' : await SiteSession.cookie(plan.sourceId,address); }
        catch (_) { throw new AppError(ErrorCode.IO_ERROR,'读取站点会话失败（' + host + '），请清除或重新保存该站点会话'); }
        const requestHeaders: rcp.RequestHeaders = {};
        Object.keys(headers).forEach((key: string) => { requestHeaders[key] = headers[key]; });
        if (cookie) { requestHeaders['Cookie'] = cookie; }
        if (apiRequest) {
          this.copyApi.headers().forEach((pair: HeaderPair) => { requestHeaders[pair.name] = pair.value; });
          await this.copyApi.wait(ctx); this.check(ctx);
        }
        response = await this.once(address, requestHeaders, plan.maxBytes, ctx, sink,directoryPost);
      }
      finally { release(); }
      if (response.statusCode === 429 || response.statusCode >= 500 && response.statusCode <= 599) {
        RequestScheduler.cooldown(plan.sourceId,host,response.headers.find((pair: HeaderPair) => pair.name.toLowerCase() === 'retry-after')?.value || '1');
      }
      const redirect = [301, 302, 303, 307, 308].indexOf(response.statusCode) >= 0;
      if (!redirect) { return response; }
      if (directoryPost) { throw new AppError(ErrorCode.POLICY_DENIED,'漫画库目录 POST 不接受跳转，请使用当前网站根网址'); }
      if (!this.allowRedirects) { throw new AppError(ErrorCode.POLICY_DENIED,'仓库目录不接受跳转，请使用最终 HTTPS 地址'); }
      if (hop === 5) { throw new AppError(ErrorCode.POLICY_DENIED, '跳转次数超限'); }
      const location = response.headers.find((pair: HeaderPair) => pair.name.toLowerCase() === 'location');
      if (!location) { throw new AppError(ErrorCode.PARSE_ERROR, '跳转响应缺少 Location'); }
      try {
        // Hostnames and status only: never log chapter paths, query strings or credentials.
        hilog.info(0x0001, 'HSReader', 'RCP_REDIRECT status=%{public}d from=%{public}s to=%{public}s',
          response.statusCode, new url.URL(address).hostname, new url.URL(location.value, address).hostname);
      } catch (_) { throw new AppError(ErrorCode.POLICY_DENIED, '跳转地址无效'); }
      const next = this.policy.resolve(location.value, address);
      if (address.startsWith('https:') && !next.startsWith('https:')) {
        throw new AppError(ErrorCode.POLICY_DENIED, '拒绝 HTTPS 降级跳转');
      }
      address = next;
    }
    throw new AppError(ErrorCode.POLICY_DENIED, '跳转次数超限');
  }

  private async once(address: string, headers: rcp.RequestHeaders, maxBytes: number,
    ctx: CallContext, sink?: ByteSink,directoryPost: boolean = false): Promise<TransportResponse> {
    this.check(ctx);
    const remaining = ctx.deadlineMs - Date.now();
    const session = rcp.createSession();
    const request = new rcp.Request(address, directoryPost ? 'POST' : 'GET', headers);
    let timedOut = false;
    let exceeded = false;
    let received = 0;
    let statusCode = 0;
    let sinkError = false;
    let sinkFailure: AppError | undefined = undefined;
    let writes: Promise<void> = Promise.resolve();
    const chunks: Uint8Array[] = [];
    const unsubscribe = ctx.cancel.subscribe(() => session.cancel(request));
    const timer = setTimeout(() => {
      timedOut = true;
      session.cancel(request);
    }, remaining);
    try {
      request.configuration = {
      security: { remoteValidation: 'system',tlsRange: { min: 'TlsV1.2',max: RcpTransport.tls12Hosts.has(new url.URL(address).hostname) ? 'TlsV1.2' : 'TlsV1.3' } },
      transfer: {
        autoRedirect: false,
        timeout: { connectMs: Math.min(30000, remaining), transferMs: remaining }
      },
      tracing: {
        httpEventsHandler: {
          onStatusCodeReceive: (status: number) => { statusCode = status; },
          onDataReceive: async (chunk: ArrayBuffer): Promise<void> => {
            this.check(ctx);
            received += chunk.byteLength;
            if (received > maxBytes) {
              exceeded = true;
              session.cancel(request);
              throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '响应超过大小限制');
            }
            // A redirect/error body must never be committed to the file sink.
            if (sink) {
              if (!sinkError && statusCode >= 200 && statusCode < 300) {
                const stable = chunk.slice(0);
                writes = writes.then(async () => {
                  this.check(ctx);
                  try { await sink.write(stable); }
                  catch (error) { sinkError = true; sinkFailure = error instanceof AppError ? error : undefined; session.cancel(request); }
                });
                await writes;
              }
            } else { chunks.push(new Uint8Array(chunk.slice(0))); }
          }
        }
      }
      };
      const raw = await session.fetch(request);
      await writes;
      this.check(ctx);
      if (exceeded) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '响应超过大小限制'); }
      if (sinkError) { throw sinkFailure || new AppError(ErrorCode.IO_ERROR, '写入下载文件失败'); }
      const pairs: HeaderPair[] = [];
      Object.keys(raw.headers).forEach((key: string) => {
        const value = raw.headers[key];
        if (typeof value === 'string') { pairs.push({ name: key, value: value }); }
        else if (value) { value.forEach((item: string) => pairs.push({ name: key, value: item })); }
      });
      let text = '';
      if (!sink) {
        const data = new Uint8Array(received);
        let offset = 0;
        chunks.forEach((chunk: Uint8Array) => { data.set(chunk, offset); offset += chunk.byteLength; });
        try { text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(data); }
        catch (_) { throw new AppError(ErrorCode.PARSE_ERROR, '响应不是有效 UTF-8'); }
      }
      return { statusCode: raw.statusCode, finalUrl: address, headers: pairs, body: text, bytes: received };
    } catch (error) {
      if (ctx.cancel.cancelled) { throw new AppError(ErrorCode.CANCELLED, '操作已取消'); }
      if (timedOut || Date.now() >= ctx.deadlineMs) { throw new AppError(ErrorCode.TIMEOUT, '请求已超时'); }
      if (exceeded) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '响应超过大小限制'); }
      if (sinkError) { throw sinkFailure || new AppError(ErrorCode.IO_ERROR, '写入下载文件失败'); }
      if (error instanceof AppError) { throw error; }
      const host = new url.URL(address).hostname; const rawCode = Number((error as BusinessError).code); const sdkCode = Number.isSafeInteger(rawCode) ? rawCode : 0;
      hilog.error(0x0001,'HSReader','RCP_FAILURE host=%{public}s sdk=%{public}d',host,sdkCode);
      if (sdkCode === 1007900035) { if (RcpTransport.tls12Hosts.size < 128) { RcpTransport.tls12Hosts.add(host); } throw new AppError(ErrorCode.NETWORK_ERROR,'TLS握手失败（' + host + '，SDK 1007900035）'); }
      // SDK errors may contain signed URLs; expose only a stable safe message.
      throw new AppError(ErrorCode.NETWORK_ERROR, '网络请求失败（' + host + '，SDK ' + sdkCode.toString() + '）');
    } finally {
      clearTimeout(timer);
      unsubscribe();
      try { await writes; } catch (_) { /* The outer request reports cancellation/timeout; finish writes before closing its sink. */ }
      session.close();
    }
  }
}
