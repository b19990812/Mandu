import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { SourceSiteSetting, SourceSiteSettingsStore, SourceSiteSnapshot } from '../model/SourceSiteTypes';

const KEY = 'source_sites_v1';
const EMPTY = '{"schemaVersion":1,"revision":0,"sites":[]}';

// Preferences store only the small per-source address override, not comic data or credentials.
export class SourceSiteSettingsRepository implements SourceSiteSettingsStore {
  private readonly context: common.Context;
  private store?: preferences.Preferences;

  constructor(context: common.Context) { this.context = context; }

  private async open(): Promise<preferences.Preferences> {
    if (!this.store) {
      try { this.store = await preferences.getPreferences(this.context, { name: 'source_site_settings' }); }
      catch (_) { throw new AppError(ErrorCode.IO_ERROR, '无法打开网站设置'); }
    }
    return this.store;
  }

  private decode(raw: preferences.ValueType): SourceSiteSnapshot {
    if (typeof raw !== 'string' || raw.length > 65536) {
      throw new AppError(ErrorCode.CONFIG_INVALID, '网站设置格式异常，原数据已保留');
    }
    let snapshot: SourceSiteSnapshot;
    try { snapshot = JSON.parse(raw) as SourceSiteSnapshot; }
    catch (_) { throw new AppError(ErrorCode.CONFIG_INVALID, '无法解析网站设置，原数据已保留'); }
    if (!snapshot || typeof snapshot !== 'object' || snapshot.schemaVersion !== 1 ||
      !Number.isSafeInteger(snapshot.revision) || snapshot.revision < 0 ||
      !Array.isArray(snapshot.sites) || snapshot.sites.length > 64) {
      throw new AppError(ErrorCode.CONFIG_INVALID, '网站设置版本或结构不受支持');
    }
    const ids: string[] = [];
    snapshot.sites.forEach((site: SourceSiteSetting) => {
      if (!site || typeof site !== 'object' || typeof site.sourceId !== 'string' ||
        !/^[a-z0-9][a-z0-9._-]{0,127}$/.test(site.sourceId) || ids.indexOf(site.sourceId) >= 0 ||
        typeof site.baseUrl !== 'string' || site.baseUrl.length > 2048 ||
        typeof site.previousBaseUrl !== 'string' || site.previousBaseUrl.length > 2048 ||
        (site.copyProtocol !== undefined && (site.sourceId !== 'org.hsmihon.copy' || ['api','web'].indexOf(site.copyProtocol) < 0)) ||
        (site.copyApiBaseUrl !== undefined && (site.sourceId !== 'org.hsmihon.copy' || typeof site.copyApiBaseUrl !== 'string' || site.copyApiBaseUrl.length > 2048)) ||
        !Number.isSafeInteger(site.revision) || site.revision < 1 ||
        !Number.isSafeInteger(site.updatedAt) || site.updatedAt < 0) {
        throw new AppError(ErrorCode.CONFIG_INVALID, '网站设置条目异常，原数据已保留');
      }
      ids.push(site.sourceId);
    });
    return snapshot;
  }

  async read(): Promise<SourceSiteSnapshot> {
    const store = await this.open();
    return this.decode(store.getSync(KEY, EMPTY));
  }

  async commit(next: SourceSiteSnapshot, expectedRevision: number): Promise<void> {
    const store = await this.open();
    const previous = store.getSync(KEY, EMPTY);
    const current = this.decode(previous);
    if (current.revision !== expectedRevision || next.revision !== expectedRevision + 1) {
      throw new AppError(ErrorCode.CONFLICT, '设置已被更新，请重新读取后再保存');
    }
    const encoded = JSON.stringify(next);
    this.decode(encoded);
    // Read/compare/put use the same synchronous Preferences cache before yielding to flush.
    store.putSync(KEY, encoded);
    try { await store.flush(); }
    catch (_) {
      // Never roll an intervening newer write back to this operation's older snapshot.
      try {
        if (store.getSync(KEY, EMPTY) === encoded) {
          store.putSync(KEY, previous);
          await store.flush();
        }
      } catch (_) { /* Report failure; do not claim durable rollback without device evidence. */ }
      throw new AppError(ErrorCode.IO_ERROR, '保存未成功，请重新读取网站设置后重试');
    }
  }
}
