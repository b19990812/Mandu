import { RuleSubscriptionService } from '../source/RuleSubscriptionService';
import { ExtensionRepositoryService } from '../source/ExtensionRepositoryService';
import { LibraryUpdateService } from '../business/LibraryUpdateService';
import { UpdatePolicyRepository } from '../storage/UpdatePolicyRepository';
import { common } from '@kit.AbilityKit';
import { SourceSiteService } from '../source/SourceSiteService';
import { SourceSiteSettingsRepository } from '../storage/SourceSiteSettingsRepository';
import { ChapterReaderService } from '../business/ChapterReaderService';
import { SourceRepository } from '../storage/SourceRepository';
import { SourceImportService } from '../source/SourceImportService';
import { SourceRegistry } from '../source/SourceRegistry';
import { DemoSiteRepository } from '../storage/DemoSiteRepository';
import { RcpTransport } from '../network/RcpTransport';
import { UrlPolicy } from '../network/UrlPolicy';
import { BundledSampleTransport } from '../source/demo/BundledSampleTransport';
import { ValidatedRulePackage } from '../source/rules/RuleTypes';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { CatalogRepository } from '../storage/CatalogRepository';
import { LibraryRepository } from '../storage/LibraryRepository';
import { ProgressRepository } from '../storage/ProgressRepository';
import { CatalogService } from '../business/CatalogService';
import { ReaderService } from '../business/ReaderService';
import { DownloadRepository } from '../storage/DownloadRepository';
import { DownloadCoordinator } from '../download/DownloadCoordinator';
import { ReaderPreferencesRepository } from '../storage/ReaderPreferencesRepository';
import { NativeSourceRegistry } from '../source/NativeSourceRegistry';
import { ManagedSource } from '../source/SourceImportService';
import { TrialPositionRepository } from '../storage/TrialPositionRepository';
import { ReaderTrace } from '../diagnostic/ReaderTrace';

// Production composition remains independent of the development laboratory.
export class AppContainer {
  readonly extensionRepositories: ExtensionRepositoryService;
  readonly subscriptions: RuleSubscriptionService;
  readonly updatePolicy: UpdatePolicyRepository;
  readonly libraryUpdates: LibraryUpdateService;
  readonly sourceSites: SourceSiteService;
  readonly reader: ChapterReaderService;
  readonly imports: SourceImportService;
  readonly registry: SourceRegistry;
  readonly demoSite: DemoSiteRepository;
  readonly catalog: CatalogRepository;
  readonly library: LibraryRepository;
  readonly progress: ProgressRepository;
  readonly catalogService: CatalogService;
  readonly bookReader: ReaderService;
  readonly downloadRecords: DownloadRepository;
  readonly downloads: DownloadCoordinator;
  readonly preferences: ReaderPreferencesRepository;
  readonly nativeSources: NativeSourceRegistry;
  readonly trialPositions: TrialPositionRepository;

  constructor(context: common.UIAbilityContext) {
    ReaderTrace.initialize(context.filesDir);
    this.sourceSites = new SourceSiteService(new SourceSiteSettingsRepository(context));
    const packages = new SourceRepository(context);
    this.imports = new SourceImportService(packages);
    this.demoSite = new DemoSiteRepository(context);
    this.nativeSources = new NativeSourceRegistry(context,this.sourceSites);
    this.registry = new SourceRegistry(packages, (rule: ValidatedRulePackage) => {
      if (rule.baseUrl === 'https://fixture.invalid/' && rule.allowedHosts.length === 1 && rule.allowedHosts[0] === 'fixture.invalid') {
        return new BundledSampleTransport(context, () => this.demoSite.revision());
      }
      return new RcpTransport(new UrlPolicy(rule.allowedHosts));
    },this.nativeSources);
    this.reader = new ChapterReaderService(this.sourceSites,context,this.registry);
    const database = ReaderDatabase.shared(context);
    this.extensionRepositories = new ExtensionRepositoryService(database);
    this.subscriptions = new RuleSubscriptionService(database,this.imports);
    this.trialPositions = new TrialPositionRepository(database);
    this.preferences = new ReaderPreferencesRepository(database);
    this.catalog = new CatalogRepository(database);
    this.library = new LibraryRepository(database);
    this.progress = new ProgressRepository(database, this.catalog);
    this.catalogService = new CatalogService(this.registry, this.catalog);
    this.downloadRecords = new DownloadRepository(database);
    this.downloads = DownloadCoordinator.shared(context, this.registry, this.catalog, this.downloadRecords);
    this.updatePolicy = new UpdatePolicyRepository(database);
    this.libraryUpdates = new LibraryUpdateService(this.catalog,this.catalogService,this.downloads,this.updatePolicy);
    this.bookReader = new ReaderService(this.registry, this.catalog, this.progress, context.cacheDir, this.downloadRecords, this.downloads.files);
  }
  async listSources(): Promise<ManagedSource[]> { return (await this.nativeSources.list()).concat(await this.imports.list()); }
}
