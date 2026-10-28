import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { SourceCatalog, SourcePackageStore, SourceState, SourceVersionKey } from '../model/SourcePackageTypes';
import { JsonExtractor, JsonNode } from '../parsing/JsonExtractor';
import { FileStore } from './FileStore';
import { payloadDigest } from './PayloadDigest';

// Immutable, content-addressed rule files + one atomic catalog pointer file.
// The explicit queue serializes commits from all repository instances in this process.
export class SourceRepository implements SourcePackageStore {
  private static tail: Promise<void> = Promise.resolve();
  private readonly files: FileStore;
  constructor(context: common.Context) { this.files = new FileStore(context.filesDir, 'source_rules'); }

  async read(): Promise<SourceCatalog> {
    const text = this.files.readText('catalog', 524288);
    return text === undefined ? { schemaVersion: 1, revision: 0, entries: [] } : this.decode(text);
  }

  async payload(key: string): Promise<string> {
    if (!/^[a-f0-9]{64}$/.test(key)) { throw new AppError(ErrorCode.CONFIG_INVALID, '规则文件标识无效'); }
    const text = this.files.readText(key, 262144);
    if (text === undefined || await payloadDigest(text) !== key) { throw new AppError(ErrorCode.CORRUPT_FILE, '规则文件缺失或摘要不符，未修改现有记录'); }
    return text;
  }

  async commit(next: SourceCatalog, expectedRevision: number, payload: string, key: string): Promise<void> {
    const previous = SourceRepository.tail;
    let release: () => void = () => {};
    SourceRepository.tail = new Promise<void>((resolve) => { release = resolve; });
    await previous;
    try {
      const current = await this.read();
      if (current.revision !== expectedRevision || next.revision !== expectedRevision + 1) { throw new AppError(ErrorCode.CONFLICT, '源规则已改变，请重新预览'); }
      const encoded = this.encode(next); this.decode(encoded);
      if (payload !== '') {
        if (await payloadDigest(payload) !== key) { throw new AppError(ErrorCode.CORRUPT_FILE, '暂存规则摘要不符'); }
        const old = this.files.readText(key, 262144);
        if (old !== undefined && old !== payload) { throw new AppError(ErrorCode.CORRUPT_FILE, '同一摘要已存在不同内容，拒绝覆盖'); }
        if (old === undefined) { await this.write(key, payload); }
      }
      // Only the final rename changes the active catalog. Failed writes leave the old catalog.
      await this.write('catalog', encoded);
    } catch (error) {
      if (error instanceof AppError) { throw error; }
      throw new AppError(ErrorCode.IO_ERROR, '规则保存未完成，原生效记录已保留');
    } finally { release(); }
  }

  private async write(key: string, text: string): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(text);
    await this.files.writeStream(key, async (sink) => { await sink.write(bytes.buffer as ArrayBuffer); });
  }
  private encode(catalog: SourceCatalog): string {
    // Literal protocol keys are independent of Release property obfuscation.
    const entries = catalog.entries.map((entry: SourceState): string =>
      '{"id":' + JSON.stringify(entry.id) + ',"active":' + JSON.stringify(entry.active) + ',"lastGood":' + JSON.stringify(entry.lastGood) +
      ',"revision":' + entry.revision.toString() + ',"enabled":' + entry.enabled.toString() + ',"removed":' + entry.removed.toString() +
      ',"versions":[' + entry.versions.map((item: SourceVersionKey): string => '{"version":' + item.version.toString() + ',"key":' + JSON.stringify(item.key) + '}').join(',') + ']}');
    return '{"schemaVersion":1,"revision":' + catalog.revision.toString() + ',"entries":[' + entries.join(',') + ']}';
  }
  private decode(text: string): SourceCatalog {
    try {
      const parser = new JsonExtractor(); const root = parser.parse(text);
      this.keys(root, ['schemaVersion', 'revision', 'entries']);
      if (this.number(root, 'schemaVersion') !== 1) { throw new AppError(ErrorCode.DATABASE_VERSION, '源规则索引版本不兼容，原数据保留'); }
      const revision = this.number(root, 'revision'); const array = root.members.get('entries');
      if (!array || array.kind !== 'array' || array.items.length > 64) { this.invalid(); }
      const ids: Set<string> = new Set();
      const entries = array.items.map((node: JsonNode): SourceState => {
        this.keys(node, ['id', 'active', 'lastGood', 'revision', 'enabled', 'removed', 'versions']);
        const id = this.string(node, 'id'); if (!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(id) || ids.has(id)) { this.invalid(); } ids.add(id);
        const active = this.string(node, 'active'); const lastGood = this.string(node, 'lastGood');
        const versionNodes = node.members.get('versions');
        if (!versionNodes || versionNodes.kind !== 'array' || versionNodes.items.length < 1 || versionNodes.items.length > 32) { this.invalid(); }
        const seen: Set<number> = new Set(); const hashes: Set<string> = new Set();
        const versions = versionNodes.items.map((v: JsonNode): SourceVersionKey => {
          this.keys(v, ['version', 'key']); const version = this.number(v, 'version'); const key = this.string(v, 'key');
          if (version < 1 || version > 2147483647 || seen.has(version) || hashes.has(key) || !/^[a-f0-9]{64}$/.test(key)) { this.invalid(); }
          seen.add(version); hashes.add(key); return { version: version, key: key };
        });
        const entryRevision = this.number(node, 'revision'); const enabled = this.boolean(node, 'enabled'); const removed = this.boolean(node, 'removed');
        if (!hashes.has(active) || lastGood !== '' && !hashes.has(lastGood) || lastGood === active || entryRevision < 1 || entryRevision > revision || removed && enabled) { this.invalid(); }
        return { id: id, active: active, lastGood: lastGood, revision: entryRevision, enabled: enabled, removed: removed, versions: versions };
      });
      return { schemaVersion: 1, revision: revision, entries: entries };
    } catch (error) {
      if (error instanceof AppError && error.code === ErrorCode.DATABASE_VERSION) { throw error; }
      return this.invalid();
    }
  }
  private keys(node: JsonNode, keys: string[]): void {
    if (node.kind !== 'object' || node.members.size !== keys.length || keys.some((key: string) => !node.members.has(key))) { this.invalid(); }
  }
  private string(node: JsonNode, key: string): string { const v = node.members.get(key); if (!v || v.kind !== 'string') { return this.invalid(); } return v.scalar; }
  private number(node: JsonNode, key: string): number {
    const v = node.members.get(key); if (!v || v.kind !== 'number' || !/^(0|[1-9][0-9]*)$/.test(v.scalar) || !Number.isSafeInteger(Number(v.scalar))) { return this.invalid(); } return Number(v.scalar);
  }
  private boolean(node: JsonNode, key: string): boolean { const v = node.members.get(key); if (!v || v.kind !== 'boolean') { return this.invalid(); } return v.scalar === 'true'; }
  private invalid(): never { throw new AppError(ErrorCode.CONFIG_INVALID, '源规则索引异常，原数据已保留'); }
}
