import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { CallContext } from '../../model/RequestTypes';
import { ChapterPageSource, ImageRequest, PageRef, PageToken, SourceBatch, SourceRef } from '../../model/SourceTypes';
import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { HtmlExtractor } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { HtmlNode } from '../rules/HtmlExtractor';
import { refreshPage } from '../RefreshPage';

export const BAOZI_SAMPLE_CHAPTER = 'https://www.twmanga.com/comic/chapter/silingfashiwojishitianzai-mantudezhuyuanzhuheiniaoshe_rjogsq/0_286.html';
export const BAOZI_IMAGE_HOSTS: string[] = ['s1.bzcdn.net', 's2.bzcdn.net'];

// Observed host declarations retained for rule metadata, not request authorization.
export function baoziPageHosts(site: SourceSiteAccess): string[] {
  const hosts = site.allowedHosts.slice();
  const current = new url.URL(site.baseUrl).hostname;
  if (current === 'www.twmanga.com' && hosts.indexOf('cn.dzmanga.com') < 0) { hosts.push('cn.dzmanga.com'); }
  if (current === 'cn.dzmanga.com' && hosts.indexOf('www.twmanga.com') < 0) { hosts.push('www.twmanga.com'); }
  return hosts;
}

// Read-only chapter slice. Search/catalogue adaptation is deliberately a separate task.
export class BaoziChapterSource implements ChapterPageSource {
  readonly id: string;
  readonly version: number = 1;
  private readonly site: SourceSiteAccess;
  private readonly transport: Transport;
  private readonly pagePolicy: UrlPolicy;
  private readonly imagePolicy: UrlPolicy = new UrlPolicy(BAOZI_IMAGE_HOSTS);

  constructor(site: SourceSiteAccess, transport: Transport) {
    this.id = site.sourceId;
    this.site = site;
    this.transport = transport;
    this.pagePolicy = new UrlPolicy(baoziPageHosts(site));
  }

  chapter(input: string): SourceRef {
    const address = this.address(input);
    const path = new url.URL(address).pathname;
    if (!/^\/comic\/chapter\/[a-zA-Z0-9_-]+\/[0-9]+_[0-9]+\.html$/.test(path)) {
      throw new AppError(ErrorCode.UNSUPPORTED, '请粘贴包子章节第一页的完整阅读网址');
    }
    return { sourceId: this.id, remoteId: path.substring('/comic/chapter/'.length).replace(/\.html$/, ''), locator: path };
  }

  async pages(chapter: SourceRef, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<PageRef>> {
    checkCall(ctx);
    if (chapter.sourceId !== this.id || ctx.ruleRevision !== this.version ||
      token && (token.kind !== 'url' || token.binding !== this.binding(chapter))) {
      throw new AppError(ErrorCode.RULE_INVALID, '章节或分页标记与当前源不匹配');
    }
    const address = this.address(token ? token.value : chapter.locator);
    const expected = chapter.locator.replace(/\.html$/, '');
    const path = new url.URL(address).pathname;
    if (path !== chapter.locator && !(path.startsWith(expected + '_') && /^_[1-9][0-9]*\.html$/.test(path.substring(expected.length)))) {
      throw new AppError(ErrorCode.POLICY_DENIED, '分页离开了当前章节');
    }
    const response = await this.transport.send({ sourceId: this.id, url: address, maxBytes: 2097152,
      headers: [{ name: 'Accept', value: 'text/html' }, { name: 'Referer', value: this.site.baseUrl }] }, ctx);
    requireHttpSuccess(response);
    if (new url.URL(response.finalUrl).pathname !== path) {
      throw new AppError(ErrorCode.CONTENT_CHANGED, '站点跳转到了其他章节或页面');
    }
    const root = new HtmlExtractor().parse(response.body);
    const selector = new SelectorSubset();
    const nodes = selector.select(root, 'amp-img.comic-contain__item');
    if (nodes.length === 0) { throw new AppError(ErrorCode.EMPTY_UNEXPECTED, '未找到章节图像，页面结构可能已改变'); }
    const items = nodes.map((node: HtmlNode, index: number): PageRef => {
      const location = node.attribute('data-src') || node.attribute('src');
      if (!location) { throw new AppError(ErrorCode.PARSE_ERROR, '章节图像地址缺失'); }
      const image = this.imagePolicy.resolve(location, response.finalUrl);
      const imagePath = new url.URL(image).pathname;
      const width = Number(node.attribute('width'));
      const height = Number(node.attribute('height'));
      return { pageKey: imagePath, ordinal: index, locator: imagePath, imageUrl: image,
        width: Number.isSafeInteger(width) && width > 0 ? width : undefined,
        height: Number.isSafeInteger(height) && height > 0 ? height : undefined };
    });
    let next: PageToken | undefined = undefined;
    const links = selector.select(root, 'a[href]');
    links.forEach((node: HtmlNode) => {
      if (node.textContent().replace(/\s+/g, '').indexOf('下一頁') < 0) { return; }
      const target = this.address(node.attribute('href'));
      const nextPath = new url.URL(target).pathname;
      if (!nextPath.startsWith(expected + '_')) { throw new AppError(ErrorCode.PARSE_ERROR, '下一页不属于当前章节'); }
      if (next && next.value !== nextPath) { throw new AppError(ErrorCode.PARSE_ERROR, '下一页链接冲突'); }
      next = { kind: 'url', value: nextPath, binding: this.binding(chapter) };
    });
    const title = selector.select(root, 'title')[0];
    return { items: items, next: next, label: title ? title.textContent().replace(/\([0-9]+\/[0-9]+\)/, '').trim() : chapter.remoteId };
  }

  async resolveImage(chapter: SourceRef, page: PageRef, forceRefresh: boolean, ctx: CallContext): Promise<ImageRequest> {
    checkCall(ctx);
    if (forceRefresh) { return this.resolveImage(chapter,await refreshPage(this,chapter,page.pageKey,ctx),false,ctx); }
    if (chapter.sourceId !== this.id || !page.imageUrl) { throw new AppError(ErrorCode.PARSE_ERROR, '图像不属于当前章节'); }
    return { url: this.imagePolicy.validate(page.imageUrl).toString(),
      headers: [{ name: 'Referer', value: this.address(chapter.locator) }], contentRevision: 'baozi-chapter-v1' };
  }

  private address(input: string): string {
    let parsed: url.URL;
    try { parsed = new url.URL(input.trim(), this.site.baseUrl); }
    catch (_) { throw new AppError(ErrorCode.POLICY_DENIED, '章节网址无效'); }
    const current = new url.URL(this.site.baseUrl);
    this.pagePolicy.validate(parsed.toString());
    if (parsed.search) {
      throw new AppError(ErrorCode.POLICY_DENIED, '章节网址不能包含查询参数');
    }
    return this.pagePolicy.validate(current.origin + parsed.pathname).toString();
  }

  private binding(chapter: SourceRef): string {
    return JSON.stringify([this.id, this.version.toString(), this.site.revision.toString(), chapter.remoteId]);
  }
}
