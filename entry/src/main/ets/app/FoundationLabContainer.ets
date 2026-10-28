import { common } from '@kit.AbilityKit';
import { url } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import BuildProfile from 'BuildProfile';
import { FoundationLab } from '../diagnostic/FoundationLab';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { Transport } from '../network/Transport';
import { RcpTransport } from '../network/RcpTransport';
import { UrlPolicy } from '../network/UrlPolicy';
import { Database } from '../storage/Database';
import { FileStore } from '../storage/FileStore';
import { BundledSampleTransport } from '../source/demo/BundledSampleTransport';
import { runSourceScenario } from '../diagnostic/SourceScenario';
import { RuleSource } from '../source/rules/RuleSource';
import { htmlDemoRule, jsonDemoRule } from '../source/rules/DemoRules';
import { CallContext } from '../model/RequestTypes';
import { runRuleUpdateScenario } from '../diagnostic/RuleUpdateScenario';
import { runImageProbe } from '../diagnostic/ImageProbe';
import { runAgentProbe } from '../diagnostic/AgentProbe';

export class FoundationLabContainer {
  private readonly context: common.UIAbilityContext;
  readonly database: Database;
  readonly files: FileStore;
  readonly lab: FoundationLab;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.database = new Database(context);
    this.files = new FileStore(context.filesDir);
    this.lab = new FoundationLab(this.database, this.files);
  }

  async sourceScenario(ctx: CallContext): Promise<string> {
    const transport = new BundledSampleTransport(this.context);
    const base = 'https://fixture.invalid/';
    const policy = new UrlPolicy(['fixture.invalid']);
    const json = await runSourceScenario(new RuleSource(jsonDemoRule(), base, policy, transport), ctx);
    const html = await runSourceScenario(new RuleSource(htmlDemoRule(), base, policy, transport), ctx);
    return '本地双源通过：JSON ' + json + '；HTML ' + html;
  }

  async ruleUpdateScenario(ctx: CallContext): Promise<string> { return runRuleUpdateScenario(this.context, ctx); }
  async imageProbe(ctx: CallContext, long: boolean, progress: (text: string) => void): Promise<string> { return runImageProbe(this.context, ctx, long, progress); }
  async agentProbe(base: string, ctx: CallContext): Promise<string> { return runAgentProbe(this.context, this.fixtureBase(base), ctx); }

  fixtureBase(input: string): string {
    if (!BuildProfile.DEBUG || BuildProfile.TARGET_NAME.toString() !== 'lab') {
      throw new AppError(ErrorCode.POLICY_DENIED, '当前构建未启用开发实验室');
    }
    let parsed: url.URL;
    try { parsed = new url.URL(input.trim()); }
    catch (_) { throw new AppError(ErrorCode.POLICY_DENIED, '请输入电脑可达的服务地址'); }
    if (parsed.username || parsed.password || parsed.search || parsed.hash || parsed.pathname !== '/') {
      throw new AppError(ErrorCode.POLICY_DENIED, '仅输入协议、主机和端口，不含路径或凭据');
    }
    return parsed.origin;
  }

  fixtureTransport(base: string): Transport {
    const parsed = new url.URL(base);
    const fixtureOrigin = BuildProfile.DEBUG && BuildProfile.TARGET_NAME.toString() === 'lab' ? base : '';
    return new RcpTransport(new UrlPolicy([parsed.hostname], fixtureOrigin));
  }

  close(): void {
    try { this.database.close(); }
    catch (_) { hilog.error(0x0001, 'HSReader', 'DATABASE_CLOSE_FAILED'); }
  }
}
