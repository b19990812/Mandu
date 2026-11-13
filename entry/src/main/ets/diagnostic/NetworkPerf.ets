import { hilog } from '@kit.PerformanceAnalysisKit';
import { rcp } from '@kit.RemoteCommunicationKit';

// Numeric timings and static operation names only. Never paths, queries or headers.
export class NetworkPerf {
  static stage(source: string,stage: string,started: number,count: number = 0): void {
    hilog.info(0x0001,'HSNetwork','NET_STAGE source=%{public}s stage=%{public}s ms=%{public}d count=%{public}d',
      source,stage,Math.max(0,Date.now() - started),count);
  }
  private static interval(end: number | undefined,start: number = 0): number {
    return end !== undefined && Number.isFinite(end) && Number.isFinite(start) && end >= start ? Math.round(end - start) : -1;
  }
  static http(source: string,host: string,started: number,status: number,bytes: number,time?: rcp.TimeInfo): void {
    const values: number[] = [Math.max(0,Date.now() - started),status,bytes,
      NetworkPerf.interval(time?.nameLookupTimeMs),
      time ? NetworkPerf.interval(time.connectTimeMs,time.nameLookupTimeMs) : -1,
      time ? NetworkPerf.interval(time.tlsHandshakeTimeMs,time.connectTimeMs) : -1,
      time ? NetworkPerf.interval(time.startTransferTimeMs,time.preTransferTimeMs) : -1,
      time ? NetworkPerf.interval(time.totalTimeMs,time.startTransferTimeMs) : -1];
    hilog.info(0x0001,'HSNetwork','NET_HTTP source=%{public}s host=%{public}s wall,status,bytes,dns,tcp,tls,first,body=%{public}s',source,host,JSON.stringify(values));
  }
}
