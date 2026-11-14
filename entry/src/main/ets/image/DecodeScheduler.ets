import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkCall } from '../source/SourceHttp';
import { ReaderPerf } from '../diagnostic/ReaderPerf';
import { ReaderTrace } from '../diagnostic/ReaderTrace';

export class DecodeDemand {
  readonly uri: string;
  background: boolean;
  constructor(uri: string,background: boolean) { this.uri = uri; this.background = background; }
}
interface DecodeCounts { limit: number; active: number; waiting: number; preloadActive: number; peakActive: number; }
class DecodeWaiter {
  readonly ctx: CallContext;
  readonly demand: DecodeDemand;
  readonly resolve: (release: () => void) => void;
  readonly reject: (error: Error) => void;
  readonly queuedAt: number = Date.now();
  stop: () => void = () => {};
  timer: number = -1;
  done: boolean = false;
  constructor(ctx: CallContext,demand: DecodeDemand,resolve: (release: () => void) => void,reject: (error: Error) => void) {
    this.ctx = ctx; this.demand = demand; this.resolve = resolve; this.reject = reject;
  }
}

// One global permit pool. Native work keeps its permit through cleanup, even after cancellation.
export class DecodeScheduler {
  private static limit: number = 4;
  private static active: number = 0;
  private static preloads: number = 0;
  private static peak: number = 0;
  private static queue: DecodeWaiter[] = [];
  private static focused: string[] = [];
  private static focusKey: string = '';
  static configure(limit: number): void {
    if (!Number.isInteger(limit) || limit < 1 || limit > 4 || DecodeScheduler.active || DecodeScheduler.queue.length) { throw new AppError(ErrorCode.CONFIG_INVALID,'解码并发只能在空闲时设为1至4'); }
    DecodeScheduler.limit = limit; DecodeScheduler.peak = 0;
  }
  static counts(): DecodeCounts { return { limit: DecodeScheduler.limit,active: DecodeScheduler.active,waiting: DecodeScheduler.queue.length,preloadActive: DecodeScheduler.preloads,peakActive: DecodeScheduler.peak }; }
  static focus(uris: string[]): void {
    const key = uris.join('|'); if (key === DecodeScheduler.focusKey) { return; }
    DecodeScheduler.focusKey = key; DecodeScheduler.focused = uris.slice(); DecodeScheduler.pump();
  }
  static changed(): void { DecodeScheduler.pump(); }
  private static rank(item: DecodeWaiter): number { return item.demand.background ? 2 : DecodeScheduler.focused.indexOf(item.demand.uri) >= 0 ? 0 : 1; }
  private static remove(item: DecodeWaiter,error: Error): void {
    if (item.done) { return; } item.done = true; item.stop(); if (item.timer >= 0) { clearTimeout(item.timer); }
    DecodeScheduler.queue = DecodeScheduler.queue.filter((entry: DecodeWaiter) => entry !== item);
    ReaderTrace.record(item.ctx.trace,'decode-queue-wait',Date.now() - item.queuedAt,error instanceof AppError ? error.code : 'failed'); item.reject(error);
  }
  static acquire(ctx: CallContext,demand: DecodeDemand): Promise<() => void> {
    checkCall(ctx);
    return new Promise<() => void>((resolve,reject) => {
      const item = new DecodeWaiter(ctx,demand,resolve,reject); DecodeScheduler.queue.push(item);
      item.stop = ctx.cancel.subscribe(() => DecodeScheduler.remove(item,new AppError(ErrorCode.CANCELLED,'排队解码已取消') as Error));
      if (!item.done) { item.timer = setTimeout(() => DecodeScheduler.remove(item,new AppError(ErrorCode.TIMEOUT,'排队解码已超时') as Error),Math.max(1,ctx.deadlineMs - Date.now())); }
      DecodeScheduler.pump();
    });
  }
  private static pump(): void {
    while (DecodeScheduler.active < DecodeScheduler.limit) {
      let candidate: DecodeWaiter | undefined = undefined;
      for (let index = 0; index < DecodeScheduler.queue.length; index++) {
        const item = DecodeScheduler.queue[index];
        if (!item.done && (!item.demand.background || DecodeScheduler.preloads < 1) && (!candidate || DecodeScheduler.rank(item) < DecodeScheduler.rank(candidate))) { candidate = item; }
      }
      const item = candidate; if (!item) { return; }
      try { checkCall(item.ctx); } catch (error) { DecodeScheduler.remove(item,error as Error); continue; }
      item.done = true; item.stop(); if (item.timer >= 0) { clearTimeout(item.timer); }
      DecodeScheduler.queue = DecodeScheduler.queue.filter((entry: DecodeWaiter) => entry !== item);
      const background = item.demand.background; DecodeScheduler.active++; if (background) { DecodeScheduler.preloads++; }
      DecodeScheduler.peak = Math.max(DecodeScheduler.peak,DecodeScheduler.active);
      ReaderTrace.record(item.ctx.trace,'decode-queue-wait',Date.now() - item.queuedAt,'ok',background ? 'preload' : 'display');
      ReaderPerf.event('decode-queue',Date.now() - item.queuedAt,background ? 'preload' : DecodeScheduler.focused.indexOf(item.demand.uri) >= 0 ? 'visible' : 'display');
      let released = false;
      item.resolve(() => {
        if (released) { return; } released = true; DecodeScheduler.active--; if (background) { DecodeScheduler.preloads--; } DecodeScheduler.pump();
      });
    }
  }
}
