export function turnCompletes(offset: number, width: number, velocity: number): boolean {
  return Math.abs(offset) > width * 0.22 || Math.abs(offset) > 12 && velocity * offset > 0 && Math.abs(velocity) > 700;
}

export function spreadMargin(width: number): number { return Math.max(12,Math.min(40,width * 0.025)); }
export const SPREAD_GUTTER: number = 4;
export const CURL_MAX_PIXELS: number = 4194304;

export function curlSnapshotScale(width: number, height: number): number {
  const w = Math.max(1,width); const h = Math.max(1,height);
  const scale = Math.min(1,4096 / Math.max(w,h),Math.sqrt(CURL_MAX_PIXELS / (w * h)));
  // Bound both rounded snapshot dimensions before enforcing the pixel cap at admission.
  return Math.min(scale,Math.max(1,Math.floor(w * scale)) / w,Math.max(1,Math.floor(h * scale)) / h);
}
