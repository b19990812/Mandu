import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';

// Fixed public manifest format, derived by static inspection of the site's decoder.
// Remote scripts are never loaded or evaluated by the application.
export class HipFormat {
  decode(raw: string): JsonNode {
    if (raw.length > 2097152 || !raw.startsWith('qM9') || !raw.endsWith('Z7')) { return this.fail(); }
    const body = raw.slice(3,-2); const length = body.length - 5;
    const last = Math.floor(length / 3); const first = Math.floor((length - last) / 2); const middle = length - last - first;
    if (length <= 0 || body.slice(first,first + 2) !== 'Vx' || body.slice(first + 2 + middle,first + 5 + middle) !== 'pL0') { return this.fail(); }
    const reordered = body.slice(first + 5 + middle) + body.slice(0,first) + body.slice(first + 2,first + 2 + middle);
    let chunks = ''; for (let offset = 0; offset < reordered.length; offset += 7) { const part = reordered.slice(offset,offset + 7); chunks += Math.floor(offset / 7) % 2 ? part.split('').reverse().join('') : part; }
    const from = '_-9876543210abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const to = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let encoded = ''; for (let i = 0; i < chunks.length; i++) { const index = from.indexOf(chunks.charAt(i)); if (index < 0) { return this.fail(); } encoded += to.charAt(index); }
    encoded += '='.repeat((4 - encoded.length % 4) % 4);
    try { const bytes = new util.Base64Helper().decodeSync(encoded); return new JsonExtractor().parse(util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(bytes)); }
    catch (_) { return this.fail(); }
  }
  private fail(): never { throw new AppError(ErrorCode.PARSE_ERROR,'HIP 图片清单格式不受支持'); }
  images(node: JsonNode,order: string,sid: string): string[] {
    const data = node.kind === 'string' ? this.decode(node.scalar) : node;
    if (data.kind !== 'array' || data.items.length < 1 || data.items.length > 2001 || data.items.some((item: JsonNode) => item.kind !== 'string' || !item.scalar || item.scalar.length > 8192)) { return this.fail(); }
    const output = data.items.map((item: JsonNode) => item.scalar);
    // The API includes one non-page entry. Preserve the site's exact integer arithmetic.
    if (!/^(0|[1-9][0-9]{0,9})$/.test(order) || !/^(0|[1-9][0-9]{0,9})$/.test(sid) || Number(order) > 4294967295 || Number(sid) > 4294967295) { return this.fail(); }
    const mask = (BigInt(sid) * BigInt('2654435761') ^ BigInt(output.length) * BigInt('2246822507')) % BigInt(output.length);
    const remove = Number(BigInt(order) ^ mask);
    if (remove < 0 || remove >= output.length) { return this.fail(); }
    output.splice(remove,1); if (output.length < 1) { return this.fail(); } return output;
  }
}
