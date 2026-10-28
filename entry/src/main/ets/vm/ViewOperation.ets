import { AppError } from '../model/ErrorTypes';
import { CancelScope } from '../model/CancelScope';
import { CallContext } from '../model/RequestTypes';

export class ViewOperation {
  private generation: number = 0;
  private current?: CancelScope;
  private closed: boolean = false;
  reopen(): void { this.cancel(); this.closed = false; this.generation++; }
  begin(timeout: number, version: number = 1): CallContext {
    if (this.current) { this.current.cancel(); }
    this.current = new CancelScope(); this.generation++;
    return { callId: this.generation.toString(), deadlineMs: Date.now() + timeout, cancel: this.current, ruleRevision: version };
  }
  active(ctx: CallContext): boolean { return !this.closed && ctx.callId === this.generation.toString() && !ctx.cancel.cancelled; }
  cancel(): void { if (this.current) { this.current.cancel(); } }
  close(): void { this.closed = true; this.cancel(); }
}
export function viewError(error: Error): string { return error instanceof AppError ? error.code + '：' + error.message : '操作失败，请重试或检查存储状态'; }
