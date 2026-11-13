import { CallContext, HeaderPair } from '../model/RequestTypes';

// A multi-request result inherits the most restrictive response policy.
export function observeRetention(ctx: CallContext,headers: HeaderPair[]): void {
  const policy = ctx.retention; if (!policy) { return; }
  const controls = headers.filter((header) => header.name.toLowerCase() === 'cache-control').map((header) => header.value).join(',').toLowerCase();
  if (/(?:^|,)\s*(?:no-store|no-cache)(?:\s|,|=|$)/.test(controls) || headers.some((header) => header.name.toLowerCase() === 'vary' && header.value.trim() === '*')) { policy.allowed = false; }
  if (/(?:^|,)\s*(?:must-revalidate|proxy-revalidate)(?:\s|,|$)/.test(controls)) { policy.staleAllowed = false; }
  const maxAge = /(?:^|,)\s*max-age\s*=\s*"?([0-9]+)"?/.exec(controls);
  const age = Number(headers.find((header) => header.name.toLowerCase() === 'age')?.value || '0');
  if (maxAge) { policy.expiresAt = Math.min(policy.expiresAt,Date.now() + Math.max(0,Number(maxAge[1]) - (Number.isFinite(age) ? Math.max(0,age) : 0)) * 1000); }
  else {
    const expires = Date.parse(headers.find((header) => header.name.toLowerCase() === 'expires')?.value || '');
    if (Number.isFinite(expires)) { policy.expiresAt = Math.min(policy.expiresAt,expires); }
  }
}
