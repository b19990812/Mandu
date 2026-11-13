import { Transport, RequestPlan, TransportResponse } from './Transport';
import { MyComicBrowserSession } from './MyComicBrowserSession';
import { RequestScheduler } from './RequestScheduler';
import { CallContext } from '../model/RequestTypes';
import { ByteSink } from '../model/ByteSink';
import { url } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class MyComicBrowserTransport implements Transport {
  private readonly delegate: Transport;
  private readonly base: string;
  constructor(delegate: Transport,base: string) { this.delegate = delegate; this.base = base; }
  async send(plan: RequestPlan,ctx: CallContext): Promise<TransportResponse> {
    if (plan.sourceId !== 'org.hsmihon.mycomic' || plan.responseKind !== 'metadata') { return this.delegate.send(plan,ctx); }
    MyComicBrowserSession.validate(plan,this.base);
    // Browser fetch explicitly uses no-store; do not retain a derived feed either.
    if (ctx.retention) { ctx.retention.allowed = false; }
    const host = new url.URL(plan.url).hostname; const release = await RequestScheduler.acquire(plan.sourceId,host,ctx);
    try {
      const response = await MyComicBrowserSession.read(plan,this.base,ctx);
      if (response.statusCode === 429 || response.statusCode >= 500) { RequestScheduler.cooldown(plan.sourceId,host,response.headers.find((header) => header.name.toLowerCase() === 'retry-after')?.value || '1'); }
      hilog.info(0x0001,'HSReader','MYCOMIC_BROWSER_METADATA status=%{public}d bytes=%{public}d',response.statusCode,response.bytes);
      return response;
    } finally { release(); }
  }
  streamToFile(plan: RequestPlan,ctx: CallContext,sink: ByteSink): Promise<TransportResponse> { return this.delegate.streamToFile(plan,ctx,sink); }
}
