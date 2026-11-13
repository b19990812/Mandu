import { url, util } from '@kit.ArkTS';
import { SiteCookieStore } from './SiteCookieStore';
import { AppError, ErrorCode } from '../model/ErrorTypes';
export class SiteSession {
  private static owner: string = '';
  private static epochs: Map<string,number> = new Map();
  static epoch(source: string): number { return SiteSession.epochs.get(source) || 0; }
  private static changed(source: string): void { SiteSession.epochs.set(source,SiteSession.epoch(source) + 1); }
  static acquire(source: string): boolean { if (SiteSession.owner) { return false; } SiteSession.owner = source; SiteSession.changed(source); return true; }
  static release(source: string): void { if (SiteSession.owner === source) { SiteSession.owner = ''; SiteSession.changed(source); } }
  static availableFor(source: string): boolean { return SiteSession.owner === '' || SiteSession.owner === source; }
  private static key(source: string,address: string): string { return 'site-cookie:' + source + ':' + new url.URL(address).origin; }
  static async save(source: string,address: string,cookie: string): Promise<void> {
    if (!cookie || /[\r\n]/.test(cookie)) { throw new AppError(ErrorCode.CONFIG_INVALID,'没有可保存的站点 Cookie'); }
    if (new util.TextEncoder().encodeInto(cookie).length > 16384) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'站点 Cookie 超过16KiB，请清理该站点会话后重试'); }
    await SiteCookieStore.save(SiteSession.key(source,address),(Date.now() + 86400000).toString() + '\n' + cookie);
    SiteSession.changed(source);
  }
  static async cookie(source: string,address: string): Promise<string> {
    const raw = await SiteCookieStore.read(SiteSession.key(source,address)); const split = raw.indexOf('\n');
    const expires = Number(raw.substring(0,split));
    if (split < 0 || !Number.isSafeInteger(expires) || expires <= Date.now()) { return ''; }
    const cookie = raw.substring(split + 1); return /[\r\n]/.test(cookie) ? '' : cookie;
  }
  static async clear(source: string,address: string): Promise<void> { await SiteCookieStore.clear(SiteSession.key(source,address)); SiteSession.changed(source); }
}
