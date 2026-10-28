import { AppError, ErrorCode } from '../model/ErrorTypes';

const ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const LIMIT: number = 2097152;

// Read the site's LZ-String Base64 data as a bounded bit stream, without running scripts.
class LzBits {
  private readonly input: string;
  private offset: number = 0;
  constructor(input: string) { this.input = input; }
  read(width: number): number {
    let value = 0;
    for (let bit = 0; bit < width; bit++) {
      if (this.offset >= this.input.length * 6) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜压缩数据不完整'); }
      const digit = ALPHABET.indexOf(this.input.charAt(Math.floor(this.offset / 6)));
      value += ((digit >> (5 - this.offset % 6)) & 1) * Math.pow(2,bit);
      this.offset++;
    }
    return value;
  }
}

export function decompressLzBase64(raw: string): string {
  if (!raw || raw.length > LIMIT || !/^[A-Za-z0-9+/]+={0,3}$/.test(raw)) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜压缩数据格式无效'); }
  const bits = new LzBits(raw.replace(/=+$/,''));
  const first = bits.read(2);
  if (first === 2) { return ''; }
  if (first > 1) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜压缩数据头无效'); }
  let previous = String.fromCharCode(bits.read(first === 0 ? 8 : 16));
  const dictionary: string[] = ['', '', '', previous];
  const output: string[] = [previous];
  let length = previous.length;
  let dictionarySize = length;
  let width = 3;
  let remaining = 4;
  while (dictionary.length <= 65536) {
    let code = bits.read(width);
    if (code === 2) { return output.join(''); }
    if (code === 0 || code === 1) {
      const literal = String.fromCharCode(bits.read(code === 0 ? 8 : 16));
      code = dictionary.length; dictionary.push(literal); dictionarySize++;
      if (--remaining === 0) { remaining = Math.pow(2,width++); }
    }
    const entry = code < dictionary.length ? dictionary[code] : code === dictionary.length ? previous + previous.charAt(0) : '';
    if (!entry) { throw new AppError(ErrorCode.PARSE_ERROR,'漫画柜压缩字典无效'); }
    length += entry.length;
    const next = previous + entry.charAt(0); dictionarySize += next.length;
    if (length > LIMIT || dictionarySize > LIMIT * 4) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画柜解压数据超限'); }
    output.push(entry); dictionary.push(next); previous = entry;
    if (--remaining === 0) { remaining = Math.pow(2,width++); }
  }
  throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'漫画柜压缩字典超限');
}
