import { CancelScope } from './CancelScope';

export interface HeaderPair { name: string; value: string; }
export interface ReaderTraceContext {
  sessionId: string;
  operationId: string;
  sourceId: string;
  pageIndex: number;
  role: string;
  partIndex: number;
  startedAt: number;
}
export interface ResponseRetention { allowed: boolean; expiresAt: number; staleAllowed: boolean; }
export enum NetworkPriority { Visible = 0, Interactive = 1, Near = 2, Cover = 3, Prefetch = 4, Download = 5 }
export interface RequestUrgency { value: NetworkPriority; }
export interface CallContext {
  callId: string;
  deadlineMs: number;
  cancel: CancelScope;
  ruleRevision: number;
  retention?: ResponseRetention;
  priority?: RequestUrgency;
  trace?: ReaderTraceContext;
}
