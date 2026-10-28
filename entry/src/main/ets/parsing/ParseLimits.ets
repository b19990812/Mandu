import { AppError, ErrorCode } from '../model/ErrorTypes';

export function checkParseText(text: string): void {
  let bytes = 0;
  if (text.length > 2097152) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '解析正文超过2MiB'); }
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 128) { bytes++; }
    else if (code < 2048) { bytes += 2; }
    else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length &&
      text.charCodeAt(i + 1) >= 0xDC00 && text.charCodeAt(i + 1) <= 0xDFFF) { bytes += 4; i++; }
    else { bytes += 3; }
    if (bytes > 2097152) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '解析正文超过2MiB'); }
  }
}
