import { common } from '@kit.AbilityKit';
import { url } from '@kit.ArkTS';
import { SourceState } from '../model/SourcePackageTypes';
import { SourceSiteAccess } from '../model/SourceSiteTypes';
import { Source } from '../model/SourceTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { FileStore } from '../storage/FileStore';
import { payloadDigest } from '../storage/PayloadDigest';
import { JsonExtractor } from '../parsing/JsonExtractor';
import { UrlPolicy } from '../network/UrlPolicy';
import { RcpTransport } from '../network/RcpTransport';
import { SourceSiteService } from './SourceSiteService';
import { ManagedSource } from './SourceImportService';
import { SourceHandle, NativeSourceResolver, RegisteredSource, RegistryTransport } from './SourceRegistry';
import { SourceChanges } from './SourceChanges';
import { sourceSiteDefinitions } from './SourceSiteCatalog';
import { createNativeSource, nativeHosts } from './NativeSourceFactory';
import { usesCopyApi, nativeAdapterVersion, nativeSnapshot, copyApiBase } from './CopyAccess';

interface NativeStatus { enabled: boolean; epoch: number; }
export class NativeSourceRegistry implements NativeSourceResolver {
  private static tail: Promise<void> = Promise.resolve();
  private readonly sites: SourceSiteService; private readonly db: ReaderDatabase; private readonly files: FileStore;
  constructor(context: common.Context,sites: SourceSiteService) { this.sites = sites; this.db = ReaderDatabase.shared(context); this.files = new FileStore(context.filesDir,'native_versions'); }
  owns(id: string): boolean { return sourceSiteDefinitions().some((site) => site.sourceId === id); }
  private async status(id: string): Promise<NativeStatus> {
    return this.db.read(async (db) => {
      const values = await db.rows('SELECT key,value FROM reader_settings WHERE key IN(?,?)',['native.' + id + '.enabled','native.' + id + '.epoch'],(row): string[] => [row.getString(0),row.getString(1)]);
      const result: NativeStatus = { enabled: id === 'org.hsmihon.baozi' || id === 'org.hsmihon.copy',epoch: 0 }; values.forEach((value: string[]) => { if (value[0].endsWith('.enabled')) { result.enabled = value[1] === 'true'; } else { result.epoch = Number(value[1]); } });
      if (!Number.isSafeInteger(result.epoch) || result.epoch < 0 || result.epoch >= 1000000000) { throw new AppError(ErrorCode.CONFIG_INVALID,'内置源状态异常'); } return result;
    });
  }
  private revision(site: SourceSiteAccess,status: NativeStatus): number { return site.revision * 1000000000 + status.epoch; }
  private async descriptor(id: string): Promise<ManagedSource> {
    if (!this.owns(id)) { throw new AppError(ErrorCode.NOT_FOUND,'内置源不存在'); }
    const site = await this.sites.access(id); const status = await this.status(id);
    const version = nativeAdapterVersion(site);
    const raw = nativeSnapshot(site); const key = await payloadDigest(raw);
    const before = NativeSourceRegistry.tail; let release: () => void = () => {}; NativeSourceRegistry.tail = new Promise<void>((resolve) => { release = resolve; }); await before;
    try { const previous = this.files.readText(key,4096); if (previous === undefined) { await this.files.writeText(key,raw); } else if (previous !== raw) { throw new AppError(ErrorCode.CORRUPT_FILE,'内置源版本摘要不符'); } } finally { release(); }
    const hosts = nativeHosts(site);
    const name = sourceSiteDefinitions().find((definition) => definition.sourceId === id)!.name;
    const state: SourceState = { id: id,active: key,lastGood: '',revision: this.revision(site,status),enabled: status.enabled,removed: false,versions: [{ version: version,key: key }] };
    return { state: state,rule: { id: id,name: name,sourceVersion: version,ruleFormatVersion: 1,engineMin: 1,engineMax: 1,baseUrl: site.baseUrl,allowedHosts: hosts,capabilities: ['search','details','chapters','pages','discover'],definition: { id: id,version: version,format: 'native',operations: [],imageHeaders: [{ name: 'Referer',value: site.baseUrl }] } } };
  }
  async list(): Promise<ManagedSource[]> { const output: ManagedSource[] = []; const definitions = sourceSiteDefinitions(); for (let i = 0; i < definitions.length; i++) { output.push(await this.descriptor(definitions[i].sourceId)); } return output; }
  async open(id: string,key?: string): Promise<SourceHandle> {
    const entry = await this.descriptor(id); if (!entry.state.enabled) { throw new AppError(ErrorCode.DISABLED,'内置源已禁用'); }
    if (key && key !== entry.state.active) { throw new AppError(ErrorCode.CONTENT_CHANGED,'内置源版本或网址已改变，旧任务请取消后重新入队'); }
    if (key) { const raw = this.files.readText(key,4096); if (!raw || await payloadDigest(raw) !== key || new JsonExtractor().parse(raw).members.get('id')?.scalar !== id) { throw new AppError(ErrorCode.CORRUPT_FILE,'内置源固定快照无效'); } }
    const site = await this.sites.access(id); const guard = async (): Promise<void> => this.assertCurrent(id,entry.state.revision);
    const api = usesCopyApi(site);
    const transport = new RegistryTransport(new RcpTransport(new UrlPolicy(entry.rule.allowedHosts),api,true,api ? new url.URL(copyApiBase(site.copyApiBaseUrl)).origin : ''),entry.state,guard,key !== undefined);
    const adapter: Source = createNativeSource(site,transport);
    await guard(); return { source: new RegisteredSource(adapter,entry.state,guard),rule: entry.rule,revision: entry.state.revision,snapshotKey: entry.state.active,transport: transport };
  }
  async assertCurrent(id: string,revision: number): Promise<void> {
    const site = await this.sites.access(id); const status = await this.status(id); if (!status.enabled) { throw new AppError(ErrorCode.DISABLED,'该源已禁用'); }
    if (revision !== this.revision(site,status)) { throw new AppError(ErrorCode.CONTENT_CHANGED,'源网址或状态已改变，旧结果已丢弃'); }
  }
  async setEnabled(id: string,enabled: boolean,expected: number): Promise<void> {
    if (!this.owns(id)) { throw new AppError(ErrorCode.NOT_FOUND,'内置源不存在'); } const site = await this.sites.access(id);
    await this.db.transaction(async (db) => {
      const rows = await db.rows('SELECT value FROM reader_settings WHERE key=?',['native.' + id + '.epoch'],(row) => row.getString(0)); const epoch = rows.length ? Number(rows[0]) : 0;
      if (expected !== site.revision * 1000000000 + epoch || epoch >= 999999998) { throw new AppError(ErrorCode.CONFLICT,'源状态已改变，请重新读取'); }
      await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['native.' + id + '.enabled',enabled.toString()]);
      await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',['native.' + id + '.epoch',(epoch + 1).toString()]);
    });
    SourceChanges.publish((await this.descriptor(id)).state);
  }
}
