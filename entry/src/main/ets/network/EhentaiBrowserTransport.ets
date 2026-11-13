import { AppError, ErrorCode } from '../model/ErrorTypes';
import { ByteSink } from '../model/ByteSink';
import { CallContext } from '../model/RequestTypes';
import { EHENTAI_BASE, EHENTAI_ID, ehentaiAddress } from './EhentaiAccess';
import { EhentaiBrowserSession } from './EhentaiBrowserSession';
import { RequestScheduler } from './RequestScheduler';
import { RequestPlan, Transport, TransportResponse } from './Transport';

export class EhentaiBrowserTransport implements Transport {
  private readonly native: Transport;
  constructor(native: Transport) { this.native = native; }

  send(plan: RequestPlan,ctx: CallContext): Promise<TransportResponse> { return this.native.send(plan,ctx); }

  async streamToFile(plan: RequestPlan,ctx: CallContext,sink: ByteSink): Promise<TransportResponse> {
    const referer = plan.headers.find((header) => header.name.toLowerCase() === 'referer')?.value;
    // The registry's cover requests use the base URL. Only validated page references select ArkWeb.
    if (plan.sourceId !== EHENTAI_ID || referer === EHENTAI_BASE) { return this.native.streamToFile(plan,ctx,sink); }
    if (!referer || plan.url !== referer || plan.responseKind !== 'image' || (plan.method && plan.method !== 'GET') ||
      !Number.isInteger(plan.maxBytes) || plan.maxBytes < 1 || plan.maxBytes > 33554432) {
      throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 浏览器仅下载章节图片');
    }
    const page = ehentaiAddress(referer,false);
    if (page.origin + '/' !== EHENTAI_BASE || page.search ||
      !/^\/s\/[a-f0-9]{10}\/[1-9][0-9]{0,14}-[1-9][0-9]{0,3}$/.test(page.pathname)) {
      throw new AppError(ErrorCode.POLICY_DENIED,'E-Hentai 浏览器图片来源页无效');
    }
    const release = await RequestScheduler.acquire(plan.sourceId,page.hostname,ctx);
    try {
      const result = await EhentaiBrowserSession.read(page.toString(),plan.maxBytes,ctx,sink);
      return { statusCode: 200,finalUrl: result.url,headers: [],body: '',bytes: result.bytes };
    } finally { release(); }
  }
}
