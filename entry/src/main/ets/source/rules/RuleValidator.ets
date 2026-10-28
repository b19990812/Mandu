import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { UrlPolicy } from '../../network/UrlPolicy';
import { SourceSiteAddress } from '../SourceSiteAddress';
import { sourceSiteDefinitions } from '../SourceSiteCatalog';
import { HtmlNode } from './HtmlExtractor';
import { JsonExtractor, JsonNode } from './JsonExtractor';
import { RuleDefinition, RuleField, RuleOperation, RuleQuery, ValidatedRulePackage } from './RuleTypes';
import { SelectorSubset } from './SelectorSubset';

const OPS: string[] = ['search', 'details', 'chapters', 'pages'];
const TRANSFORMS: string[] = ['trim', 'collapseWhitespace', 'string', 'integer', 'urlAbsolute'];

// No object casts from untrusted JSON. Unknown keys and unsupported features fail closed.
export class RuleValidator {
  parse(text: string): ValidatedRulePackage {
    // UTF-16 first bound, then exact UTF-8 bound without allocating another whole payload.
    if (text.length > 262144) { this.fail('$', '规则超过256KiB'); }
    let bytes = 0;
    for (let i = 0; i < text.length; i++) {
      const c = text.charCodeAt(i);
      if (c < 128) { bytes++; } else if (c < 2048) { bytes += 2; }
      else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length && text.charCodeAt(i + 1) >= 0xDC00 && text.charCodeAt(i + 1) <= 0xDFFF) { bytes += 4; i++; }
      else { bytes += 3; }
      if (bytes > 262144) { this.fail('$', '规则超过256KiB'); }
    }
    const root = new JsonExtractor().parse(text);
    this.keys(root, ['id', 'name', 'sourceVersion', 'ruleFormatVersion', 'engineMin', 'engineMax', 'baseUrl', 'allowedHosts', 'capabilities', 'operations', 'imageHeaders'], '$');
    const id = this.string(root, 'id', '$', 128);
    if (!/^[a-z0-9][a-z0-9._-]{0,127}$/.test(id) || sourceSiteDefinitions().some((site) => site.sourceId === id)) {
      this.fail('$.id', 'ID无效或与内置专用适配器冲突');
    }
    const name = this.string(root, 'name', '$', 80).trim();
    if (name === '') { this.fail('$.name', '名称不能为空'); }
    const sourceVersion = this.integer(root, 'sourceVersion', '$');
    const formatVersion = this.integer(root, 'ruleFormatVersion', '$');
    const min = this.integer(root, 'engineMin', '$');
    const max = this.integer(root, 'engineMax', '$');
    if (formatVersion !== 1 || min > 1 || max < 1 || min > max) {
      throw new AppError(ErrorCode.ENGINE_INCOMPATIBLE, '规则格式或引擎版本不兼容');
    }
    const address = new SourceSiteAddress();
    const baseUrl = address.normalize(this.string(root, 'baseUrl', '$', 2048));
    const allowedHosts = this.strings(this.child(root, 'allowedHosts', '$'), '$.allowedHosts', 16);
    if (allowedHosts.length === 0) { this.fail('$.allowedHosts', '域名清单不能为空'); }
    allowedHosts.forEach((host: string) => {
      if (host !== host.toLowerCase() || new url.URL(address.normalize('https://' + host + '/')).hostname !== host) {
        this.fail('$.allowedHosts', '必须为准确的小写公网域名');
      }
    });
    const policy = new UrlPolicy(allowedHosts);
    policy.validate(baseUrl);
    const capabilities = this.strings(this.child(root, 'capabilities', '$'), '$.capabilities', 4);
    if (capabilities.length !== 4 || OPS.some((op: string) => capabilities.indexOf(op) < 0)) {
      this.fail('$.capabilities', '当前规则必须且只能声明四类数据操作');
    }
    const definitions = this.child(root, 'operations', '$');
    this.keys(definitions, OPS, '$.operations');
    const operations: RuleOperation[] = [];
    let format = '';
    OPS.forEach((op: string) => {
      const parsed = this.operation(this.child(definitions, op, '$.operations'), op, policy, baseUrl);
      const node = this.child(this.child(definitions, op, '$.operations'), 'extract', '$.operations.' + op);
      const opFormat = this.string(node, 'format', '$.operations.' + op + '.extract', 4);
      if (format !== '' && format !== opFormat) { this.fail('$.operations', '引擎1暂不支持单源混用两种提取格式'); }
      format = opFormat; operations.push(parsed);
    });
    const definition: RuleDefinition = { id: id, version: sourceVersion, format: format, operations: operations,
      imageHeaders: this.headers(root.members.get('imageHeaders'), '$.imageHeaders', policy) };
    return { id: id, name: name, sourceVersion: sourceVersion, ruleFormatVersion: formatVersion,
      engineMin: min, engineMax: max, baseUrl: baseUrl, allowedHosts: allowedHosts,
      capabilities: capabilities, definition: definition };
  }

  private operation(node: JsonNode, name: string, policy: UrlPolicy, base: string): RuleOperation {
    const p = '$.operations.' + name;
    this.keys(node, ['request', 'extract', 'pagination'], p);
    const request = this.child(node, 'request', p);
    this.keys(request, ['method', 'path', 'query', 'headers'], p + '.request');
    if (this.string(request, 'method', p + '.request', 8) !== 'GET') { this.fail(p + '.request.method', '仅支持匿名GET'); }
    const path = this.string(request, 'path', p + '.request', 1024);
    if (!path.startsWith('/') || path.startsWith('//') || /[?#\\\u0000-\u0020\u007f]/.test(path)) { this.fail(p + '.request.path', '必须为站内路径，查询参数放query'); }
    this.template(path, name, p + '.request.path');
    policy.resolve(path.replace(/\{\{[a-zA-Z]+\}\}/g, 'x'), base);
    const query: RuleQuery[] = [];
    const queryNode = request.members.get('query');
    if (queryNode) {
      this.object(queryNode, p + '.request.query');
      if (queryNode.members.size > 20) { this.fail(p + '.request.query', '查询参数过多'); }
      queryNode.members.forEach((value: JsonNode, key: string) => {
        if (!/^[a-zA-Z0-9_-]{1,64}$/.test(key) || value.kind !== 'string' || value.scalar.length > 1024) { this.fail(p + '.request.query', '查询字段无效'); }
        this.template(value.scalar, name, p + '.request.query.' + key);
        query.push({ name: key, value: value.scalar });
      });
    }
    const extract = this.child(node, 'extract', p);
    this.keys(extract, ['format', 'items', 'object', 'requiredMarker', 'emptyMarker', 'fields'], p + '.extract');
    const format = this.string(extract, 'format', p + '.extract', 4);
    if (format !== 'json' && format !== 'html') { this.fail(p + '.extract.format', '不支持的格式'); }
    const location = this.string(extract, name === 'details' ? 'object' : 'items', p + '.extract', 256);
    if (extract.members.has(name === 'details' ? 'items' : 'object')) { this.fail(p + '.extract', '集合与详情定位字段不能混用'); }
    this.expression(location, format, p + '.extract');
    let marker: string | undefined = undefined;
    let empty: string | undefined = undefined;
    if (format === 'html') {
      marker = this.string(extract, 'requiredMarker', p + '.extract', 256); this.expression(marker, format, p);
      empty = this.optionalString(extract, 'emptyMarker', p, 256); if (empty) { this.expression(empty, format, p); }
    } else if (extract.members.has('requiredMarker') || extract.members.has('emptyMarker')) { this.fail(p + '.extract', 'JSON规则不能包含HTML标记'); }
    const fieldsNode = this.child(extract, 'fields', p + '.extract');
    this.object(fieldsNode, p + '.extract.fields');
    if (fieldsNode.members.size === 0 || fieldsNode.members.size > 50) { this.fail(p + '.extract.fields', '字段数必须在1～50'); }
    const supported = name === 'search' ? ['remoteId', 'title', 'locator', 'cover'] :
      name === 'details' ? ['remoteId', 'title', 'locator', 'description', 'cover'] :
      name === 'chapters' ? ['remoteId', 'title', 'locator', 'ordinal'] : ['pageKey', 'imageUrl'];
    this.keys(fieldsNode, supported, p + '.extract.fields');
    const required = name === 'details' ? ['title'] : name === 'pages' ? ['pageKey', 'imageUrl'] :
      name === 'chapters' ? ['remoteId', 'title', 'locator', 'ordinal'] : ['remoteId', 'title', 'locator'];
    const fields: RuleField[] = [];
    fieldsNode.members.forEach((value: JsonNode, key: string) => fields.push(this.field(value, key, format, p + '.extract.fields.' + key)));
    required.forEach((key: string) => {
      if (!fields.some((field: RuleField) => field.name === key && field.required)) { this.fail(p + '.extract.fields.' + key, '标准必填字段必须声明required=true'); }
    });
    fields.forEach((field: RuleField) => {
      if (['locator', 'cover', 'imageUrl'].indexOf(field.name) >= 0 && (field.transforms || []).indexOf('urlAbsolute') < 0) { this.fail(p + '.extract.fields.' + field.name, 'URL字段必须显式urlAbsolute'); }
      if (field.name === 'ordinal' && (field.transforms || []).indexOf('integer') < 0) { this.fail(p + '.extract.fields.ordinal', '序号必须转为integer'); }
    });
    const pagination = this.child(node, 'pagination', p);
    this.keys(pagination, ['mode', 'start', 'nextPath', 'nextSelector', 'nextAttr'], p + '.pagination');
    const mode = this.string(pagination, 'mode', p + '.pagination', 8);
    if (mode !== 'none' && mode !== (format === 'json' ? 'page' : 'url') || name === 'details' && mode !== 'none') { this.fail(p + '.pagination.mode', '不支持的分页模式'); }
    let nextPath: string | undefined = undefined;
    let nextSelector: string | undefined = undefined;
    if (mode !== 'none') {
      if (this.integer(pagination, 'start', p + '.pagination') !== 1) { this.fail(p + '.pagination.start', '起始页必须为1'); }
      if (format === 'json') {
        if (pagination.members.has('nextSelector') || pagination.members.has('nextAttr')) { this.fail(p + '.pagination', 'JSON分页不接受HTML字段'); }
        nextPath = this.string(pagination, 'nextPath', p + '.pagination', 256); this.expression(nextPath, 'json', p);
      } else {
        if (pagination.members.has('nextPath')) { this.fail(p + '.pagination', 'HTML分页不接受JSON字段'); }
        nextSelector = this.string(pagination, 'nextSelector', p + '.pagination', 256); this.expression(nextSelector, 'html', p);
        if (this.string(pagination, 'nextAttr', p + '.pagination', 32) !== 'href') { this.fail(p + '.pagination.nextAttr', '当前URL分页仅支持href'); }
      }
    } else if (pagination.members.size !== 1) { this.fail(p + '.pagination', '无分页时仅允许mode'); }
    return { name: name, path: path, query: query, headers: this.headers(request.members.get('headers'), p + '.request.headers', policy),
      root: name === 'details' ? location : undefined, items: name !== 'details' ? location : undefined,
      requiredMarker: marker, emptyMarker: empty, fields: fields, nextPath: nextPath, nextSelector: nextSelector };
  }

  private field(node: JsonNode, name: string, format: string, path: string): RuleField {
    this.keys(node, format === 'json' ? ['from', 'required', 'default', 'transforms'] : ['selector', 'text', 'attr', 'required', 'default', 'transforms'], path);
    const requiredNode = node.members.get('required');
    if (requiredNode && requiredNode.kind !== 'boolean') { this.fail(path + '.required', '必须为布尔值'); }
    const fallback = this.optionalString(node, 'default', path, 4096);
    const transformsNode = node.members.get('transforms');
    const transforms = transformsNode ? this.strings(transformsNode, path + '.transforms', 8) : [];
    transforms.forEach((item: string) => { if (TRANSFORMS.indexOf(item) < 0) { this.fail(path + '.transforms', '不支持该转换'); } });
    const location = this.string(node, format === 'json' ? 'from' : 'selector', path, 256);
    this.expression(location, format, path);
    let attr: string | undefined = undefined;
    if (format === 'html') {
      attr = this.optionalString(node, 'attr', path, 64);
      const text = node.members.get('text');
      if (attr && text || !attr && (!text || text.kind !== 'boolean' || text.scalar !== 'true') || attr && !/^[a-zA-Z0-9_-]+$/.test(attr)) { this.fail(path, '必须选择text=true或单个attr'); }
      if (attr) { attr = attr.toLowerCase(); }
    }
    if (requiredNode && requiredNode.scalar === 'true' && fallback !== undefined) { this.fail(path, '必填字段不能用默认值隐藏缺失'); }
    return { name: name, from: format === 'json' ? location : undefined, selector: format === 'html' ? location : undefined,
      attribute: attr, required: requiredNode ? requiredNode.scalar === 'true' : false, defaultValue: fallback, transforms: transforms };
  }

  private headers(node: JsonNode | undefined, path: string, policy: UrlPolicy): RuleQuery[] {
    if (!node) { return []; }
    this.keys(node, ['Accept', 'Accept-Language', 'Referer', 'User-Agent'], path);
    const output: RuleQuery[] = [];
    node.members.forEach((value: JsonNode, key: string) => {
      if (value.kind !== 'string' || value.scalar.length > 1024 || /[\u0000-\u001f\u007f]/.test(value.scalar) || value.scalar.indexOf('{{') >= 0) { this.fail(path + '.' + key, '请求头无效'); }
      if (key === 'Referer') { policy.validate(value.scalar); }
      output.push({ name: key, value: value.scalar });
    });
    return output;
  }
  private template(value: string, operation: string, path: string): void {
    const allowed = operation === 'search' ? ['query', 'page'] : operation === 'pages' ? ['chapterId', 'page'] : ['mangaId', 'page'];
    const stripped = value.replace(/\{\{([a-zA-Z]+)\}\}/g, (_match: string, key: string): string => {
      if (allowed.indexOf(key) < 0) { this.fail(path, '模板变量不适用于该操作'); } return 'x';
    });
    if (/[{}\u0000-\u001f\u007f]/.test(stripped)) { this.fail(path, '模板格式无效'); }
  }
  private expression(value: string, format: string, path: string): void {
    try {
      if (format === 'json') {
        if (value === '$.' || value.endsWith('.')) { this.fail(path, 'JSON路径无效'); }
        new JsonExtractor().at(new JsonNode('object'), value);
      } else { new SelectorSubset().select(new HtmlNode('validation'), value); }
    } catch (_) { this.fail(path, '字段路径或选择器不受支持'); }
  }
  private object(node: JsonNode, path: string): void { if (node.kind !== 'object') { this.fail(path, '必须为对象'); } }
  private keys(node: JsonNode, allowed: string[], path: string): void {
    this.object(node, path);
    node.members.forEach((_value: JsonNode, key: string) => { if (allowed.indexOf(key) < 0) { this.fail(path, '包含未知字段'); } });
  }
  private child(node: JsonNode, key: string, path: string): JsonNode {
    const value = node.members.get(key); if (!value) { return this.fail(path + '.' + key, '必填字段缺失'); } return value;
  }
  private string(node: JsonNode, key: string, path: string, max: number): string {
    const value = this.child(node, key, path);
    if (value.kind !== 'string' || value.scalar.length === 0 || value.scalar.length > max || /[\u0000-\u001f\u007f]/.test(value.scalar)) { this.fail(path + '.' + key, '字符串无效'); }
    return value.scalar;
  }
  private optionalString(node: JsonNode, key: string, path: string, max: number): string | undefined {
    const value = node.members.get(key); if (!value) { return undefined; }
    if (value.kind !== 'string' || value.scalar.length > max || /[\u0000-\u001f\u007f]/.test(value.scalar)) { this.fail(path + '.' + key, '字符串无效'); }
    return value.scalar;
  }
  private integer(node: JsonNode, key: string, path: string): number {
    const value = this.child(node, key, path); const number = Number(value.scalar);
    if (value.kind !== 'number' || !/^[1-9][0-9]*$/.test(value.scalar) || !Number.isSafeInteger(number) || number > 2147483647) { this.fail(path + '.' + key, '必须为正整数'); }
    return number;
  }
  private strings(node: JsonNode, path: string, max: number): string[] {
    if (node.kind !== 'array' || node.items.length > max) { this.fail(path, '数组格式或数量无效'); }
    const output: string[] = [];
    node.items.forEach((value: JsonNode) => {
      if (value.kind !== 'string' || value.scalar.length === 0 || value.scalar.length > 256 || output.indexOf(value.scalar) >= 0) { this.fail(path, '数组项无效或重复'); }
      output.push(value.scalar);
    }); return output;
  }
  private fail(path: string, message: string): never { throw new AppError(ErrorCode.RULE_INVALID, path + '：' + message); }
}
