import { CatalogRepository } from '../storage/CatalogRepository';
import { CatalogService } from './CatalogService';
import { UpdateDownloads } from '../model/UpdateDownloads';
import { UpdatePolicyRepository } from '../storage/UpdatePolicyRepository';
import { NetworkPolicy } from '../network/NetworkPolicy';
import { CallContext } from '../model/RequestTypes';
import { checkCall } from '../source/SourceHttp';
import { ChapterRecord } from '../model/LibraryTypes';
import { EHENTAI_ID } from '../network/EhentaiAccess';

export class LibraryUpdateService {
  private static running: boolean = false;
  private readonly catalog: CatalogRepository;
  private readonly service: CatalogService;
  private readonly downloads: UpdateDownloads;
  private readonly policy: UpdatePolicyRepository;
  constructor(catalog: CatalogRepository, service: CatalogService, downloads: UpdateDownloads, policy: UpdatePolicyRepository) {
    this.catalog = catalog; this.service = service; this.downloads = downloads; this.policy = policy;
  }
  private async flush(ctx: CallContext): Promise<number> {
    let failures = 0;
    const ids = await this.policy.pending();
    for (let i = 0; i < ids.length; i++) {
      checkCall(ctx);
      const chapter = await this.catalog.chapter(ids[i]);
      const book = chapter ? await this.catalog.manga(chapter.mangaId) : undefined;
      if (!chapter || !chapter.active || chapter.ref.sourceId === EHENTAI_ID || !book?.favorite) { await this.policy.clearPending(ids[i]); continue; }
      try { await this.downloads.enqueue(ids[i]); await this.policy.clearPending(ids[i]); } catch (_) { failures++; }
    }
    return failures;
  }
  async run(ctx: CallContext, automatic: boolean, report: (message: string) => void): Promise<void> {
    if (LibraryUpdateService.running) { report('已有书架更新正在进行'); return; }
    LibraryUpdateService.running = true;
    try {
      const policy = await this.policy.read(); checkCall(ctx);
      if (policy.autoDownload) { await this.flush(ctx); }
      if (automatic && (!policy.hours || Date.now() - await this.policy.lastAttempt() < policy.hours * 3600000)) { return; }
      if (!await NetworkPolicy.allowed(policy.wifiOnly)) { report(policy.wifiOnly ? '等待 Wi-Fi 后检查更新' : '等待网络后检查更新'); return; }
      const books = await this.catalog.library(policy.category); checkCall(ctx);
      let checked = 0; let skipped = 0; let failed = 0; let added = 0; let downloadFailed = 0;
      for (let i = 0; i < books.length; i++) {
        checkCall(ctx);
        if (books[i].detail.ref.sourceId === 'org.hsmihon.local' || policy.skipUnread && (books[i].unreadCount || 0) > 0) { skipped++; continue; }
        if (!await NetworkPolicy.allowed(policy.wifiOnly)) { report('网络条件变化，更新已停止；下次前台检查重试'); return; }
        report('正在检查 ' + (i + 1).toString() + ' / ' + books.length.toString() + ' · ' + books[i].detail.title);
        try {
          const before = await this.catalog.chapters(books[i].id);
          const known: Set<string> = new Set(before.map((chapter: ChapterRecord) => chapter.id));
          await this.service.refresh(books[i].id,{ callId: ctx.callId,deadlineMs: Math.min(ctx.deadlineMs,Date.now() + 60000),cancel: ctx.cancel,ruleRevision: 1 },
            policy.autoDownload && books[i].detail.ref.sourceId !== EHENTAI_ID);
          checkCall(ctx); checked++;
          const fresh = (await this.catalog.chapters(books[i].id)).filter((chapter: ChapterRecord) => chapter.active && !known.has(chapter.id));
          added += fresh.length;
          if (policy.autoDownload) { downloadFailed += await this.flush(ctx); }
        } catch (error) { checkCall(ctx); failed++; }
      }
      checkCall(ctx); await this.policy.stamp();
      report('已检查 ' + checked.toString() + ' 部 · 跳过 ' + skipped.toString() + ' 部 · 新章 ' + added.toString() + ' · 刷新失败 ' + failed.toString() + ' · 下载入队失败 ' + downloadFailed.toString());
    } finally { LibraryUpdateService.running = false; }
  }
}
