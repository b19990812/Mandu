import { UpdateDownloads } from '../model/UpdateDownloads';
import { common } from '@kit.AbilityKit';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { CatalogRepository } from '../storage/CatalogRepository';
import { SourceRepository } from '../storage/SourceRepository';
import { SourceSiteSettingsRepository } from '../storage/SourceSiteSettingsRepository';
import { SourceSiteService } from '../source/SourceSiteService';
import { SourceRegistry } from '../source/SourceRegistry';
import { NativeSourceRegistry } from '../source/NativeSourceRegistry';
import { ValidatedRulePackage } from '../source/rules/RuleTypes';
import { BundledSampleTransport } from '../source/demo/BundledSampleTransport';
import { RcpTransport } from '../network/RcpTransport';
import { UrlPolicy } from '../network/UrlPolicy';
import { CatalogService } from './CatalogService';
import { LibraryUpdateService } from './LibraryUpdateService';
import { UpdatePolicyRepository } from '../storage/UpdatePolicyRepository';
import { DownloadRepository } from '../storage/DownloadRepository';

class DeferredDownloads implements UpdateDownloads {
  private readonly registry: SourceRegistry;
  private readonly catalog: CatalogRepository;
  private readonly records: DownloadRepository;
  constructor(registry: SourceRegistry,catalog: CatalogRepository,records: DownloadRepository) { this.registry = registry; this.catalog = catalog; this.records = records; }
  async enqueue(id: string): Promise<void> {
    const chapter = await this.catalog.chapter(id); if (!chapter) { return; }
    const source = await this.registry.open(chapter.ref.sourceId);
    await this.records.enqueue(chapter,source.snapshotKey);
  }
}
// Extension uses only Context-compatible storage/network services; no UIAbilityContext cast or background-transfer lease.
export function updateRuntime(context: common.Context): LibraryUpdateService {
  const db = ReaderDatabase.shared(context);
  const sites = new SourceSiteService(new SourceSiteSettingsRepository(context));
  const native = new NativeSourceRegistry(context,sites);
  const registry = new SourceRegistry(new SourceRepository(context),(rule: ValidatedRulePackage) => {
    if (rule.baseUrl === 'https://fixture.invalid/' && rule.allowedHosts.length === 1 && rule.allowedHosts[0] === 'fixture.invalid') { return new BundledSampleTransport(context); }
    return new RcpTransport(new UrlPolicy(rule.allowedHosts));
  },native);
  const catalog = new CatalogRepository(db);
  return new LibraryUpdateService(catalog,new CatalogService(registry,catalog),new DeferredDownloads(registry,catalog,new DownloadRepository(db)),new UpdatePolicyRepository(db));
}
