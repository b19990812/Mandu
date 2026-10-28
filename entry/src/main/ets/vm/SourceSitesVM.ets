import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContainer } from '../app/AppContainer';
import { AppError } from '../model/ErrorTypes';
import { SourceSiteView } from '../model/SourceSiteTypes';
import { SourceSiteService } from '../source/SourceSiteService';

@Observed
export class SourceSitesVM {
  sites: SourceSiteView[] = [];
  busy: boolean = false;
  status: string = '';
  editingSourceId: string = '';
  editingName: string = '';
  draft: string = '';
  copyMode: string = 'api';
  copyApiDraft: string = '';
  private editingRevision: number = 0;
  private service?: SourceSiteService;
  private disposed: boolean = false;
  private generation: number = 0;

  initialize(context: common.UIAbilityContext): void {
    this.disposed = false;
    this.service = new AppContainer(context).sourceSites;
    this.reload();
  }

  private async run(action: (service: SourceSiteService) => Promise<void>, message: string,
    closeEditor: boolean = false): Promise<void> {
    if (this.busy || this.disposed || !this.service) { return; }
    const service = this.service;
    const current = ++this.generation;
    this.busy = true;
    this.status = '正在处理…';
    try {
      await action(service);
      const sites = await service.list();
      if (!this.disposed && current === this.generation) {
        this.sites = sites;
        this.status = message;
        if (closeEditor) { this.cancelEdit(); }
      }
    } catch (error) {
      hilog.error(0x0001, 'HSReader', 'SOURCE_SITE_SETTINGS code=%{public}s',
        error instanceof AppError ? error.code : 'SYSTEM_ERROR');
      if (!this.disposed && current === this.generation) {
        this.status = error instanceof AppError ? error.code + '：' + error.message : '读取或保存网站设置失败，请重试';
      }
    } finally {
      if (current === this.generation) { this.busy = false; }
    }
  }

  reload(): void {
    this.run(async (_service: SourceSiteService): Promise<void> => {}, '网站设置已读取');
  }

  edit(site: SourceSiteView): void {
    if (this.busy) { return; }
    this.editingSourceId = site.sourceId;
    this.editingName = site.name;
    this.editingRevision = site.revision;
    this.draft = site.baseUrl;
    this.copyMode = site.copyProtocol || 'api';
    this.copyApiDraft = site.copyApiBaseUrl || '';
  }

  cancelEdit(): void {
    this.editingSourceId = '';
    this.editingName = '';
    this.draft = '';
    this.copyApiDraft = '';
  }

  save(): void {
    if (this.editingSourceId === '') { return; }
    const sourceId = this.editingSourceId;
    const revision = this.editingRevision;
    const address = this.draft;
    const mode = sourceId === 'org.hsmihon.copy' ? this.copyMode : undefined;
    const api = sourceId === 'org.hsmihon.copy' ? this.copyApiDraft : undefined;
    this.run((service: SourceSiteService) => service.save(sourceId, address, revision, mode, api), '接入设置已保存', true);
  }

  reset(site: SourceSiteView): void {
    this.run((service: SourceSiteService) => service.reset(site.sourceId, site.revision), '已恢复默认网址', true);
  }

  rollback(site: SourceSiteView): void {
    this.run((service: SourceSiteService) => service.rollback(site.sourceId, site.revision), '已切回上一次网址', true);
  }

  dispose(): void { this.disposed = true; }
}
