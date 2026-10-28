import { ByteSink } from '../model/ByteSink';
import { CallContext, HeaderPair } from '../model/RequestTypes';
export { CallContext, HeaderPair } from '../model/RequestTypes';

export interface RequestPlan {
  sourceId: string;
  url: string;
  headers: HeaderPair[];
  maxBytes: number;
  responseKind?: string;
  method?: string;
}

export interface TransportResponse {
  statusCode: number;
  finalUrl: string;
  headers: HeaderPair[];
  body: string;
  bytes: number;
}

// Defaults to GET. RcpTransport permits only the bodyless native Manhuaku directory POST.
export interface Transport {
  send(plan: RequestPlan, ctx: CallContext): Promise<TransportResponse>;
  streamToFile(plan: RequestPlan, ctx: CallContext, sink: ByteSink): Promise<TransportResponse>;
}
