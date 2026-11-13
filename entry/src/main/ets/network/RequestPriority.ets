import { CallContext, NetworkPriority } from '../model/RequestTypes';

export function requestPriority(ctx: CallContext): NetworkPriority {
  if (ctx.priority) { return ctx.priority.value; }
  // Compatibility for imported rules and older internal callers.
  if (ctx.callId.startsWith('download')) { return NetworkPriority.Download; }
  if (ctx.callId.startsWith('reader-prefetch')) { return NetworkPriority.Prefetch; }
  if (ctx.callId.startsWith('reader-prerender')) { return NetworkPriority.Near; }
  if (ctx.callId.startsWith('cover')) { return NetworkPriority.Cover; }
  return NetworkPriority.Interactive;
}
