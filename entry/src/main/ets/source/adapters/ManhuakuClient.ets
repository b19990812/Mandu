import { url } from '@kit.ArkTS';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { CallContext } from '../../model/RequestTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { SiteJsonClient } from './SiteJsonClient';

export class ManhuakuClient {
  readonly site: SourceSiteAccess;
  private readonly transport: Transport;
  private readonly reader: SiteJsonClient;
  constructor(site: SourceSiteAccess,transport: Transport) { this.site = site; this.transport = transport; this.reader = new SiteJsonClient(site,transport,1); }
  binding(operation: string): string { return this.reader.binding(operation); }
  text(path: string,ctx: CallContext): Promise<string> { return this.reader.text(path,ctx); }
  async data(path: string,post: boolean,ctx: CallContext): Promise<JsonNode> {
    checkCall(ctx);
    if (ctx.ruleRevision !== 1) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库适配器版本已改变'); }
    if (!(post ? /^\/comic\/[1-9][0-9]{0,18}$/ : /^\/api\/source-lines\/[1-9][0-9]{0,18}$/).test(path)) { throw new AppError(ErrorCode.RULE_INVALID,'漫画库数据接口路径无效'); }
    const policy = new UrlPolicy(this.site.allowedHosts); const address = policy.resolve(path,this.site.baseUrl);
    const response = await this.transport.send({ sourceId: this.site.sourceId,url: address,method: post ? 'POST' : 'GET',responseKind: 'metadata',maxBytes: 2097152,
      headers: [{ name: 'Accept',value: 'application/json' },{ name: 'Referer',value: this.site.baseUrl }] },ctx);
    requireHttpSuccess(response); checkCall(ctx);
    if (policy.validate(response.finalUrl).pathname !== new url.URL(address).pathname) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画库数据接口返回其他路径'); }
    const root = new JsonExtractor().parse(response.body); const code = root.members.get('code');
    if (code?.kind !== 'number' || code.scalar !== '0') { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库 API 未返回 code=0 的成功结果'); }
    const data = root.members.get('data');
    if (data?.kind !== 'object') { throw new AppError(ErrorCode.PARSE_ERROR,'漫画库 API 数据对象缺失'); } return data;
  }
}
