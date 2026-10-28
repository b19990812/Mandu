import { SourceSiteAccess } from '../model/SourceSiteTypes';
import { SourceSiteAddress } from './SourceSiteAddress';
import { AppError, ErrorCode } from '../model/ErrorTypes';

export const COPY_DEFAULT_API: string = 'https://api.copy4000.com/';
// These are explicit choices from the inspected 1.4.85 client, not availability claims.
export const COPY_API_SITES: string[] = ['https://api.copy4000.com/','https://api.copy3000.com/','https://api.2026copy.com/','https://mapi.copy2000.site/','https://mapi.copy20.com/','https://api.mangacopy.com/'];
export function copyProtocol(value?: string): string {
  if (value === undefined) { return 'api'; }
  if (value !== 'api' && value !== 'web') { throw new AppError(ErrorCode.CONFIG_INVALID,'COPY接入方式无效'); }
  return value;
}
export function copyApiBase(value?: string): string { return new SourceSiteAddress().normalize(value === undefined ? COPY_DEFAULT_API : value); }
export function usesCopyApi(site: SourceSiteAccess): boolean { return site.sourceId === 'org.hsmihon.copy' && copyProtocol(site.copyProtocol) === 'api'; }
export function nativeAdapterVersion(site: SourceSiteAccess): number { return usesCopyApi(site) || site.sourceId === 'org.hsmihon.hipmh' || site.sourceId === 'org.hsmihon.manhuagui' ? 2 : 1; }
export function nativeSnapshot(site: SourceSiteAccess): string {
  const copyConfig = site.sourceId === 'org.hsmihon.copy' ? ',"protocol":' + JSON.stringify(copyProtocol(site.copyProtocol)) + ',"apiBaseUrl":' + JSON.stringify(copyApiBase(site.copyApiBaseUrl)) + ',"resolution":"source","session":' + JSON.stringify(usesCopyApi(site) ? 'anonymous' : 'site-cookie') : '';
  return '{"schema":1,"id":' + JSON.stringify(site.sourceId) + ',"version":' + nativeAdapterVersion(site).toString() + ',"baseUrl":' + JSON.stringify(site.baseUrl) + copyConfig + '}';
}
