import { AppError, ErrorCode } from '../model/ErrorTypes';
import { common } from '@kit.AbilityKit';
import { url } from '@kit.ArkTS';
import { CallContext } from '../model/RequestTypes';
import { ChapterPageSource } from '../model/SourceTypes';
import { ReaderAssetCache } from '../image/ReaderAssetCache';
import { UrlPolicy } from '../network/UrlPolicy';
import { SourceRef } from '../model/SourceTypes';
import { SourceRegistry } from '../source/SourceRegistry';
import { SourceSiteService } from '../source/SourceSiteService';
import { BundledSampleTransport } from '../source/demo/BundledSampleTransport';
import { htmlDemoRule } from '../source/rules/DemoRules';
import { RuleSource } from '../source/rules/RuleSource';
import { ChapterManifest, collectChapterManifest } from './ChapterManifest';

export interface ReaderSession {
  source: ChapterPageSource;
  manifest: ChapterManifest;
  cache: ReaderAssetCache;
}

export class ChapterReaderService {
  private readonly sites: SourceSiteService;
  private readonly cacheDir: string;
  private readonly context: common.UIAbilityContext;
  private readonly registry: SourceRegistry;

  constructor(sites: SourceSiteService, context: common.UIAbilityContext,registry: SourceRegistry) {
    this.sites = sites; this.context = context; this.cacheDir = context.cacheDir; this.registry = registry;
  }

  async openDemo(ctx: CallContext,long: boolean = false): Promise<ReaderSession> {
    const transport = new BundledSampleTransport(this.context);
    const source = new RuleSource(htmlDemoRule(), 'https://fixture.invalid/', new UrlPolicy(['fixture.invalid']), transport);
    const search = await source.search('', undefined, ctx);
    const detail = await source.details(search.items[0].ref, ctx);
    let chapters = await source.chapters(detail.ref, undefined, ctx);
    if (long) { while (chapters.next) { chapters = await source.chapters(detail.ref,chapters.next,ctx); } }
    const manifest = await collectChapterManifest(source, chapters.items[0].ref, ctx);
    manifest.label = long ? '长图示例 · 星海旅人（合成图）' : '内置示例 · 星海旅人（合成图）';
    return { source: source, manifest: manifest, cache: new ReaderAssetCache(this.cacheDir, transport,134217728,33554432) };
  }

  async open(input: string, ctx: CallContext,sourceId: string = 'org.hsmihon.baozi'): Promise<ReaderSession> {
    if (input.length > 8192) { throw new AppError(ErrorCode.CONFIG_INVALID,'章节网址过长'); }
    if (['org.hsmihon.baozi','org.hsmihon.copy'].indexOf(sourceId) < 0) { throw new AppError(ErrorCode.UNSUPPORTED,'请选择受支持的漫画源'); }
    const site = await this.sites.access(sourceId); let parsed: url.URL;
    try { parsed = new url.URL(input.trim()); } catch (_) { throw new AppError(ErrorCode.CONFIG_INVALID,'请输入完整章节网址'); }
    new UrlPolicy(site.allowedHosts).validate(parsed.toString());
    if (parsed.search) { throw new AppError(ErrorCode.POLICY_DENIED,'章节网址不能包含查询参数'); }
    let chapter: SourceRef; const path = parsed.pathname;
    if (sourceId === 'org.hsmihon.baozi') {
      if (!/^\/comic\/chapter\/[a-zA-Z0-9_-]+\/[0-9]+_[0-9]+\.html$/.test(path)) { throw new AppError(ErrorCode.UNSUPPORTED,'请输入包子章节第一页网址'); }
      chapter = { sourceId: sourceId,remoteId: path.substring('/comic/chapter/'.length).replace(/\.html$/,''),locator: path };
    } else {
      const match = /^\/comic\/([a-zA-Z0-9_-]{1,200})\/chapter\/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/.exec(path);
      if (!match) { throw new AppError(ErrorCode.UNSUPPORTED,'请输入COPY章节阅读网址'); }
      chapter = { sourceId: sourceId,remoteId: match[1] + '/' + match[2],locator: path };
    }
    const handle = await this.registry.open(sourceId); const source = handle.source;
    const call: CallContext = { callId: ctx.callId,deadlineMs: ctx.deadlineMs,cancel: ctx.cancel,ruleRevision: source.version };
    const manifest = await collectChapterManifest(source, chapter, call); await this.registry.assertCurrent(sourceId,handle.revision);
    if (manifest.pages.length === 0) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED, '章节没有图像'); }
    return { source: source, manifest: manifest,
      cache: new ReaderAssetCache(this.cacheDir,handle.transport,134217728,33554432,handle.snapshotKey) };
  }
}
