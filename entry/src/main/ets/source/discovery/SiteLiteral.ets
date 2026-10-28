import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { checkParseText } from '../../parsing/ParseLimits';
import { AppError, ErrorCode } from '../../model/ErrorTypes';

// COPY publishes a data-only, single-quoted list attribute. Parse only literal
// JSON/Python scalars, arrays and objects; never execute website expressions.
export function parseSiteLiteral(raw: string): JsonNode {
  checkParseText(raw); let result = ''; let at = 0;
  const fail = (): void => { throw new AppError(ErrorCode.PARSE_ERROR,'网站列表不是受支持的纯数据格式'); };
  while (at < raw.length) {
    const char = raw.charAt(at++);
    if (char === '"' || char === "'") {
      const quote = char; let value = ''; let closed = false;
      while (at < raw.length) {
        const next = raw.charAt(at++);
        if (next === quote) { closed = true; break; }
        if (next !== '\\') { if (next.charCodeAt(0) < 32) { fail(); } value += next; continue; }
        const escaped = raw.charAt(at++);
        if (escaped === 'u') { const hex = raw.substring(at,at + 4); if (!/^[0-9a-fA-F]{4}$/.test(hex)) { fail(); } value += String.fromCharCode(parseInt(hex,16)); at += 4; }
        else if (escaped === 'n') { value += '\n'; } else if (escaped === 'r') { value += '\r'; } else if (escaped === 't') { value += '\t'; }
        else if (escaped === 'b') { value += '\b'; } else if (escaped === 'f') { value += '\f'; }
        else if (['\\','/','"',"'"].indexOf(escaped) >= 0) { value += escaped; } else { fail(); }
      }
      if (!closed) { fail(); } result += JSON.stringify(value);
    } else if (/[\s\[\]{}:,.0-9eE+\-]/.test(char)) { result += char; }
    else {
      const rest = raw.substring(at - 1); const word = /^(?:None|True|False|null|true|false)\b/.exec(rest);
      if (!word) { fail(); } else { result += word[0] === 'None' ? 'null' : word[0] === 'True' ? 'true' : word[0] === 'False' ? 'false' : word[0]; at += word[0].length - 1; }
    }
  }
  return new JsonExtractor().parse(result);
}
