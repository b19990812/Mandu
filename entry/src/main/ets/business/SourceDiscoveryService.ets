import { CallContext } from '../model/RequestTypes';
import { SourceBrowseQuery, SourceBrowseBatch, SourceBrowseItem, PageToken } from '../model/SourceTypes';
import { SourceRegistry, SourceHandle } from '../source/SourceRegistry';
import { CatalogRepository } from '../storage/CatalogRepository';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkCall } from '../source/SourceHttp';

export class SourceDiscoveryService {
  private readonly registry: SourceRegistry;
  private readonly catalog: CatalogRepository;
  constructor(registry: SourceRegistry,catalog: CatalogRepository) { this.registry = registry; this.catalog = catalog; }
  open(id: string): Promise<SourceHandle> { return this.registry.open(id); }
  async browse(handle: SourceHandle,query: SourceBrowseQuery,token: PageToken | undefined,ctx: CallContext): Promise<SourceBrowseBatch> {
    if (!handle.source.discovery) { throw new AppError(ErrorCode.UNSUPPORTED,'该源暂未提供原生首页，请使用搜索或网站首页'); }
    const watch = this.registry.watch(handle,ctx);
    try { const batch = await handle.source.discovery.browse(query,token,ctx); watch.check(); return batch; }
    finally { watch.release(); }
  }
  async select(handle: SourceHandle,item: SourceBrowseItem,ctx: CallContext): Promise<string> {
    if (item.manga.ref.sourceId !== handle.source.id) { throw new AppError(ErrorCode.CONFLICT,'漫画不属于当前来源'); }
    const watch = this.registry.watch(handle,ctx);
    try {
      checkCall(ctx); await this.registry.assertCurrent(handle.source.id,handle.revision); watch.check();
      const records = await this.catalog.saveSearch([item.manga],() => watch.check()); watch.check(); return records[0].id;
    } finally { watch.release(); }
  }
}
