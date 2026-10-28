import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { CallContext } from '../../model/RequestTypes';
import { ChapterRef, ImageRequest, MangaDetail, MangaSummary, PageRef, PageToken,
  Source, SourceBatch, SourceRef } from '../../model/SourceTypes';
import { Transport, TransportResponse } from '../../network/Transport';
import { UrlPolicy } from '../../network/UrlPolicy';
import { checkCall, requireHttpSuccess } from '../SourceHttp';
import { HtmlExtractor, HtmlNode } from './HtmlExtractor';
import { JsonExtractor, JsonNode } from './JsonExtractor';
import { SelectorSubset } from './SelectorSubset';
import { RuleDefinition, RuleField, RuleOperation } from './RuleTypes';
import { refreshPage } from '../RefreshPage';

interface Extracted { rows: Map<string, string>[]; nextValue: string; nextKind: string; }

export class RuleSource implements Source {
  readonly id: string;
  readonly version: number;
  private readonly rule: RuleDefinition;
  private readonly baseUrl: string;
  private readonly policy: UrlPolicy;
  private readonly transport: Transport;
  private readonly activationRevision: string;

  constructor(rule: RuleDefinition, baseUrl: string, policy: UrlPolicy, transport: Transport, activationRevision: string = '') {
    this.rule = rule;
    this.id = rule.id;
    this.version = rule.version;
    this.baseUrl = policy.validate(baseUrl).toString();
    this.policy = policy;
    this.transport = transport;
    this.activationRevision = activationRevision || rule.version.toString();
    if (rule.format !== 'json' && rule.format !== 'html') { throw new AppError(ErrorCode.RULE_INVALID, '不支持的规则格式'); }
  }

  async search(query: string, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<MangaSummary>> {
    const data = await this.execute('search', query, '', token, ctx);
    const items = data.rows.map((row: Map<string, string>): MangaSummary => ({
      ref: this.ref(row), title: this.required(row, 'title'), cover: row.get('cover')
    }));
    return { items: items, next: this.next(data, 'search', query, '') };
  }

  async details(manga: SourceRef, ctx: CallContext): Promise<MangaDetail> {
    this.checkRef(manga);
    const data = await this.execute('details', '', manga.remoteId, undefined, ctx);
    const row = data.rows[0];
    if (!row) { throw new AppError(ErrorCode.PARSE_ERROR, '详情对象缺失'); }
    return {
      ref: { sourceId: this.id, remoteId: row.get('remoteId') || manga.remoteId, locator: row.get('locator') || manga.locator },
      title: this.required(row, 'title'), authors: [], tags: [], description: row.get('description') || '',
      status: 'unknown', cover: row.get('cover')
    };
  }

  async chapters(manga: SourceRef, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<ChapterRef>> {
    this.checkRef(manga);
    const data = await this.execute('chapters', '', manga.remoteId, token, ctx);
    const items = data.rows.map((row: Map<string, string>): ChapterRef => ({
      ref: this.ref(row), mangaRemoteId: manga.remoteId, title: this.required(row, 'title'),
      ordinal: this.integer(this.required(row, 'ordinal'))
    }));
    return { items: items, next: this.next(data, 'chapters', '', manga.remoteId) };
  }

  async pages(chapter: SourceRef, token: PageToken | undefined, ctx: CallContext): Promise<SourceBatch<PageRef>> {
    this.checkRef(chapter);
    const data = await this.execute('pages', '', chapter.remoteId, token, ctx);
    const items = data.rows.map((row: Map<string, string>, index: number): PageRef => {
      const imageUrl = this.required(row, 'imageUrl');
      return { pageKey: this.required(row, 'pageKey'), ordinal: index, locator: imageUrl, imageUrl: imageUrl };
    });
    return { items: items, next: this.next(data, 'pages', '', chapter.remoteId) };
  }

  async resolveImage(chapter: SourceRef, page: PageRef, forceRefresh: boolean, ctx: CallContext): Promise<ImageRequest> {
    this.checkRef(chapter);
    checkCall(ctx);
    if (forceRefresh) { return this.resolveImage(chapter,await refreshPage(this,chapter,page.pageKey,ctx),false,ctx); }
    if (!page.imageUrl) { throw new AppError(ErrorCode.PARSE_ERROR, '图片地址缺失'); }
    return { url: this.policy.validate(page.imageUrl).toString(), headers: (this.rule.imageHeaders || []).slice(), contentRevision: this.activationRevision };
  }

  private async execute(name: string, query: string, remoteId: string,
    token: PageToken | undefined, ctx: CallContext): Promise<Extracted> {
    checkCall(ctx);
    if (query.length > 256 || remoteId.length > 512 || token && token.value.length > 2048) {
      throw new AppError(ErrorCode.RULE_INVALID, '源请求参数过长');
    }
    if (ctx.ruleRevision !== this.version) { throw new AppError(ErrorCode.CONTENT_CHANGED, '源规则版本已改变'); }
    const operation = this.rule.operations.find((item: RuleOperation) => item.name === name);
    if (!operation || operation.fields.length > 50) { throw new AppError(ErrorCode.RULE_INVALID, '源操作或字段映射无效'); }
    if (token && token.binding !== this.binding(name, query, remoteId)) {
      throw new AppError(ErrorCode.RULE_INVALID, '分页标记不属于当前操作');
    }
    if (token && token.kind !== 'page' && token.kind !== 'url') { throw new AppError(ErrorCode.RULE_INVALID, '分页类型无效'); }
    const params: Map<string, string> = new Map();
    params.set('query', query); params.set('mangaId', remoteId); params.set('chapterId', remoteId);
    params.set('page', token && token.kind === 'page' ? token.value : '1');
    if (!/^[1-9][0-9]{0,5}$/.test(params.get('page') || '')) { throw new AppError(ErrorCode.RULE_INVALID, '页码无效'); }
    let address = this.policy.resolve(this.render(operation.path, params), this.baseUrl);
    if (token && token.kind === 'url') { address = this.policy.resolve(token.value, this.baseUrl); }
    else {
      const parsed = new url.URL(address);
      const queryPairs = (operation.query || []).map((pair): string =>
        encodeURIComponent(pair.name) + '=' + encodeURIComponent(this.render(pair.value, params, false)));
      if (queryPairs.length > 0) { parsed.search = '?' + queryPairs.join('&'); }
      address = this.policy.validate(parsed.toString()).toString();
    }
    const headers = (operation.headers || []).slice();
    if (!headers.some((pair) => pair.name.toLowerCase() === 'accept')) {
      headers.push({ name: 'Accept', value: this.rule.format === 'json' ? 'application/json' : 'text/html' });
    }
    const response = await this.transport.send({
      sourceId: this.id, url: address, maxBytes: 2097152,
      headers: headers
    }, ctx);
    requireHttpSuccess(response);
    checkCall(ctx);
    return this.rule.format === 'json' ? this.json(operation, response) : this.html(operation, response);
  }

  private json(operation: RuleOperation, response: TransportResponse): Extracted {
    const parser = new JsonExtractor();
    const root = parser.parse(response.body);
    const selected = parser.at(root, operation.root || operation.items || '$');
    if (!selected || (operation.name === 'details' ? selected.kind !== 'object' : selected.kind !== 'array')) {
      throw new AppError(ErrorCode.PARSE_ERROR, 'JSON集合或对象字段缺失');
    }
    const nodes: JsonNode[] = operation.name === 'details' ? [selected] : selected.items;
    const rows = nodes.map((node: JsonNode): Map<string, string> => {
      const row: Map<string, string> = new Map();
      operation.fields.forEach((field: RuleField) => {
        const value = parser.at(node, field.from || field.name);
        if (value && value.kind !== 'null' && value.kind !== 'object' && value.kind !== 'array') {
          if (value.kind !== 'string' && (field.transforms || []).indexOf('string') < 0 &&
            (field.transforms || []).indexOf('integer') < 0) {
            throw new AppError(ErrorCode.PARSE_ERROR, '字段类型不符：' + field.name);
          }
          row.set(field.name, this.transform(value.scalar, field, response.finalUrl));
        } else { this.missing(row, field); }
      });
      return row;
    });
    const next = operation.nextPath ? parser.at(root, operation.nextPath) : undefined;
    if (operation.nextPath && !next) { throw new AppError(ErrorCode.PARSE_ERROR, '分页字段缺失'); }
    if (next && next.kind !== 'null' && (next.kind !== 'number' && next.kind !== 'string' || this.integer(next.scalar) < 1)) {
      throw new AppError(ErrorCode.PARSE_ERROR, '下一页标记无效');
    }
    return { rows: rows, nextValue: next && next.kind !== 'null' ? next.scalar : '', nextKind: 'page' };
  }

  private html(operation: RuleOperation, response: TransportResponse): Extracted {
    const root = new HtmlExtractor().parse(response.body);
    const selector = new SelectorSubset();
    if (!operation.requiredMarker || selector.select(root, operation.requiredMarker).length === 0) {
      throw new AppError(ErrorCode.PARSE_ERROR, 'HTML内容标识缺失');
    }
    const nodes = selector.select(root, operation.items || operation.root || 'body');
    if (nodes.length === 0 && (!operation.emptyMarker || selector.select(root, operation.emptyMarker).length === 0)) {
      throw new AppError(ErrorCode.EMPTY_UNEXPECTED, 'HTML结构变化，未找到预期内容');
    }
    const rows = nodes.map((node: HtmlNode): Map<string, string> => {
      const row: Map<string, string> = new Map();
      operation.fields.forEach((field: RuleField) => {
        const selected = selector.select(node, field.selector || 'self')[0];
        if (!selected || field.attribute && !selected.attrs.has(field.attribute)) { this.missing(row, field); }
        else { row.set(field.name, this.transform(field.attribute ? selected.attribute(field.attribute) : selected.textContent(), field, response.finalUrl)); }
      });
      return row;
    });
    const next = operation.nextSelector ? selector.select(root, operation.nextSelector)[0] : undefined;
    return { rows: rows, nextValue: next ? this.policy.resolve(next.attribute('href'), response.finalUrl) : '', nextKind: 'url' };
  }

  private transform(input: string, field: RuleField, base: string): string {
    const maximum = field.name === 'description' ? 16384 : field.name === 'title' ? 1024 : field.name === 'remoteId' ? 512 : 2048;
    if (input.length > maximum) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '字段超过长度限额：' + field.name); }
    let value = input;
    const transforms = field.transforms || [];
    if (transforms.length > 8) { throw new AppError(ErrorCode.RULE_INVALID, '字段转换次数超限'); }
    transforms.forEach((name: string) => {
      if (name === 'trim') { value = value.trim(); }
      else if (name === 'collapseWhitespace') { value = value.replace(/\s+/g, ' ').trim(); }
      else if (name === 'urlAbsolute') { value = this.policy.resolve(value, base); }
      else if (name === 'integer') { value = this.integer(value).toString(); }
      else if (name !== 'string') { throw new AppError(ErrorCode.RULE_INVALID, '不支持该字段转换'); }
    });
    if (field.required && value === '') { throw new AppError(ErrorCode.PARSE_ERROR, '必填字段为空：' + field.name); }
    if (value.length > maximum) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '转换后字段超过长度限额：' + field.name); }
    return value;
  }

  private missing(row: Map<string, string>, field: RuleField): void {
    if (field.required) { throw new AppError(ErrorCode.PARSE_ERROR, '必填字段缺失：' + field.name); }
    if (field.defaultValue !== undefined) { row.set(field.name, field.defaultValue); }
  }

  private required(row: Map<string, string>, key: string): string {
    const value = row.get(key);
    if (value === undefined || value === '') { throw new AppError(ErrorCode.PARSE_ERROR, '标准字段缺失：' + key); }
    return value;
  }

  private integer(value: string): number {
    const number = Number(value);
    if (!/^[0-9]+$/.test(value) || !Number.isSafeInteger(number)) { throw new AppError(ErrorCode.PARSE_ERROR, '序号不是非负安全整数'); }
    return number;
  }

  private ref(row: Map<string, string>): SourceRef {
    return { sourceId: this.id, remoteId: this.required(row, 'remoteId'), locator: this.required(row, 'locator') };
  }

  private checkRef(ref: SourceRef): void {
    if (ref.sourceId !== this.id) { throw new AppError(ErrorCode.RULE_INVALID, '资源不属于当前源'); }
  }

  private render(template: string, params: Map<string, string>, encode: boolean = true): string {
    const result = template.replace(/\{\{([a-zA-Z]+)\}\}/g, (_whole: string, key: string): string => {
      const value = params.get(key);
      if (value === undefined) { throw new AppError(ErrorCode.RULE_INVALID, '模板变量不受支持'); }
      return encode ? encodeURIComponent(value) : value;
    });
    if (result.indexOf('{{') >= 0 || result.indexOf('}}') >= 0) { throw new AppError(ErrorCode.RULE_INVALID, '模板格式无效'); }
    return result;
  }

  private binding(operation: string, query: string, remoteId: string): string {
    return JSON.stringify([this.id, this.version.toString(), this.activationRevision, operation, query, remoteId]);
  }

  private next(data: Extracted, operation: string, query: string, remoteId: string): PageToken | undefined {
    return data.nextValue === '' ? undefined : {
      kind: data.nextKind, value: data.nextValue, binding: this.binding(operation, query, remoteId)
    };
  }
}
