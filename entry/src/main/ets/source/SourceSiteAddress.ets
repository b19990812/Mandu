import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { UrlPolicy } from '../network/UrlPolicy';

export class SourceSiteAddress {
  normalize(input: string): string {
    const text = input.trim();
    if (text.length === 0 || text.length > 2048 || /[\u0000-\u0020\u007f\\]/.test(text)) {
      throw new AppError(ErrorCode.POLICY_DENIED, '请输入完整的 HTTPS 网站首页地址');
    }
    let parsed: url.URL;
    try { parsed = new url.URL(text); }
    catch (_) { throw new AppError(ErrorCode.POLICY_DENIED, '网址格式无效，请包含 https://'); }
    const host = parsed.hostname.toLowerCase();
    if (host.length > 253 || !host.split('.').every((label: string) =>
      /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) {
      throw new AppError(ErrorCode.POLICY_DENIED, '网站域名格式无效');
    }
    new UrlPolicy([host]).validate(text);
    if (parsed.pathname !== '/' || parsed.search || parsed.hash) {
      throw new AppError(ErrorCode.POLICY_DENIED, '只填写网站根网址，章节路径由源规则处理');
    }
    return parsed.origin + '/';
  }
}
