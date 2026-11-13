import { ByteSink } from '../model/ByteSink';
import { CallContext, HeaderPair } from '../model/RequestTypes';
export { CallContext, HeaderPair } from '../model/RequestTypes';

export interface GalleryMetadataKey { gid: string; token: string; }

export interface RequestPlan {
  sourceId: string;
  url: string;
  headers: HeaderPair[];
  maxBytes: number;
  responseKind?: string;
  method?: string;
  galleryMetadata?: GalleryMetadataKey;
}

export interface TransportResponse {
  statusCode: number;
  finalUrl: string;
  headers: HeaderPair[];
  body: string;
  bytes: number;
}

// Defaults to GET. RcpTransport checks native metadata POST operations individually.
export interface Transport {
  send(plan: RequestPlan, ctx: CallContext): Promise<TransportResponse>;
  streamToFile(plan: RequestPlan, ctx: CallContext, sink: ByteSink): Promise<TransportResponse>;
}
