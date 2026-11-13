import { CallContext } from '../model/RequestTypes';
import { CancelScope } from '../model/CancelScope';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkCall } from '../source/SourceHttp';
import { requestPriority } from './RequestPriority';
import { RequestScheduler } from './RequestScheduler';

// Each consumer owns cancellation/deadline; the underlying request stops at zero.
export class SharedRequest<T> {
  private readonly scope: CancelScope = new CancelScope();
  private readonly context: CallContext;
  private readonly request: Promise<T>;
  private users: number = 0;
  private complete: boolean = false;
  get cancelled(): boolean { return this.scope.cancelled; }
  constructor(ctx: CallContext,load: (call: CallContext) => Promise<T>) {
    this.context = { callId: ctx.callId,deadlineMs: Date.now() + 60000,cancel: this.scope,ruleRevision: ctx.ruleRevision,
      priority: { value: requestPriority(ctx) },retention: ctx.retention };
    this.request = Promise.resolve().then(() => { checkCall(this.context); return load(this.context); });
    this.request.then(() => { this.complete = true; },() => { this.complete = true; });
  }
  consume(ctx: CallContext): Promise<T> {
    checkCall(ctx); this.users++;
    const priority = this.context.priority!;
    if (requestPriority(ctx) < priority.value) { priority.value = requestPriority(ctx); RequestScheduler.reprioritize(); }
    return new Promise<T>((resolve,reject) => {
      let done = false; let unsubscribe: () => void = () => {};
      const finish = (value: T | undefined,error?: Error): void => {
        if (done) { return; } done = true; clearTimeout(timer); unsubscribe(); this.users--;
        if (!this.users && !this.complete) { this.scope.cancel(); }
        if (error) { reject(error); } else { resolve(value!); }
      };
      const timer = setTimeout(() => finish(undefined,new AppError(ErrorCode.TIMEOUT,'共享请求等待超时') as Error),Math.max(1,ctx.deadlineMs - Date.now()));
      unsubscribe = ctx.cancel.subscribe(() => finish(undefined,new AppError(ErrorCode.CANCELLED,'请求已取消') as Error));
      this.request.then((value: T) => { try { checkCall(ctx); finish(value); } catch (error) { finish(undefined,error as Error); } },(error: Error) => finish(undefined,error));
    });
  }
}
