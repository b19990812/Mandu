import { url } from '@kit.ArkTS';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { checkCall, requireHttpSuccess } from '../SourceHttp';

// Shared bounded GET mechanics only. Each source owns its response schema and image policy.
export class SiteJsonClient {
  readonly site: SourceSiteAccess;
  private readonly transport: Transport;
  private readonly policy: UrlPolicy;
  private readonly version: number;
  constructor(site: SourceSiteAccess,transport: Transport,version: number) { this.site = site; this.transport = transport; this.version = version; this.policy = new UrlPolicy(site.allowedHosts); }
  binding(operation: string): string { return JSON.stringify([this.site.sourceId,this.version,this.site.revision,this.site.baseUrl,operation]); }
  async text(path: string,ctx: CallContext): Promise<string> {
    checkCall(ctx);
    if (ctx.ruleRevision !== this.version) { throw new AppError(ErrorCode.CONTENT_CHANGED,'网站适配器版本已改变'); }
    const address = this.policy.resolve(path,this.site.baseUrl);
    const response = await this.transport.send({ sourceId: this.site.sourceId,url: address,headers: [{ name: 'Referer',value: this.site.baseUrl },
      { name: 'User-Agent',value: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36' }],maxBytes: 2097152,responseKind: 'metadata' },ctx);
    requireHttpSuccess(response); checkCall(ctx);
    const final = this.policy.validate(response.finalUrl);
    if (final.pathname !== new url.URL(address).pathname) { throw new AppError(ErrorCode.CONTENT_CHANGED,'网站返回其他页面，请检查网址或登录状态'); }
    return response.body;
  }
  async data(path: string,ctx: CallContext): Promise<JsonNode> {
    const root = new JsonExtractor().parse(await this.text(path,ctx)); const code = siteScalar(root,'code');
    if (code === '401') { throw new AppError(ErrorCode.AUTH_REQUIRED,'此内容需要登录，请在来源网站确认权限'); }
    if (code === '403') { throw new AppError(ErrorCode.ACCESS_DENIED,'网站拒绝访问此内容'); }
    if (code === '429') { throw new AppError(ErrorCode.RATE_LIMITED,'网站限制请求频率'); }
    if (code !== '200') { throw new AppError(ErrorCode.PARSE_ERROR,'网站API未返回成功结果'); }
    const data = root.members.get('data'); if (!data || data.kind !== 'object') { throw new AppError(ErrorCode.PARSE_ERROR,'网站API数据对象缺失'); } return data;
  }
}
export function siteScalar(node: JsonNode,key: string): string { const value = node.members.get(key); return value && ['number','string'].indexOf(value.kind) >= 0 ? value.scalar : ''; }
export function siteNumber(node: JsonNode,key: string,max: number): number {
  const field = node.members.get(key); const value = Number(field?.scalar);
  if (field?.kind !== 'number' || !Number.isSafeInteger(value) || value < 0 || value > max) { throw new AppError(ErrorCode.PARSE_ERROR,'网站整数字段无效：' + key); } return value;
}
