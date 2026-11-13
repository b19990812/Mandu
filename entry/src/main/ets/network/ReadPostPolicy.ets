import { url } from '@kit.ArkTS';
import { RequestPlan } from './Transport';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { EHENTAI_API, EHENTAI_ID } from './EhentaiAccess';

// A defined result authorizes POST. The empty result is the bodyless Manhuaku read.
export function metadataPostBody(plan: RequestPlan,streaming: boolean): string | undefined {
  if ((plan.method === undefined || plan.method === 'GET') && !plan.galleryMetadata) { return undefined; }
  const address = new url.URL(plan.url);
  if (plan.method === 'POST' && !streaming && plan.responseKind === 'metadata') {
    if (plan.sourceId === 'org.hsmihon.manhuaku' && !plan.galleryMetadata &&
      /^\/comic\/[1-9][0-9]{0,18}$/.test(address.pathname) && !address.search && !address.hash) { return ''; }
    const gallery = plan.galleryMetadata;
    if (plan.sourceId === EHENTAI_ID && address.toString() === EHENTAI_API && gallery &&
      /^[1-9][0-9]{0,14}$/.test(gallery.gid) && /^[a-f0-9]{10}$/.test(gallery.token)) {
      return '{"method":"gdata","gidlist":[[' + gallery.gid + ',"' + gallery.token + '"]],"namespace":1}';
    }
  }
  throw new AppError(ErrorCode.POLICY_DENIED,'仅支持已登记的原生元数据 POST 读取');
}
