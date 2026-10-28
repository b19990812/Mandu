import { common } from '@kit.AbilityKit';
import { url, util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { CallContext } from '../../model/RequestTypes';
import { ByteSink } from '../../model/ByteSink';
import { RequestPlan, Transport, TransportResponse } from '../../network/Transport';
import { checkCall } from '../SourceHttp';
import { JsonExtractor } from '../rules/JsonExtractor';

// Explicit self-owned samples; never substituted for a failed real website request.
export class BundledSampleTransport implements Transport {
  private readonly context: common.Context;
  private readonly paths: Map<string, string> = new Map();
  private readonly revision: () => number;

  constructor(context: common.Context, revision: () => number = () => 1) {
    this.context = context;
    this.revision = revision;
    const parser = new JsonExtractor();
    const root = parser.parse(this.readFile('index.json'));
    if (root.kind !== 'array') { throw new AppError(ErrorCode.PARSE_ERROR, '自有样本索引无效'); }
    root.items.forEach((node) => {
      const path = parser.at(node, 'path');
      const file = parser.at(node, 'file');
      if (!path || !file || path.kind !== 'string' || file.kind !== 'string' || this.paths.has(path.scalar)) {
        throw new AppError(ErrorCode.PARSE_ERROR, '自有样本索引重复或缺失');
      }
      this.paths.set(path.scalar, file.scalar);
    });
  }

  async send(plan: RequestPlan, ctx: CallContext): Promise<TransportResponse> {
    checkCall(ctx);
    const address = new url.URL(plan.url);
    if (address.origin !== 'https://fixture.invalid') { throw new AppError(ErrorCode.POLICY_DENIED, '内置示例不能替代真实网站'); }
    const key = address.pathname + address.search;
    const filename = this.paths.get(key);
    const search = address.pathname === '/search' || address.pathname === '/api/search';
    const body = search ? this.search(address) : filename ? this.readFile(filename) : '{"error":"fixture not found"}';
    if (new util.TextEncoder().encodeInto(body).byteLength > plan.maxBytes) {
      throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '内置示例超过响应限额');
    }
    return { statusCode: filename || search ? 200 : 404, finalUrl: plan.url, headers: [], body: body,
      bytes: new util.TextEncoder().encodeInto(body).byteLength };
  }

  private search(address: url.URL): string {
    const query = address.searchParams.get('q') || ''; const page = Number(address.searchParams.get('page') || '1');
    if (!Number.isSafeInteger(page) || page < 1) { throw new AppError(ErrorCode.CONFIG_INVALID, '样本页码无效'); }
    const titles: string[] = ['星海旅人 & 归途', '纸飞机实验室'];
    const matches: number[] = []; titles.forEach((title: string, index: number) => { if (title.toLowerCase().includes(query.toLowerCase())) { matches.push(index); } });
    const selected = matches[page - 1]; const has = selected !== undefined; const next = page < matches.length;
    if (address.pathname === '/api/search') {
      const item = has ? '{"id":"m' + (selected + 1).toString() + '","title":' + JSON.stringify(titles[selected]) + ',"url":"/manga/m' + (selected + 1).toString() + '","cover":"/images/page-1.png"}' : '';
      return '{"data":{"' + (this.revision() === 2 ? 'results' : 'items') + '":[' + item + '],"nextPage":' + (next ? (page + 1).toString() : 'null') + '}}';
    }
    const item = has ? '<a class="' + (this.revision() === 2 ? 'comic-card' : 'comic') + '" data-id="m' + (selected + 1).toString() + '" href="/manga/m' + (selected + 1).toString() + '"><span class="title">' + titles[selected].replace(/&/g, '&amp;') + '</span></a>' : '<span class="empty">没有结果</span>';
    return '<html><body><div id="search-results">' + item + '</div>' + (next ? '<a class="next" href="/search?q=' + encodeURIComponent(query) + '&amp;page=' + (page + 1).toString() + '">下一页</a>' : '') + '</body></html>';
  }

  async streamToFile(plan: RequestPlan, ctx: CallContext, sink: ByteSink): Promise<TransportResponse> {
    checkCall(ctx);
    const address = new url.URL(plan.url);
    const match = /^\/images\/page-([12])\.png$/.exec(address.pathname);
    const matrix = address.pathname.substring('/images/matrix/'.length);
    const matrixAllowed = address.pathname.startsWith('/images/matrix/') && ['ordinary.png', 'ordinary.jpg', 'ordinary.webp', 'long_1080.png', 'long_1080.jpg', 'long_webp.webp', 'long_2160.png', 'long_2160.jpg'].indexOf(matrix) >= 0;
    if (address.origin !== 'https://fixture.invalid' || address.search || !match && !matrixAllowed) {
      throw new AppError(ErrorCode.POLICY_DENIED, '内置示例仅接受自己的合成图片');
    }
    const bytes = this.context.resourceManager.getRawFileContentSync(match ? 'demo-fixtures/page_' + match[1] + '.png' : 'image-matrix/' + matrix);
    const ceiling = plan.responseKind === 'image' ? 33554432 : 2097152;
    if (bytes.byteLength > plan.maxBytes || bytes.byteLength > ceiling) {
      throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '内置示例超过资源限额');
    }
    await sink.write(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
    checkCall(ctx);
    const mime = matrix.endsWith('.jpg') ? 'image/jpeg' : matrix.endsWith('.webp') ? 'image/webp' : 'image/png';
    return { statusCode: 200, finalUrl: plan.url, headers: [{ name: 'Content-Type', value: mime }],
      body: '', bytes: bytes.byteLength };
  }

  private readFile(filename: string): string {
    if (!/^[a-z0-9_]+\.(json|html)$/.test(filename)) { throw new AppError(ErrorCode.POLICY_DENIED, '样本文件标识无效'); }
    const variant = filename !== 'index.json' && this.revision() === 2 ? 'v2/' : '';
    const bytes = this.context.resourceManager.getRawFileContentSync('demo-fixtures/' + variant + filename);
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes);
  }
}
