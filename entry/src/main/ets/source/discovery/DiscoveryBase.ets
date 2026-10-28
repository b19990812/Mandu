import { SourceSiteAccess } from '../../model/SourceSiteTypes';
import { SourceBrowseItem, SourceRef } from '../../model/SourceTypes';
import { CallContext } from '../../model/RequestTypes';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { Transport } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { HtmlExtractor, HtmlNode } from '../rules/HtmlExtractor';
import { SelectorSubset } from '../rules/SelectorSubset';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { nodeText } from './DiscoverySupport';

export class DiscoveryBase {
  protected readonly id: string;
  protected readonly site: SourceSiteAccess;
  protected readonly transport: Transport;
  protected readonly policy: UrlPolicy;
  protected readonly covers: UrlPolicy;
  protected readonly select: SelectorSubset = new SelectorSubset();
  constructor(id: string,site: SourceSiteAccess,transport: Transport,coverHosts: string[]) {
    this.id = id; this.site = site; this.transport = transport; this.policy = new UrlPolicy(site.allowedHosts); this.covers = new UrlPolicy(coverHosts);
  }
  protected async read(path: string,ctx: CallContext,json: boolean = false): Promise<string> {
    checkCall(ctx);
    const response = await this.transport.send({ sourceId: this.id,url: this.policy.resolve(path,this.site.baseUrl),headers: [{ name: 'Accept',value: json ? 'application/json' : 'text/html' },{ name: 'Referer',value: this.site.baseUrl }],maxBytes: 2097152,responseKind: 'metadata' },ctx);
    requireHttpSuccess(response); checkCall(ctx); return response.body;
  }
  protected async document(path: string,ctx: CallContext): Promise<HtmlNode> { return new HtmlExtractor().parse(await this.read(path,ctx)); }
  protected ref(path: string): SourceRef {
    const parsed = this.policy.validate(this.policy.resolve(path,this.site.baseUrl)); const match = /^\/comic\/([a-zA-Z0-9_-]{1,200})$/.exec(parsed.pathname);
    if (!match || parsed.search || parsed.hash) { throw new AppError(ErrorCode.PARSE_ERROR,'首页返回了不支持的漫画地址'); }
    return { sourceId: this.id,remoteId: match[1],locator: parsed.pathname };
  }
  protected cover(address: string): string | undefined {
    if (!address) { return undefined; }
    try { return this.covers.validate(address).toString(); } catch (_) { return undefined; }
  }
  protected cardImage(card: HtmlNode): string | undefined {
    for (const selector of ['amp-img[src]','img[data-src]','img[src]']) {
      const node = this.select.select(card,selector)[0]; if (node) { const cover = this.cover(node.attribute('data-src') || node.attribute('src')); if (cover) { return cover; } }
    }
    return undefined;
  }
  protected copyCards(root: HtmlNode,selector: string): SourceBrowseItem[] {
    const items: SourceBrowseItem[] = [];
    this.select.select(root,selector).forEach((card: HtmlNode) => {
      const links = this.select.select(card,'a[href]').filter((node: HtmlNode) => /^\/comic\/[a-zA-Z0-9_-]+$/.test(node.attribute('href')));
      const link = links[0]; if (!link) { return; }
      const titled = this.select.select(card,'[title]').find((node: HtmlNode) => node.attribute('title').trim() !== '');
      const title = (titled?.attribute('title') || links.map((node: HtmlNode) => nodeText(node)).find((text: string) => text !== '') || '').trim();
      if (!title || title.length > 1024) { throw new AppError(ErrorCode.PARSE_ERROR,'首页漫画标题缺失或过长'); }
      items.push({ manga: { ref: this.ref(link.attribute('href')),title: title,cover: this.cardImage(card) },subtitle: '' });
    });
    return items;
  }
  protected json(raw: string): JsonNode { return new JsonExtractor().parse(raw); }
  protected scalar(root: JsonNode,name: string): string { const node = root.members.get(name); return node && (node.kind === 'number' || node.kind === 'string') ? node.scalar : ''; }
}
