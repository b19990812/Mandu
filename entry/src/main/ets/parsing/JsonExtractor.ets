import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkParseText } from './ParseLimits';

export class JsonNode {
  kind: string;
  scalar: string = '';
  members: Map<string, JsonNode> = new Map();
  items: JsonNode[] = [];
  constructor(kind: string) { this.kind = kind; }
}

// Small bounded JSON tree: numeric lexemes are preserved, including remote IDs > 2^53.
export class JsonExtractor {
  private text: string = '';
  private offset: number = 0;
  private nodes: number = 0;

  parse(text: string): JsonNode {
    checkParseText(text);
    this.text = text;
    this.offset = 0;
    this.nodes = 0;
    try {
      const root = this.value(0);
      this.space();
      if (this.offset !== this.text.length) { this.fail(); }
      return root;
    } finally { this.text = ''; }
  }

  at(root: JsonNode, path: string): JsonNode | undefined {
    if (path === '$' || path === '') { return root; }
    if (path.length > 256) { throw new AppError(ErrorCode.RULE_INVALID, 'JSON路径过长'); }
    if (path.startsWith('$') && !path.startsWith('$.') && !path.startsWith('$[')) {
      throw new AppError(ErrorCode.RULE_INVALID, 'JSON根路径格式无效');
    }
    let rest = path.startsWith('$.') ? path.substring(2) : path.startsWith('$[') ? path.substring(1) : path;
    let node: JsonNode | undefined = root;
    let steps = 0;
    while (rest !== '') {
      if (++steps > 64) { throw new AppError(ErrorCode.RULE_INVALID, 'JSON路径过深'); }
      const key = /^[a-zA-Z0-9_-]+/.exec(rest);
      const index = /^\[(0|[1-9][0-9]*)\]/.exec(rest);
      if (key) {
        node = node && node.kind === 'object' ? node.members.get(key[0]) : undefined;
        rest = rest.substring(key[0].length);
      } else if (index) {
        const position = Number(index[1]);
        node = node && node.kind === 'array' && Number.isSafeInteger(position) ? node.items[position] : undefined;
        rest = rest.substring(index[0].length);
      } else { throw new AppError(ErrorCode.RULE_INVALID, '不支持的JSON路径'); }
      if (rest.startsWith('.')) { rest = rest.substring(1); if (rest === '') { this.fail(); } }
      else if (rest !== '' && !rest.startsWith('[')) { throw new AppError(ErrorCode.RULE_INVALID, 'JSON路径格式无效'); }
    }
    return node;
  }

  private value(depth: number): JsonNode {
    this.space();
    if (depth > 64 || ++this.nodes > 50000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, 'JSON节点或嵌套深度超限'); }
    const char = this.text.charAt(this.offset);
    if (char === '"') { const node = new JsonNode('string'); node.scalar = this.string(); return node; }
    if (char === '{' || char === '[') {
      this.offset++;
      const node = new JsonNode(char === '{' ? 'object' : 'array');
      const close = char === '{' ? '}' : ']';
      this.space();
      if (this.text.charAt(this.offset) === close) { this.offset++; return node; }
      while (true) {
        if (node.kind === 'object') {
          const key = this.string();
          this.space();
          if (this.text.charAt(this.offset++) !== ':' || node.members.has(key)) { this.fail(); }
          node.members.set(key, this.value(depth + 1));
        } else { node.items.push(this.value(depth + 1)); }
        this.space();
        const separator = this.text.charAt(this.offset++);
        if (separator === close) { return node; }
        if (separator !== ',') { this.fail(); }
        this.space();
      }
    }
    const literal = /^(true|false|null)(?=[\s,}\]]|$)/.exec(this.text.substring(this.offset));
    if (literal) {
      this.offset += literal[0].length;
      const node = new JsonNode(literal[0] === 'null' ? 'null' : 'boolean');
      node.scalar = literal[0];
      return node;
    }
    const number = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?(?=[\s,}\]]|$)/.exec(this.text.substring(this.offset));
    if (number) {
      this.offset += number[0].length;
      const node = new JsonNode('number'); node.scalar = number[0]; return node;
    }
    return this.fail();
  }

  private string(): string {
    this.space();
    const begin = this.offset;
    if (this.text.charAt(this.offset++) !== '"') { return this.fail(); }
    let escaped = false;
    while (this.offset < this.text.length) {
      const char = this.text.charAt(this.offset++);
      if (char === '"' && !escaped) {
        try { return JSON.parse(this.text.substring(begin, this.offset)) as string; }
        catch (_) { return this.fail(); }
      }
      if (char.charCodeAt(0) < 32) { return this.fail(); }
      if (char === '\\' && !escaped) { escaped = true; } else { escaped = false; }
    }
    return this.fail();
  }

  private space(): void {
    while (this.offset < this.text.length && /[\u0020\t\r\n]/.test(this.text.charAt(this.offset))) { this.offset++; }
  }

  private fail(): never { throw new AppError(ErrorCode.PARSE_ERROR, 'JSON结构或字段类型无效'); }
}
