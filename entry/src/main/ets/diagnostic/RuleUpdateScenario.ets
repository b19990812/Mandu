import { common } from '@kit.AbilityKit';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { SourceState } from '../model/SourcePackageTypes';
import { ByteSink } from '../model/ByteSink';
import { RequestPlan, Transport, TransportResponse } from '../network/Transport';
import { SourceImportService } from '../source/SourceImportService';
import { SourceRegistry } from '../source/SourceRegistry';
import { BundledSampleTransport } from '../source/demo/BundledSampleTransport';
import { SourceRepository } from '../storage/SourceRepository';
import { RuleFilePicker } from '../storage/RuleFilePicker';
import { DemoSiteRepository } from '../storage/DemoSiteRepository';
import { runSourceScenario } from './SourceScenario';

class HeldTransport implements Transport {
  private readonly delegate: Transport;
  readonly entered: Promise<void>;
  private enter: () => void = () => {};
  private release: () => void = () => {};
  private readonly gate: Promise<void>;
  constructor(delegate: Transport) {
    this.delegate = delegate; this.entered = new Promise<void>((resolve) => { this.enter = resolve; });
    this.gate = new Promise<void>((resolve) => { this.release = resolve; });
  }
  async send(plan: RequestPlan, ctx: CallContext): Promise<TransportResponse> {
    const result = await this.delegate.send(plan, ctx); this.enter(); await this.gate; return result;
  }
  streamToFile(plan: RequestPlan, ctx: CallContext, sink: ByteSink): Promise<TransportResponse> { return this.delegate.streamToFile(plan, ctx, sink); }
  resume(): void { this.release(); }
}

export async function runRuleUpdateScenario(context: common.UIAbilityContext, ctx: CallContext): Promise<string> {
  const store = new SourceRepository(context); const imports = new SourceImportService(store);
  const files = new RuleFilePicker(context); const site = new DemoSiteRepository(context); const originalSite = site.revision();
  const ids: string[] = [];
  const call = (version: number): CallContext => ({ callId: ctx.callId, cancel: ctx.cancel, deadlineMs: ctx.deadlineMs, ruleRevision: version });
  try {
    for (let formatIndex = 0; formatIndex < 2; formatIndex++) {
      const format = formatIndex === 0 ? 'json' : 'html'; const id = 'org.example.lab.update.' + format; ids.push(id);
      const v1 = files.sample(format + '-v1.json').replace('org.example.demo.' + format, id);
      const v2 = files.sample(format + '-v2.json').replace('org.example.demo.' + format, id);
      let existing = (await store.read()).entries.find((item: SourceState) => item.id === id);
      if (existing && (await imports.load(existing.active, id)).sourceVersion === 2) { await imports.rollback(id, existing.revision); }
      await imports.activate(await imports.preview(v1)); await site.setRevision(1);
      const transport = new BundledSampleTransport(context, () => site.revision());
      const registry = new SourceRegistry(store, () => transport);
      const before = await registry.open(id); await runSourceScenario(before.source, call(1));
      await site.setRevision(2);
      let changedFailed = false;
      try { await before.source.search('', undefined, call(1)); }
      catch (error) { changedFailed = error instanceof AppError && [ErrorCode.PARSE_ERROR, ErrorCode.EMPTY_UNEXPECTED].indexOf(error.code) >= 0; }
      if (!changedFailed) { throw new AppError(ErrorCode.PARSE_ERROR, '旧规则没有识别样本改版'); }
      await imports.activate(await imports.preview(v2)); const fixed = await registry.open(id);
      await runSourceScenario(fixed.source, call(2));
      const active = (await store.read()).entries.find((item: SourceState) => item.id === id)!.active;
      let invalidFailed = false;
      try { await imports.preview(v2.replace('"sourceVersion": 2', '"sourceVersion": 3').replace('"name":', '"script":"unsupported","name":')); }
      catch (error) { invalidFailed = error instanceof AppError && error.code === ErrorCode.RULE_INVALID; }
      if (!invalidFailed || (await store.read()).entries.find((item: SourceState) => item.id === id)!.active !== active) {
        throw new AppError(ErrorCode.CONFLICT, '坏规则未能保留当前版本');
      }
      const held = new HeldTransport(transport); const slowRegistry = new SourceRegistry(store, () => held);
      const slow = await slowRegistry.open(id);
      const pending = slow.source.search('', undefined, call(2)); await held.entered;
      try {
        existing = (await store.read()).entries.find((item: SourceState) => item.id === id)!;
        await imports.rollback(id, existing.revision);
      } finally { held.resume(); }
      let staleFailed = false;
      try { await pending; } catch (error) { staleFailed = error instanceof AppError && error.code === ErrorCode.CONTENT_CHANGED; }
      if (!staleFailed) { throw new AppError(ErrorCode.CONTENT_CHANGED, '旧请求结果没有被隔离'); }
      await site.setRevision(1); const reverted = await registry.open(id); await runSourceScenario(reverted.source, call(1));
      const reopened = new SourceImportService(new SourceRepository(context));
      if ((await reopened.list()).find((item) => item.state.id === id)!.rule.sourceVersion !== 1) { throw new AppError(ErrorCode.IO_ERROR, '重开存储未保留回滚版本'); }
    }
    return 'JSON/HTML更新回滚通过；非法v3保留旧版；旧请求隔离通过；重开存储通过';
  } finally {
    await site.setRevision(originalSite);
    for (let i = 0; i < ids.length; i++) {
      const entry = (await store.read()).entries.find((item: SourceState) => item.id === ids[i]);
      if (entry && !entry.removed) { await imports.remove(entry.id, entry.revision); }
    }
  }
}
