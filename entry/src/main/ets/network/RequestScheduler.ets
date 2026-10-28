import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';

interface Waiter { source: string; host: string; ctx: CallContext; priority: number; grant: (release: () => void) => void; fail: (error: AppError) => void; unsubscribe: () => void; timer: number; }

// Process-wide concurrency limits apply across registry/reader/download instances.
// Only server cooldowns delay otherwise available capacity; there is no fixed request interval.
export class RequestScheduler {
  private static active: number = 0;
  private static sources: Map<string,number> = new Map();
  private static hosts: Map<string,number> = new Map();
  private static nextSource: Map<string,number> = new Map();
  private static nextHost: Map<string,number> = new Map();
  private static queue: Waiter[] = [];
  private static wake: number = -1;
  static acquire(source: string, host: string, ctx: CallContext): Promise<() => void> {
    if (ctx.cancel.cancelled) { return Promise.reject(new AppError(ErrorCode.CANCELLED,'操作已取消')); }
    if (Date.now() >= ctx.deadlineMs) { return Promise.reject(new AppError(ErrorCode.TIMEOUT,'请求已超时')); }
    if (RequestScheduler.queue.length >= 256) { return Promise.reject(new AppError(ErrorCode.RATE_LIMITED,'请求队列已满，请稍后重试')); }
    return new Promise<() => void>((resolve,reject) => {
      const waiter: Waiter = { source: source,host: host,ctx: ctx,priority: ctx.callId.startsWith('download') ? 2 : ctx.callId.startsWith('reader-prefetch') ? 1 : 0,grant: resolve,fail: reject,unsubscribe: () => {},timer: -1 };
      const remove = (code: ErrorCode): void => {
        const index = RequestScheduler.queue.indexOf(waiter); if (index < 0) { return; }
        RequestScheduler.queue.splice(index,1); waiter.unsubscribe(); clearTimeout(waiter.timer); reject(new AppError(code, code === ErrorCode.CANCELLED ? '排队请求已取消' : '排队请求超时')); RequestScheduler.pump();
      };
      waiter.timer = setTimeout(() => remove(ErrorCode.TIMEOUT), Math.max(1,ctx.deadlineMs - Date.now()));
      RequestScheduler.queue.push(waiter); waiter.unsubscribe = ctx.cancel.subscribe(() => remove(ErrorCode.CANCELLED)); RequestScheduler.pump();
    });
  }
  static cooldown(source: string, host: string, raw: string): void {
    let duration = /^[0-9]+$/.test(raw.trim()) ? Number(raw) * 1000 : Date.parse(raw) - Date.now();
    if (!Number.isFinite(duration) || duration < 0) { duration = 1000; }
    const until = Date.now() + Math.min(86400000, duration);
    RequestScheduler.nextSource.set(source,Math.max(RequestScheduler.nextSource.get(source) || 0,until));
    RequestScheduler.nextHost.set(host,Math.max(RequestScheduler.nextHost.get(host) || 0,until));
  }
  private static pump(): void {
    if (RequestScheduler.wake >= 0) { clearTimeout(RequestScheduler.wake); RequestScheduler.wake = -1; }
    RequestScheduler.queue.sort((a: Waiter,b: Waiter) => a.priority - b.priority);
    let delay = 1000;
    for (let index = 0; index < RequestScheduler.queue.length && RequestScheduler.active < 4;) {
      const item = RequestScheduler.queue[index];
      const wait = Math.max(RequestScheduler.nextSource.get(item.source) || 0,RequestScheduler.nextHost.get(item.host) || 0) - Date.now();
      if (wait > 0 || (RequestScheduler.sources.get(item.source) || 0) >= 2 || (RequestScheduler.hosts.get(item.host) || 0) >= 2) { if (wait > 0) { delay = Math.min(delay,wait); } index++; continue; }
      RequestScheduler.queue.splice(index,1); item.unsubscribe(); clearTimeout(item.timer);
      RequestScheduler.active++; RequestScheduler.sources.set(item.source,(RequestScheduler.sources.get(item.source) || 0) + 1); RequestScheduler.hosts.set(item.host,(RequestScheduler.hosts.get(item.host) || 0) + 1);
      let released = false;
      item.grant(() => {
        if (released) { return; } released = true; RequestScheduler.active--; RequestScheduler.sources.set(item.source,Math.max(0,(RequestScheduler.sources.get(item.source) || 1) - 1)); RequestScheduler.hosts.set(item.host,Math.max(0,(RequestScheduler.hosts.get(item.host) || 1) - 1)); RequestScheduler.pump();
      });
    }
    if (RequestScheduler.queue.length > 0) { RequestScheduler.wake = setTimeout(() => RequestScheduler.pump(),Math.max(10,delay)); }
  }
}
