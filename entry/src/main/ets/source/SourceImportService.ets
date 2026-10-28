import { AppError, ErrorCode } from '../model/ErrorTypes';
import { SourceCatalog, SourcePackageStore, SourceState } from '../model/SourcePackageTypes';
import { payloadDigest } from '../storage/PayloadDigest';
import { RuleValidator } from './rules/RuleValidator';
import { ValidatedRulePackage } from './rules/RuleTypes';
import { SourceChanges } from './SourceChanges';

export interface RuleImportPreview {
  raw: string; key: string; catalogRevision: number; rule: ValidatedRulePackage;
  oldVersion: number; addedHosts: string[]; removedHosts: string[]; unchanged: boolean;
}
export interface ManagedSource { state: SourceState; rule: ValidatedRulePackage; }

export class SourceImportService {
  private readonly store: SourcePackageStore;
  private readonly validator: RuleValidator = new RuleValidator();
  constructor(store: SourcePackageStore) { this.store = store; }

  async list(includeRemoved: boolean = false): Promise<ManagedSource[]> {
    const catalog = await this.store.read(); const output: ManagedSource[] = [];
    for (let i = 0; i < catalog.entries.length; i++) {
      const state = catalog.entries[i]; if (state.removed && !includeRemoved) { continue; }
      output.push({ state: state, rule: await this.load(state.active, state.id) });
    }
    return output;
  }
  async preview(raw: string): Promise<RuleImportPreview> {
    const rule = this.validator.parse(raw); const key = await payloadDigest(raw); const catalog = await this.store.read();
    const existing = catalog.entries.find((entry: SourceState) => entry.id === rule.id);
    let oldVersion = 0; let oldHosts: string[] = [];
    if (existing) {
      const old = await this.load(existing.active, existing.id); oldVersion = old.sourceVersion; oldHosts = old.allowedHosts;
      const sameVersion = existing.versions.find((entry) => entry.version === rule.sourceVersion);
      if (sameVersion && sameVersion.key !== key) { throw new AppError(ErrorCode.CONFLICT, '同版本内容不同，请增加sourceVersion'); }
      if (key !== existing.active && rule.sourceVersion <= oldVersion) { throw new AppError(ErrorCode.CONFLICT, '更新必须提高版本，降版请使用显式回滚'); }
      if (!sameVersion && existing.versions.length >= 32) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '该源已保留32个版本，请先导出备份再整理'); }
    } else if (catalog.entries.length >= 64) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '源记录最多64项'); }
    return { raw: raw, key: key, catalogRevision: catalog.revision, rule: rule, oldVersion: oldVersion,
      addedHosts: rule.allowedHosts.filter((host: string) => oldHosts.indexOf(host) < 0),
      removedHosts: oldHosts.filter((host: string) => rule.allowedHosts.indexOf(host) < 0),
      unchanged: existing !== undefined && existing.active === key && !existing.removed };
  }
  async activate(preview: RuleImportPreview): Promise<void> {
    // Re-parse raw payload; never trust a mutable view-model preview object.
    const checked = await this.preview(preview.raw);
    if (checked.key !== preview.key || checked.catalogRevision !== preview.catalogRevision) { throw new AppError(ErrorCode.CONFLICT, '预览已过期，请重新校验'); }
    if (checked.unchanged) { return; }
    const catalog = await this.store.read();
    if (catalog.revision !== checked.catalogRevision) { throw new AppError(ErrorCode.CONFLICT, '源规则已改变，请重新预览'); }
    const previous = catalog.entries.find((entry: SourceState) => entry.id === checked.rule.id);
    const versions = previous ? previous.versions.slice() : [];
    if (!versions.some((item) => item.key === checked.key)) { versions.push({ version: checked.rule.sourceVersion, key: checked.key }); }
    const next: SourceState = { id: checked.rule.id, active: checked.key,
      lastGood: previous && previous.active !== checked.key ? previous.active : previous ? previous.lastGood : '',
      revision: previous ? previous.revision + 1 : 1, enabled: previous && !previous.removed ? previous.enabled : true,
      removed: false, versions: versions };
    await this.replace(catalog, next, checked.raw, checked.key);
  }
  async setEnabled(id: string, enabled: boolean, expectedRevision: number): Promise<void> {
    const catalog = await this.store.read(); const previous = this.current(catalog, id, expectedRevision);
    if (previous.removed) { throw new AppError(ErrorCode.DISABLED, '已移除的源需重新导入'); }
    if (previous.enabled === enabled) { return; }
    const next = this.copy(previous); next.enabled = enabled; next.revision++;
    await this.replace(catalog, next);
  }
  async remove(id: string, expectedRevision: number): Promise<void> {
    const catalog = await this.store.read(); const previous = this.current(catalog, id, expectedRevision);
    const next = this.copy(previous); next.enabled = false; next.removed = true; next.revision++;
    await this.replace(catalog, next);
  }
  async rollback(id: string, expectedRevision: number): Promise<void> {
    const catalog = await this.store.read(); const previous = this.current(catalog, id, expectedRevision);
    if (previous.removed || previous.lastGood === '') { throw new AppError(ErrorCode.CONFLICT, '没有可回滚的上一版本'); }
    await this.load(previous.lastGood, id);
    const next = this.copy(previous); next.active = previous.lastGood; next.lastGood = previous.active; next.revision++;
    await this.replace(catalog, next);
  }
  async load(key: string, id: string): Promise<ValidatedRulePackage> {
    const rule = this.validator.parse(await this.store.payload(key));
    if (rule.id !== id) { throw new AppError(ErrorCode.CORRUPT_FILE, '规则文件与源身份不匹配'); }
    return rule;
  }
  private current(catalog: SourceCatalog, id: string, revision: number): SourceState {
    const entry = catalog.entries.find((item: SourceState) => item.id === id);
    if (!entry || entry.revision !== revision) { throw new AppError(ErrorCode.CONFLICT, '源状态已改变，请重新读取'); }
    return entry;
  }
  private copy(entry: SourceState): SourceState { return { id: entry.id, active: entry.active, lastGood: entry.lastGood,
    revision: entry.revision, enabled: entry.enabled, removed: entry.removed, versions: entry.versions.slice() }; }
  private async replace(catalog: SourceCatalog, entry: SourceState, raw: string = '', key: string = ''): Promise<void> {
    const entries = catalog.entries.filter((item: SourceState) => item.id !== entry.id); entries.push(entry);
    await this.store.commit({ schemaVersion: 1, revision: catalog.revision + 1, entries: entries }, catalog.revision, raw, key);
    SourceChanges.publish(entry);
  }
}
