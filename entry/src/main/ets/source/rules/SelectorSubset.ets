import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { HtmlNode } from './HtmlExtractor';

class SelectorStep {
  pattern: string;
  direct: boolean;
  constructor(pattern: string, direct: boolean) { this.pattern = pattern; this.direct = direct; }
}

export class SelectorSubset {
  select(root: HtmlNode, selector: string): HtmlNode[] {
    if (selector === 'self') { return [root]; }
    const steps = this.steps(selector);
    let current: HtmlNode[] = [root];
    steps.forEach((step: SelectorStep) => {
      const next: HtmlNode[] = [];
      const seen: Set<HtmlNode> = new Set();
      current.forEach((parent: HtmlNode) => {
        this.walk(parent, step, next, seen);
      });
      current = next;
    });
    return current;
  }

  private walk(parent: HtmlNode, step: SelectorStep, output: HtmlNode[], seen: Set<HtmlNode>): void {
    parent.children.forEach((node: HtmlNode) => {
      if (node.tag !== '#text' && this.matches(node, step.pattern) && !seen.has(node)) { output.push(node); seen.add(node); }
      if (!step.direct) { this.walk(node, step, output, seen); }
    });
  }

  private steps(selector: string): SelectorStep[] {
    if (selector.length === 0 || selector.length > 256 || selector.indexOf('\\') >= 0) {
      throw new AppError(ErrorCode.RULE_INVALID, '选择器不在支持的子集中');
    }
    const output: SelectorStep[] = [];
    let token = '';
    let bracket = 0;
    let quote = '';
    let direct = false;
    for (let i = 0; i < selector.length; i++) {
      const char = selector.charAt(i);
      if (quote !== '') { token += char; if (char === quote) { quote = ''; } continue; }
      if (bracket > 0 && (char === '"' || char === "'")) { quote = char; token += char; continue; }
      if (char === '[') { bracket++; }
      if (char === ']') { bracket--; }
      if (bracket < 0 || bracket > 1) { throw new AppError(ErrorCode.RULE_INVALID, '属性选择器无效'); }
      if (bracket === 0 && (char === '>' || /\s/.test(char))) {
        if (token !== '') { output.push(new SelectorStep(token, direct)); token = ''; direct = false; }
        if (char === '>') {
          if (output.length === 0 || direct) { throw new AppError(ErrorCode.RULE_INVALID, '子代选择器无效'); }
          direct = true;
        }
      } else { token += char; }
    }
    if (quote !== '' || bracket !== 0 || token === '' && direct) {
      throw new AppError(ErrorCode.RULE_INVALID, '选择器未闭合');
    }
    if (token !== '') { output.push(new SelectorStep(token, direct)); }
    if (output.length === 0 || output.length > 8) { throw new AppError(ErrorCode.RULE_INVALID, '选择器长度超限'); }
    output.forEach((step: SelectorStep) => { this.matches(new HtmlNode('validation'), step.pattern); });
    return output;
  }

  private matches(node: HtmlNode, pattern: string): boolean {
    let rest = pattern;
    let matched = true;
    const tag = /^[a-zA-Z][a-zA-Z0-9_-]*|^\*/.exec(rest);
    if (tag) {
      if (tag[0] !== '*' && node.tag !== tag[0].toLowerCase()) { matched = false; }
      rest = rest.substring(tag[0].length);
    }
    while (rest !== '') {
      const identity = /^([.#])([a-zA-Z0-9_-]+)/.exec(rest);
      if (identity) {
        if (identity[1] === '#' && node.attribute('id') !== identity[2]) { matched = false; }
        if (identity[1] === '.' && node.attribute('class').split(/\s+/).indexOf(identity[2]) < 0) { matched = false; }
        rest = rest.substring(identity[0].length);
        continue;
      }
      const attribute = /^\[([a-zA-Z0-9_-]+)(?:=(?:"([^"]*)"|'([^']*)'|([a-zA-Z0-9_.-]+)))?\]/.exec(rest);
      if (attribute) {
        const name = attribute[1].toLowerCase();
        if (!node.attrs.has(name)) { matched = false; }
        const expected = attribute[2] !== undefined ? attribute[2] : attribute[3] !== undefined ? attribute[3] : attribute[4];
        if (expected !== undefined && node.attribute(name) !== expected) { matched = false; }
        rest = rest.substring(attribute[0].length);
        continue;
      }
      throw new AppError(ErrorCode.RULE_INVALID, '不支持该选择器语法');
    }
    return matched;
  }
}
