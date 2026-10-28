import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { PageRef, SourceRef } from '../../model/SourceTypes';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';
import { decompressLzBase64 } from '../../parsing/LzString';
import { checkParseText } from '../../parsing/ParseLimits';
import { UrlPolicy } from '../../network/UrlPolicy';

export const MANHUAGUI_ASSET_HOSTS: string[] = ['cf.hamreus.com','cf.mhgui.com','i.hamreus.com','eu.hamreus.com','us.hamreus.com'];
const DIGITS: string = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

function literal(raw: string): string {
  const escapes = new Map<string,string>([['n','\n'],['r','\r'],['t','\t'],['b','\b'],['f','\f'],['v','\v'],['\\','\\'],["'","'"],['"','"'],['/','/']]);
  let output = '';
  for (let i = 0; i < raw.length; i++) {
    if (raw.charAt(i) !== '\\') { output += raw.charAt(i); continue; }
    const char = raw.charAt(++i);
    if (char === 'x' || char === 'u') {
      const size = char === 'x' ? 2 : 4; const hex = raw.substring(i + 1,i + 1 + size);
      if (hex.length !== size || !/^[0-9a-fA-F]+$/.test(hex)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜脚本转义无效'); }
      output += String.fromCharCode(parseInt(hex,16)); i += size;
    } else if (escapes.has(char)) { output += escapes.get(char)!; }
    else { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜脚本字符串格式变化'); }
  }
  return output;
}

function unpack(script: string): string {
  // Only read P.A.C.K.E.R's literal arguments. The function body is never evaluated.
  const args = /}\s*\(\s*'((?:\\.|[^'\\])*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:\\.|[^'\\])*)'\s*(\[\s*'((?:\\.|[^'\\])*)'\s*\]|\.split)\s*\(\s*'((?:\\.|[^'\\])*)'\s*\)/.exec(script);
  if (!args) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜章节脚本结构变化'); }
  const radix = Number(args[2]); const count = Number(args[3]);
  if (radix < 2 || radix > 62 || count < 1 || count > 10000 || literal(args[7]) !== '|') { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜章节字典参数无效'); }
  const method = args[5] === '.split' ? 'split' : literal(args[6]);
  if (method !== 'split' && method !== 'splic') { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜章节字典格式变化'); }
  const words = (method === 'splic' ? decompressLzBase64(literal(args[4])) : literal(args[4])).split('|');
  if (words.length > count) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜章节字典数量不符'); }
  const packed = literal(args[1]); let expandedLength = packed.length;
  const decoded = packed.replace(/\b[0-9a-zA-Z]+\b/g,(token: string): string => {
    let number = 0;
    for (let i = 0; i < token.length; i++) {
      const digit = DIGITS.indexOf(token.charAt(i));
      if (digit >= radix) { return token; }
      number = number * radix + digit; if (number >= count) { return token; }
    }
    const word = words[number] || token; expandedLength += word.length - token.length;
    if (expandedLength > 2097152) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画柜章节脚本解码超限'); } return word;
  });
  checkParseText(decoded); return decoded;
}

export function manhuaguiReaderData(html: string): JsonNode {
  checkParseText(html);
  const scripts = /<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi;
  let match: RegExpExecArray | null;
  while ((match = scripts.exec(html)) !== null) {
    let script = match[1];
    if (/function\s*\(\s*p\s*,\s*a\s*,\s*c\s*,\s*k\s*,/.test(script)) { script = unpack(script); }
    const start = /\bSMH\s*\.\s*imgData\s*\(\s*/.exec(script);
    if (!start) { continue; }
    const begin = start.index + start[0].length;
    let depth = 0; let quoted = false; let escaped = false;
    for (let i = begin; i < script.length; i++) {
      const char = script.charAt(i);
      if (quoted) {
        if (char === '"' && !escaped) { quoted = false; }
        escaped = char === '\\' && !escaped; continue;
      }
      if (char === '"') { quoted = true; }
      else if (char === '{') { depth++; }
      else if (char === '}' && --depth === 0) { return new JsonExtractor().parse(script.substring(begin,i + 1)); }
    }
    throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜章节数据不完整');
  }
  throw new AppError(ErrorCode.EMPTY_UNEXPECTED,'漫画柜页面未提供图片清单，请检查网站会话或页面结构');
}

function scalar(node: JsonNode,key: string): string { return node.members.get(key)?.scalar || ''; }

export function manhuaguiPages(html: string,ref: SourceRef): PageRef[] {
  const data = manhuaguiReaderData(html); const parts = ref.remoteId.split('/');
  if (scalar(data,'bid') !== parts[0] || scalar(data,'cid') !== parts[1]) { throw new AppError(ErrorCode.CONTENT_CHANGED,'漫画柜页面返回其他章节'); }
  const files = data.members.get('files'); const path = scalar(data,'path'); const signature = data.members.get('sl');
  if (files?.kind !== 'array' || !files.items.length || files.items.length > 2000 || scalar(data,'len') !== files.items.length.toString() ||
    !/^\/[^?#\\]*\/$/.test(path) || path.startsWith('//') || !signature || signature.kind !== 'object') { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜图片清单或数量不完整'); }
  const expires = scalar(signature,'e'); const sign = scalar(signature,'m');
  if (!/^[0-9]{1,16}$/.test(expires) || !sign || sign.length > 256) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜图片签名缺失'); }
  const policy = new UrlPolicy([]); const base = policy.resolve(path,'https://i.hamreus.com/');
  const basePath = new url.URL(base).pathname; const seen: Set<string> = new Set();
  return files.items.map((file: JsonNode,index: number): PageRef => {
    if (file.kind !== 'string' || !file.scalar || /[?#\\]/.test(file.scalar)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜图片文件名无效'); }
    const address = policy.validate(policy.resolve(file.scalar,base));
    if (address.origin !== 'https://i.hamreus.com' || !address.pathname.startsWith(basePath) || address.pathname === basePath || seen.has(address.pathname)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜图片路径缺失或重复'); }
    seen.add(address.pathname); address.searchParams.set('e',expires); address.searchParams.set('m',sign);
    return { pageKey: address.pathname,ordinal: index,locator: address.pathname,imageUrl: address.toString() };
  });
}
