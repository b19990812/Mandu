import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { SourceSiteAccess, SourceSiteDefinition, SourceSiteSetting, SourceSiteSettingsStore,
  SourceSiteSnapshot, SourceSiteView } from '../model/SourceSiteTypes';
import { SourceSiteAddress } from './SourceSiteAddress';
import { sourceSiteDefinitions } from './SourceSiteCatalog';
import { SourceChanges } from './SourceChanges';
import { copyProtocol, copyApiBase } from './CopyAccess';
import { EHENTAI_BASE, EHENTAI_ID } from '../network/EhentaiAccess';

export class SourceSiteService {
  private readonly store: SourceSiteSettingsStore;
  private readonly address: SourceSiteAddress = new SourceSiteAddress();

  constructor(store: SourceSiteSettingsStore) { this.store = store; }

  private definition(sourceId: string): SourceSiteDefinition {
    const definition = sourceSiteDefinitions().find((site: SourceSiteDefinition) => site.sourceId === sourceId);
    if (!definition) { throw new AppError(ErrorCode.CONFIG_INVALID, '未找到对应的漫画源'); }
    return definition;
  }

  private current(snapshot: SourceSiteSnapshot, sourceId: string): SourceSiteSetting {
    const definition = this.definition(sourceId);
    const saved = snapshot.sites.find((site: SourceSiteSetting) => site.sourceId === sourceId);
    if (saved) {
      if (sourceId === 'org.hsmihon.copy') {
        copyProtocol(saved.copyProtocol);
        if (saved.copyApiBaseUrl !== undefined && copyApiBase(saved.copyApiBaseUrl) !== saved.copyApiBaseUrl) { throw new AppError(ErrorCode.CONFIG_INVALID,'已保存的COPY API网址不规范'); }
      }
      if (this.address.normalize(saved.baseUrl) !== saved.baseUrl ||
        (saved.previousBaseUrl !== '' && this.address.normalize(saved.previousBaseUrl) !== saved.previousBaseUrl)) {
        throw new AppError(ErrorCode.CONFIG_INVALID, '已保存的网址不规范，原设置已保留');
      }
      return saved;
    }
    return {
      sourceId: sourceId, baseUrl: definition.defaultBaseUrl, previousBaseUrl: '', revision: 0, updatedAt: 0
    };
  }

  async list(): Promise<SourceSiteView[]> {
    const snapshot = await this.store.read();
    return sourceSiteDefinitions().map((definition: SourceSiteDefinition): SourceSiteView => {
      const site = this.current(snapshot, definition.sourceId);
      return {
        sourceId: site.sourceId, name: definition.name, baseUrl: site.baseUrl,
        defaultBaseUrl: definition.defaultBaseUrl, previousBaseUrl: site.previousBaseUrl, revision: site.revision,
        copyProtocol: site.sourceId === 'org.hsmihon.copy' ? copyProtocol(site.copyProtocol) : undefined,
        copyApiBaseUrl: site.sourceId === 'org.hsmihon.copy' ? copyApiBase(site.copyApiBaseUrl) : undefined
      };
    });
  }

  async access(sourceId: string): Promise<SourceSiteAccess> {
    const site = this.current(await this.store.read(), sourceId);
    const normalized = this.address.normalize(site.baseUrl);
    return {
      sourceId: sourceId, baseUrl: normalized,
      allowedHosts: [new url.URL(normalized).hostname], revision: site.revision,
      copyProtocol: sourceId === 'org.hsmihon.copy' ? copyProtocol(site.copyProtocol) : undefined,
      copyApiBaseUrl: sourceId === 'org.hsmihon.copy' ? copyApiBase(site.copyApiBaseUrl) : undefined
    };
  }

  async save(sourceId: string, input: string, expectedRevision: number, protocol?: string, apiBaseUrl?: string): Promise<void> {
    const normalized = this.address.normalize(input);
    if (sourceId === EHENTAI_ID && normalized !== EHENTAI_BASE) {
      throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 使用公开站点 e-hentai.org');
    }
    const snapshot = await this.store.read();
    const previous = this.current(snapshot, sourceId);
    if (previous.revision !== expectedRevision) {
      throw new AppError(ErrorCode.CONFLICT, '这个源的网址已变更，请重新读取后再保存');
    }
    const mode = sourceId === 'org.hsmihon.copy' ? copyProtocol(protocol === undefined ? previous.copyProtocol : protocol) : undefined;
    const api = sourceId === 'org.hsmihon.copy' ? copyApiBase(apiBaseUrl === undefined ? previous.copyApiBaseUrl : apiBaseUrl) : undefined;
    if (normalized === previous.baseUrl && (sourceId !== 'org.hsmihon.copy' || mode === copyProtocol(previous.copyProtocol) && api === copyApiBase(previous.copyApiBaseUrl))) { return; }
    const next: SourceSiteSetting = {
      sourceId: sourceId, baseUrl: normalized, previousBaseUrl: normalized !== previous.baseUrl ? previous.baseUrl : previous.previousBaseUrl,
      revision: previous.revision + 1, updatedAt: Date.now(), copyProtocol: mode, copyApiBaseUrl: api
    };
    const entries = snapshot.sites.filter((site: SourceSiteSetting) => site.sourceId !== sourceId);
    entries.push(next);
    const updated: SourceSiteSnapshot = {
      schemaVersion: 1, revision: snapshot.revision + 1, sites: entries
    };
    await this.store.commit(updated, snapshot.revision);
    SourceChanges.addressChanged(sourceId);
  }

  async reset(sourceId: string, expectedRevision: number): Promise<void> {
    await this.save(sourceId, this.definition(sourceId).defaultBaseUrl, expectedRevision,
      sourceId === 'org.hsmihon.copy' ? 'api' : undefined,sourceId === 'org.hsmihon.copy' ? copyApiBase() : undefined);
  }

  async rollback(sourceId: string, expectedRevision: number): Promise<void> {
    const previous = this.current(await this.store.read(), sourceId);
    if (previous.previousBaseUrl === '') {
      throw new AppError(ErrorCode.CONFIG_INVALID, '没有可切回的上一次网址');
    }
    await this.save(sourceId, previous.previousBaseUrl, expectedRevision);
  }
}
