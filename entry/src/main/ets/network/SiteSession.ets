import { url } from '@kit.ArkTS';
import { SecretStore } from '../storage/SecretStore';
import { AppError, ErrorCode } from '../model/ErrorTypes';
export class SiteSession {
  private static owner: string = '';
  static acquire(source: string): boolean { if (SiteSession.owner) { return false; } SiteSession.owner = source; return true; }
  static release(source: string): void { if (SiteSession.owner === source) { SiteSession.owner = ''; } }
  private static key(source: string,address: string): string { return 'site-cookie:' + source + ':' + new url.URL(address).origin; }
  static async save(source: string,address: string,cookie: string): Promise<void> {
    if (!cookie || /[\r\n]/.test(cookie)) { throw new AppError(ErrorCode.CONFIG_INVALID,'没有可保存的站点 Cookie'); }
    await SecretStore.save(SiteSession.key(source,address),(Date.now() + 86400000).toString() + '\n' + cookie);
  }
  static async cookie(source: string,address: string): Promise<string> {
    const raw = await SecretStore.read(SiteSession.key(source,address)); const split = raw.indexOf('\n');
    if (split < 0 || Number(raw.substring(0,split)) <= Date.now()) { return ''; }
    const cookie = raw.substring(split + 1); return /[\r\n]/.test(cookie) ? '' : cookie;
  }
  static clear(source: string,address: string): Promise<void> { return SecretStore.remove(SiteSession.key(source,address)); }
}
