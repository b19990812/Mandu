import { url } from '@kit.ArkTS';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { RcpTransport } from '../network/RcpTransport';
import { UrlPolicy } from '../network/UrlPolicy';
import { SourceImportService, RuleImportPreview } from './SourceImportService';
import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkCall, requireHttpSuccess } from './SourceHttp';

export interface RuleSubscription { sourceId: string; address: string; }
export class RuleSubscriptionService {
  private readonly db: ReaderDatabase;
  private readonly imports: SourceImportService;
  constructor(db: ReaderDatabase,imports: SourceImportService) { this.db = db; this.imports = imports; }
  private policy(address: string): UrlPolicy {
    let parsed: url.URL;
    try { parsed = new url.URL(address); } catch (_) { throw new AppError(ErrorCode.CONFIG_INVALID,'订阅网址无效'); }
    const policy = new UrlPolicy([parsed.hostname]); policy.validate(address); return policy;
  }
  async list(): Promise<RuleSubscription[]> { return this.db.read((db) => db.rows("SELECT substr(key,19),value FROM reader_settings WHERE key LIKE 'rule.subscription.%' ORDER BY key",[],(row): RuleSubscription => ({ sourceId: row.getString(0),address: row.getString(1) }))); }
  async fetch(address: string,expectedId: string,digest: string,ctx: CallContext): Promise<RuleImportPreview> {
    if (digest && !/^[a-fA-F0-9]{64}$/.test(digest)) { throw new AppError(ErrorCode.CONFIG_INVALID,'SHA256 必须为64位十六进制'); }
    const transport = new RcpTransport(this.policy(address));
    const response = await transport.send({ sourceId: 'rule-subscription',url: address,headers: [],maxBytes: 262144,responseKind: 'metadata' },ctx);
    requireHttpSuccess(response); checkCall(ctx);
    const preview = await this.imports.preview(response.body); checkCall(ctx);
    if (expectedId && preview.rule.id !== expectedId) { throw new AppError(ErrorCode.CONTENT_CHANGED,'订阅返回了不同源身份，拒绝更新'); }
    if (digest && preview.key.toLowerCase() !== digest.toLowerCase()) { throw new AppError(ErrorCode.CORRUPT_FILE,'规则摘要不匹配'); }
    return preview;
  }
  async remember(sourceId: string,address: string): Promise<void> {
    this.policy(address);
    await this.db.transaction((db) => db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['rule.subscription.' + sourceId,address]));
  }
  async remove(sourceId: string): Promise<void> { await this.db.transaction((db) => db.run('DELETE FROM reader_settings WHERE key=?',['rule.subscription.' + sourceId])); }
}

