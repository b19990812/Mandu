import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FoundationLabContainer } from '../app/FoundationLabContainer';
import { CancelScope } from '../model/CancelScope';
import { AppError } from '../model/ErrorTypes';
import { CallContext } from '../network/Transport';
import { archiveProbe } from '../diagnostic/ArchiveProbe';
import { ReaderTrace, ReaderTraceEntry } from '../diagnostic/ReaderTrace';

@Observed
export class DebugLabVM {
  baseUrl: string = 'http://127.0.0.1:8765';
  status: string = '使用电脑局域网地址；127.0.0.1 仅在已配置端口转发时有效。';
  traceQuery: string = '';
  traceRows: ReaderTraceEntry[] = [];
  traceTotal: number = 0;
  busy: boolean = false;
  private container?: FoundationLabContainer;
  private scope?: CancelScope;
  private generation: number = 0;
  private disposed: boolean = false;
  private context?: common.UIAbilityContext;

  initialize(context: common.UIAbilityContext): void {
    this.disposed = false;
    this.context = context;
    ReaderTrace.initialize(context.filesDir);
    ReaderTrace.loadPersisted();
    this.searchReaderLogs();
    try { this.container = new FoundationLabContainer(context); }
    catch (_) {
      hilog.error(0x0001, 'HSReader', 'LAB_INIT_FAILED');
      this.status = 'IO_ERROR：无法打开应用私有目录，请检查存储状态';
    }
  }

  private async run(action: (container: FoundationLabContainer, ctx: CallContext) => Promise<string>, timeoutMs: number): Promise<void> {
    if (this.busy || !this.container || this.disposed) { return; }
    const current = ++this.generation;
    const container = this.container;
    const scope = new CancelScope();
    this.scope = scope;
    this.busy = true;
    this.status = '执行中…';
    const ctx: CallContext = {
      callId: 'probe-' + current.toString(), deadlineMs: Date.now() + timeoutMs, cancel: scope, ruleRevision: 1
    };
    try {
      const message = await action(container, ctx);
      if (!this.disposed && current === this.generation && !scope.cancelled) { this.status = message; }
    } catch (error) {
      hilog.error(0x0001, 'HSReader', 'call=%{public}s code=%{public}s', ctx.callId,
        error instanceof AppError ? error.code : 'SYSTEM_ERROR');
      if (!this.disposed && current === this.generation) {
        this.status = error instanceof AppError ? error.code + '：' + error.message : 'SYSTEM_ERROR：系统操作失败，详见设备日志';
      }
    } finally {
      if (current === this.generation) { this.busy = false; this.scope = undefined; }
      if (this.disposed) { container.close(); }
    }
  }

  readStorage(): void { this.run((container: FoundationLabContainer) => container.lab.readStorage(), 30000); }
  parserProbe(): void { this.run((container: FoundationLabContainer) => container.lab.parserProbe(), 30000); }
  archiveProbe(): void { const context = this.context; if (context) { this.run(async () => archiveProbe(context),30000); } }
  sourceScenario(): void {
    this.run((container: FoundationLabContainer, ctx: CallContext) => container.sourceScenario(ctx), 30000);
  }
  ruleUpdateScenario(): void { this.run((container: FoundationLabContainer, ctx: CallContext) => container.ruleUpdateScenario(ctx), 60000); }
  imageProbe(long: boolean): void {
    this.run((container: FoundationLabContainer, ctx: CallContext) => container.imageProbe(ctx, long, (message: string) => {
      if (!this.disposed && !ctx.cancel.cancelled) { this.status = message; }
    }), long ? 180000 : 60000);
  }
  writeStorage(): void { this.run((container: FoundationLabContainer) => container.lab.writeStorage(), 30000); }
  agentProbe(): void { this.run((container: FoundationLabContainer, ctx: CallContext) => container.agentProbe(this.baseUrl, ctx), 45000); }

  searchReaderLogs(): void {
    this.traceRows = ReaderTrace.query(this.traceQuery,150);
    this.traceTotal = ReaderTrace.total();
  }
  async clearReaderLogs(): Promise<void> { await ReaderTrace.clear(); this.searchReaderLogs(); }

  request(path: string = '/health', timeoutMs: number = 30000): void {
    this.run((container: FoundationLabContainer, ctx: CallContext) => {
      const base = container.fixtureBase(this.baseUrl);
      return container.lab.request(base, path, container.fixtureTransport(base), ctx);
    }, timeoutMs);
  }

  stream(): void {
    this.run((container: FoundationLabContainer, ctx: CallContext) => {
      const base = container.fixtureBase(this.baseUrl);
      return container.lab.stream(base, container.fixtureTransport(base), ctx);
    }, 30000);
  }

  cancel(): void {
    if (this.scope) { this.scope.cancel(); }
    this.status = '已请求取消；等待资源释放';
  }

  dispose(): void {
    this.disposed = true;
    if (this.scope) { this.scope.cancel(); }
    if (!this.busy && this.container) { this.container.close(); }
  }
}
