import { url } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { TransportResponse } from './Transport';
import { UrlPolicy } from './UrlPolicy';

export const EHENTAI_ID: string = 'org.hsmihon.ehentai';
export const EHENTAI_BASE: string = 'https://e-hentai.org/';
export const EHENTAI_API: string = 'https://api.e-hentai.org/api.php';
const policy: UrlPolicy = new UrlPolicy([]);

export function ehentaiAddress(raw: string, image: boolean): url.URL {
  if (raw.length > 8192 || /[\u0000-\u0020\u007f\\]/.test(raw)) {
    throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 地址格式无效');
  }
  let address: url.URL;
  try { address = new url.URL(raw); }
  catch (_) { throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 地址格式无效'); }
  if (address.username || address.password || address.hash || address.protocol !== 'https:') {
    throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 仅允许不含凭据或片段的 HTTPS 地址');
  }
  const host = address.hostname;
  const node = host.endsWith('.hath.network') && /^\/(?:h|om)\//.test(address.pathname);
  if (image ? !(host === 'ehgt.org' || host.endsWith('.ehgt.org') || node) :
    address.origin !== 'https://e-hentai.org' && address.toString() !== EHENTAI_API) {
    throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 返回了未经验证的站点或图片节点');
  }
  if (image && node && address.port && address.port !== '443') {
    const port = Number(address.port);
    if (port < 1024 || port > 65534) { throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 图片节点端口无效'); }
    policy.validate('https://' + host + '/');
  } else { policy.validate(address.toString()); }
  return address;
}

export class EhentaiQuota {
  private static until: number = 0;
  private static message: string = '';

  static check(): void {
    if (Date.now() < EhentaiQuota.until) { throw new AppError(ErrorCode.SOURCE_QUOTA,EhentaiQuota.message); }
  }

  static observe(response: TransportResponse): void {
    const errorPage = response.body.length < 8192 && !/id=["'](?:gdt|img)["']|class=["']itg\b/i.test(response.body);
    const limited = response.statusCode === 429 || errorPage && /please wait a bit longer between (?:each )?search/i.test(response.body);
    const exhausted = response.statusCode === 509 || errorPage &&
      /you have exceeded your (?:image viewing|bandwidth) limits|(?:your|this) ip address has been temporarily banned|could not get dispatch for image/i.test(response.body);
    if (limited || exhausted) {
      const retry = response.headers.find((pair) => pair.name.toLowerCase() === 'retry-after')?.value.trim() || '';
      const wait = /^\d+$/.test(retry) ? Number(retry) * 1000 : Date.parse(retry) - Date.now();
      EhentaiQuota.until = Date.now() + (Number.isFinite(wait) && wait > 0 ? Math.min(wait,86400000) : exhausted ? 300000 : 3000);
      EhentaiQuota.message = exhausted ? 'E-Hentai 图片配额已用尽或站点暂时限制访问，请稍后重试' : 'E-Hentai 请求过于频繁，请稍后重试';
      EhentaiQuota.check();
    }
    if (response.statusCode === 451) { throw new AppError(ErrorCode.POLICY_DENIED,'当前网络无法访问 E-Hentai（451）'); }
  }
}
