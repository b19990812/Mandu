import { url } from '@kit.ArkTS';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext, ResponseRetention } from '../../model/RequestTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { SiteJsonClient } from './SiteJsonClient';
import { SharedRequest } from '../../network/SharedRequest';
import { SiteSession } from '../../network/SiteSession';
import { SourceChanges } from '../SourceChanges';
import { observeRetention } from '../../network/ResponseRetentionPolicy';

interface KuDataCache { data: JsonNode; expiresAt: number; }

export class ManhuakuClient {
  private static cache: Map<string,KuDataCache> = new Map();
  private static pending: Map<string,SharedRequest<JsonNode>> = new Map();
  private static epoch: number = 0;
  readonly site: SourceSiteAccess;
  private readonly transport: Transport;
  private readonly reader: SiteJsonClient;
  constructor(site: SourceSiteAccess,transport: Transport) { this.site = site; this.transport = transport; this.reader = new SiteJsonClient(site,transport,1); }
  binding(operation: string): string { return this.reader.binding(operation); }
  text(path: string,ctx: CallContext): Promise<string> { return this.reader.text(path,ctx); }
  invalidate(): void { ManhuakuClient.epoch++; ManhuakuClient.cache.clear(); }
  private key(path: string,post: boolean): string { return JSON.stringify([this.site.sourceId,this.site.baseUrl,this.site.revision,SiteSession.epoch(this.site.sourceId),SourceChanges.epoch(this.site.sourceId),ManhuakuClient.epoch,post,path]); }
  async data(path: string,post: boolean,ctx: CallContext,force: boolean = false): Promise<JsonNode> {
    checkCall(ctx);
    if (ctx.ruleRevision !== 1) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库适配器版本已改变'); }
    if (!(post ? /^\/comic\/[1-9][0-9]{0,18}$/ : /^\/api\/source-lines\/[1-9][0-9]{0,18}$/).test(path)) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库数据接口路径无效'); }
    const key = this.key(path,post); const saved = ManhuakuClient.cache.get(key);
    if (!force && saved && saved.expiresAt > Date.now()) { return saved.data; }
    if (force) { ManhuakuClient.cache.delete(key); return this.loadData(path,post,ctx,key); }
    let pending = ManhuakuClient.pending.get(key);
    if (!pending || pending.cancelled) {
      if (ManhuakuClient.pending.size >= 16 && !pending) { throw new AppError(ErrorCode.RATE_LIMITED,'漫画库数据请求过多'); }
      const request = new SharedRequest<JsonNode>(ctx,async (call: CallContext) => {
        try { return await this.loadData(path,post,call,key); }
        finally { if (ManhuakuClient.pending.get(key) === request) { ManhuakuClient.pending.delete(key); } }
      }); ManhuakuClient.pending.set(key,request); pending = request;
    }
    return pending.consume(ctx);
  }
  private async loadData(path: string,post: boolean,ctx: CallContext,key: string): Promise<JsonNode> {
    const retention: ResponseRetention = { allowed: true,expiresAt: Date.now() + (post ? 60000 : 3600000),staleAllowed: false };
    const call: CallContext = { callId: ctx.callId,deadlineMs: ctx.deadlineMs,cancel: ctx.cancel,ruleRevision: ctx.ruleRevision,priority: ctx.priority,retention: retention };
    const policy = new UrlPolicy(this.site.allowedHosts); const address = policy.resolve(path,this.site.baseUrl);
    const response = await this.transport.send({ sourceId: this.site.sourceId,url: address,method: post ? 'POST' : 'GET',responseKind: 'metadata',maxBytes: 2097152,
      headers: [{ name: 'Accept',value: 'application/json' },{ name: 'Referer',value: this.site.baseUrl }] },call);
    observeRetention(call,response.headers);
    requireHttpSuccess(response); checkCall(ctx);
    if (policy.validate(response.finalUrl).pathname !== new url.URL(address).pathname) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库数据接口返回其他路径'); }
    const root = new JsonExtractor().parse(response.body); const code = root.members.get('code');
    if (code?.kind !== 'number' || code.scalar !== '0') { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库 API 未返回 code=0 的成功结果'); }
    const data = root.members.get('data');
    if (data?.kind !== 'object') { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库 API 数据对象缺失'); }
    if (key !== this.key(path,post)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库配置或会话已改变'); }
    if (retention.allowed && retention.expiresAt > Date.now()) {
      ManhuakuClient.cache.delete(key); ManhuakuClient.cache.set(key,{ data: data,expiresAt: retention.expiresAt });
      while (ManhuakuClient.cache.size > 16) { const oldest: string = Array.from(ManhuakuClient.cache.keys())[0]; ManhuakuClient.cache.delete(oldest); }
    }
    return data;
  }
}
