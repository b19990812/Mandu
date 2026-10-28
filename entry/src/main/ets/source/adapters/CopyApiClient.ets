import { url } from '@kit.ArkTS';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { copyApiBase } from '../CopyAccess';
import { copyValue, copyObject, copyInteger } from './CopyApiFormat';

export interface CopyApiList { list: JsonNode[]; total: number; }
export class CopyApiClient {
  readonly site: SourceSiteAccess;
  readonly baseUrl: string;
  private readonly transport: Transport;
  private readonly policy: UrlPolicy;
  constructor(site: SourceSiteAccess,transport: Transport) {
    this.site = site; this.transport = transport; this.baseUrl = copyApiBase(site.copyApiBaseUrl);
    this.policy = new UrlPolicy([new url.URL(this.baseUrl).hostname]);
  }
  binding(operation: string): string { return JSON.stringify(['org.hsmihon.copy',2,this.site.revision,this.baseUrl,operation]); }
  async get(path: string,ctx: CallContext): Promise<JsonNode> {
    checkCall(ctx);
    if (ctx.ruleRevision !== 2) { throw new AppError(ErrorCode.CONTENT_CHANGED,'COPY API适配器版本已改变'); }
    if (!path.startsWith('/') || path.startsWith('//')) { throw new AppError(ErrorCode.RULE_INVALID,'COPY API路径无效'); }
    const address = this.policy.resolve('/api/v3' + path,this.baseUrl);
    const response = await this.transport.send({ sourceId: 'org.hsmihon.copy',url: address,responseKind: 'metadata',maxBytes: 2097152,headers: [{ name: 'Accept',value: 'application/json' }] },ctx);
    checkCall(ctx);
    if (response.statusCode === 210) { throw new AppError(ErrorCode.ACCESS_DENIED,'COPY API拒绝请求（210），请检查线路或平台'); }
    requireHttpSuccess(response);
    const final = this.policy.validate(response.finalUrl);
    if (final.pathname !== new url.URL(address).pathname) { throw new AppError(ErrorCode.POLICY_DENIED,'COPY API响应路径与请求不符'); }
    if (/^\s*</.test(response.body)) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API返回网页，请检查API线路'); }
    if (/^\s*error\s*$/i.test(response.body)) { throw new AppError(ErrorCode.ACCESS_DENIED,'COPY API返回参数或平台错误'); }
    const root = new JsonExtractor().parse(response.body); const code = copyValue(root,'code');
    if (code === '401') { throw new AppError(ErrorCode.AUTH_REQUIRED,'COPY API要求登录，当前接入仅支持匿名内容'); }
    if (code === '403' || code === '210') { throw new AppError(ErrorCode.ACCESS_DENIED,'COPY API拒绝访问此内容'); }
    if (code === '404') { throw new AppError(ErrorCode.NOT_FOUND,'COPY API作品或章节不存在'); }
    if (code !== '200') { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API未返回成功结果'); }
    return copyObject(root,'results');
  }
  list(results: JsonNode,offset: number,limit: number,maximum: number = 210000): CopyApiList {
    const total = copyInteger(results,'total',maximum); const list = results.members.get('list');
    if (!list || list.kind !== 'array' || list.items.length > limit || offset + list.items.length > total || offset + list.items.length < total && list.items.length !== limit) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API分页数量无效、缺项或没有前进'); }
    if (results.members.has('offset') && copyInteger(results,'offset',maximum) !== offset) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY API返回了错误分页位置'); }
    return { list: list.items,total: total };
  }
}
