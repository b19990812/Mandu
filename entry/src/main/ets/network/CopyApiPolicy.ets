import { url } from '@kit.ArkTS';
import { CallContext, HeaderPair } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';

// Installed by the native COPY registry only; imported rules cannot select this profile.
export class CopyApiPolicy {
  private static nextStart: number = 0;
  private readonly origin: string;
  constructor(origin: string) { this.origin = origin; }
  matches(sourceId: string,address: string): boolean {
    const target = new url.URL(address);
    return this.origin !== '' && sourceId === 'org.hsmihon.copy' && target.origin === this.origin && target.pathname.startsWith('/api/v3/');
  }
  headers(): HeaderPair[] {
    return [{ name: 'Accept',value: 'application/json' },
      { name: 'Accept-Language',value: 'en-US,en;q=0.9,zh-TW;q=0.8,zh;q=0.7' },
      { name: 'Origin',value: 'https://2025copy.com' },{ name: 'Version',value: '2026.08.21' },
      { name: 'Region',value: '0' },{ name: 'Webp',value: '0' },{ name: 'platform',value: '1' },
      { name: 'User-Agent',value: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0' },
      { name: 'sec-fetch-dest',value: 'document' },{ name: 'sec-fetch-mode',value: 'navigate' },
      { name: 'sec-fetch-site',value: 'same-origin' },{ name: 'sec-fetch-user',value: '?1' },
      { name: 'upgrade-insecure-requests',value: '1' }];
  }
  async wait(ctx: CallContext): Promise<void> {
    if (ctx.cancel.cancelled) { throw new AppError(ErrorCode.CANCELLED,'COPY API请求已取消'); }
    const start = Math.max(Date.now(),CopyApiPolicy.nextStart);
    if (start >= ctx.deadlineMs) { throw new AppError(ErrorCode.TIMEOUT,'COPY API请求排队超时'); }
    CopyApiPolicy.nextStart = start + 100;
    const delay = start - Date.now();
    if (delay <= 0) { return; }
    await new Promise<void>((resolve,reject) => {
      let unsubscribe: () => void = () => {};
      const timer = setTimeout(() => { unsubscribe(); resolve(); },delay);
      unsubscribe = ctx.cancel.subscribe(() => { clearTimeout(timer); reject(new AppError(ErrorCode.CANCELLED,'COPY API请求已取消')); });
    });
  }
}
