import { CancelScope } from './CancelScope';

export interface HeaderPair { name: string; value: string; }
export interface CallContext {
  callId: string;
  deadlineMs: number;
  cancel: CancelScope;
  ruleRevision: number;
}
