import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';

export class UrlPolicy {
  private readonly fixtureOrigin: string;

  // Keep existing callers and rule packages compatible; declared hosts are metadata only.
  constructor(_declaredHosts: string[], fixtureOrigin: string = '') {
    this.fixtureOrigin = fixtureOrigin;
  }

  validate(address: string): url.URL {
    if (address.length > 8192) { throw new AppError(ErrorCode.POLICY_DENIED, '网址超过长度限额'); }
    let parsed: url.URL;
    try { parsed = new url.URL(address); }
    catch (_) { throw new AppError(ErrorCode.POLICY_DENIED, '地址格式无效'); }
    const host = parsed.hostname.toLowerCase();
    if (parsed.username || parsed.password || parsed.hash) {
      throw new AppError(ErrorCode.POLICY_DENIED, '地址不能包含凭据或片段');
    }
    if (this.fixtureOrigin && parsed.origin === this.fixtureOrigin && parsed.protocol === 'http:') {
      return parsed;
    }
    // Production accepts any valid public DNS name; transport and address checks still apply.
    if (parsed.protocol !== 'https:' || (parsed.port !== '' && parsed.port !== '443') ||
      host === 'localhost' || host.endsWith('.localhost') || host.indexOf(':') >= 0 ||
      /^[0-9.]+$/.test(host) || host.endsWith('.local') || host.endsWith('.internal') ||
      host.indexOf('.') < 0 || host.length > 253 || !host.split('.').every((label: string) =>
        /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))) {
      throw new AppError(ErrorCode.POLICY_DENIED, '仅允许标准 HTTPS 公网域名');
    }
    return parsed;
  }

  resolve(location: string, base: string): string {
    let resolved: url.URL;
    try { resolved = new url.URL(location, base); }
    catch (_) { throw new AppError(ErrorCode.POLICY_DENIED, '跳转地址无效'); }
    return this.validate(resolved.toString()).toString();
  }
}
