import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { checkParseText } from '../../parsing/ParseLimits';

// Read only JSON flight records published by the website. Never evaluate script,
// module references or expressions. Keep this protocol local to Vomic.
export class VomicFormat {
  private readonly rows: Map<string, JsonNode> = new Map();
  private visited: number = 0;

  reader(html: string): JsonNode {
    checkParseText(html); this.rows.clear(); this.visited = 0;
    const pattern = /self\.__next_f\.push\((\[1,"(?:[^"\\]|\\.)*"\])\)/g;
    let stream = ''; let match: RegExpExecArray | null;
    while ((match = pattern.exec(html)) !== null) {
      const chunk = new JsonExtractor().parse(match[1]);
      stream += chunk.items[1].scalar;
      if (stream.length > 2097152) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'Vomic清单元数据过大'); }
    }
    stream.split('\n').forEach((line: string) => {
      const record = /^([0-9a-f]+):([\[{].*)$/.exec(line);
      if (!record) { return; }
      if (this.rows.has(record[1]) || this.rows.size >= 4096) { this.fail(); }
      this.rows.set(record[1],new JsonExtractor().parse(record[2]));
    });
    const matches: JsonNode[] = [];
    this.rows.forEach((node: JsonNode) => this.findReader(node,matches,0));
    if (matches.length !== 1) { return this.fail(); }
    const props = matches[0]; const login = props.members.get('isLogin');
    if (!login || login.kind !== 'boolean') { return this.fail(); }
    if (login.scalar !== 'true') { throw new AppError(ErrorCode.AUTH_REQUIRED,'Vomic阅读需要登录，请在来源网站登录并保存会话后重试'); }
    const chapter = this.resolve(props.members.get('chapterData'));
    if (chapter.kind !== 'object') { return this.fail(); }
    return chapter;
  }

  resolve(input: JsonNode | undefined): JsonNode {
    if (!input) { return this.fail(); }
    let node = input; const seen: Set<string> = new Set();
    while (node.kind === 'string' && /^\$[0-9a-f]+$/.test(node.scalar)) {
      const key = node.scalar.slice(1);
      if (seen.has(key) || seen.size >= 32) { return this.fail(); }
      seen.add(key); const next = this.rows.get(key); if (!next) { return this.fail(); } node = next;
    }
    return node;
  }

  private findReader(node: JsonNode,matches: JsonNode[],depth: number): void {
    if (++this.visited > 50000 || depth > 64) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'Vomic清单节点超限'); }
    if (node.kind === 'object' && node.members.has('chapterData') && node.members.has('isLogin')) { matches.push(node); return; }
    node.items.forEach((child: JsonNode) => this.findReader(child,matches,depth + 1));
    node.members.forEach((child: JsonNode) => this.findReader(child,matches,depth + 1));
  }

  private fail(): never { throw new AppError(ErrorCode.PARSE_ERROR,'Vomic网站清单结构不受支持'); }
}
