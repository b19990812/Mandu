import { ByteSink } from '../model/ByteSink';
import { CallContext, HeaderPair } from '../model/RequestTypes';
export { CallContext, HeaderPair } from '../model/RequestTypes';

export interface RequestPlan {
  sourceId: string;
  url: string;
  headers: HeaderPair[];
  maxBytes: number;
  responseKind?: string;
}

export interface TransportResponse {
  statusCode: number;
  finalUrl: string;
  headers: HeaderPair[];
  body: string;
  bytes: number;
}

// P0 is anonymous GET only. Credentials and retries are added at T03b, not in UI.
export interface Transport {
  send(plan: RequestPlan, ctx: CallContext): Promise<TransportResponse>;
  streamToFile(plan: RequestPlan, ctx: CallContext, sink: ByteSink): Promise<TransportResponse>;
}
