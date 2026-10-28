import { Parser } from '@ohos/htmlparser2';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { checkParseText } from './ParseLimits';

export class HtmlNode {
  tag: string;
  text: string = '';
  attrs: Map<string, string> = new Map();
  children: HtmlNode[] = [];
  parent?: HtmlNode;

  constructor(tag: string) { this.tag = tag; }

  attribute(name: string): string { return this.attrs.get(name) || ''; }
  textContent(): string {
    if (this.tag === 'script' || this.tag === 'style') { return ''; }
    return this.tag === '#text' ? this.text : this.children.map((node: HtmlNode) => node.textContent()).join('');
  }
}

class HtmlTreeEvents {
  readonly root: HtmlNode = new HtmlNode('#document');
  private stack: HtmlNode[] = [this.root];
  private nodes: number = 0;

  onopentag(name: string, attributes: Record<string, string>, _implied: boolean): void {
    if (++this.nodes > 50000 || this.stack.length >= 65) {
      throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, 'HTML节点数或嵌套深度超限');
    }
    const node = new HtmlNode(name.toLowerCase());
    Object.keys(attributes).forEach((key: string) => node.attrs.set(key.toLowerCase(), attributes[key]));
    const parent = this.stack[this.stack.length - 1];
    node.parent = parent;
    parent.children.push(node);
    this.stack.push(node);
  }

  onclosetag(_name: string, _implied: boolean): void {
    if (this.stack.length > 1) { this.stack.pop(); }
  }

  ontext(text: string): void {
    const parent = this.stack[this.stack.length - 1];
    if (text === '' || parent.tag === 'script' || parent.tag === 'style') { return; }
    if (++this.nodes > 50000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, 'HTML节点数超限'); }
    const node = new HtmlNode('#text');
    node.text = text;
    node.parent = parent;
    parent.children.push(node);
  }
}

export class HtmlExtractor {
  parse(text: string): HtmlNode {
    checkParseText(text);
    const handler = new HtmlTreeEvents();
    try {
      const parser = new Parser(handler, { decodeEntities: true, lowerCaseTags: true, lowerCaseAttributeNames: true });
      parser.end(text);
      return handler.root;
    } catch (error) {
      if (error instanceof AppError) { throw error; }
      throw new AppError(ErrorCode.PARSE_ERROR, 'HTML解析失败');
    }
  }
}
