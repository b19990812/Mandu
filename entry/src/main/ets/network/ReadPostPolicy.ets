import { url } from '@kit.ArkTS';
import { RequestPlan } from './Transport';
import { AppError, ErrorCode } from '../model/ErrorTypes';

// Only the site's public, bodyless directory read is permitted to use POST.
export function isDirectoryPost(plan: RequestPlan,streaming: boolean): boolean {
  if (plan.method === undefined || plan.method === 'GET') { return false; }
  const address = new url.URL(plan.url);
  if (plan.method !== 'POST' || plan.sourceId !== 'org.hsmihon.manhuaku' || streaming || plan.responseKind !== 'metadata' ||
    !/^\/comic\/[1-9][0-9]{0,18}$/.test(address.pathname) || address.search || address.hash) {
    throw new AppError(ErrorCode.POLICY_DENIED,'仅支持漫画库公开目录的无请求体 POST 读取');
  }
  return true;
}
