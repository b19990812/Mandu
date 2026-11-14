import { hilog } from '@kit.PerformanceAnalysisKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { ReaderTrace } from './ReaderTrace';
import { ReaderTraceContext } from '../model/RequestTypes';

// Numeric timings and static operation names only. Never paths, queries or headers.
export class NetworkPerf {
  static stage(source: string,stage: string,started: number,count: number = 0,trace?: ReaderTraceContext,
    outcome: string = 'ok',cacheTier: string = '',bytes: number = 0): void {
    const duration = Math.max(0, Date.now() - started);
    hilog.info(0x0001,'HSNetwork','NET_STAGE source=%{public}s stage=%{public}s ms=%{public}d count=%{public}d',
      source,stage,duration,count);
    ReaderTrace.record(trace,stage,duration,outcome,cacheTier,count,bytes);
  }
  private static interval(end: number | undefined,start: number = 0): number {
    return end !== undefined && Number.isFinite(end) && Number.isFinite(start) && end >= start ? Math.round(end - start) : -1;
  }
  static http(source: string,host: string,started: number,status: number,bytes: number,time?: rcp.TimeInfo,trace?: ReaderTraceContext): void {
    const values: number[] = [Math.max(0,Date.now() - started),status,bytes,
      NetworkPerf.interval(time?.nameLookupTimeMs),
      time ? NetworkPerf.interval(time.connectTimeMs,time.nameLookupTimeMs) : -1,
      time ? NetworkPerf.interval(time.tlsHandshakeTimeMs,time.connectTimeMs) : -1,
      time ? NetworkPerf.interval(time.startTransferTimeMs,time.preTransferTimeMs) : -1,
      time ? NetworkPerf.interval(time.totalTimeMs,time.startTransferTimeMs) : -1];
    hilog.info(0x0001,'HSNetwork','NET_HTTP source=%{public}s host=%{public}s wall,status,bytes,dns,tcp,tls,first,body=%{public}s',source,host,JSON.stringify(values));
    const outcome = status >= 200 && status < 300 ? 'ok' : status > 0 ? 'http-' + status.toString() : 'no-response';
    ReaderTrace.record(trace,'network-http',values[0],outcome,'network',0,bytes,values.slice(3));
  }
}
