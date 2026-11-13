import { util } from '@kit.ArkTS';
import { SecretStore } from '../storage/SecretStore';
import { payloadDigest } from '../storage/PayloadDigest';
import { AppError, ErrorCode } from '../model/ErrorTypes';

interface CookieParts { generation: string; count: number; digest: string; }

// Keep every encrypted AssetStore item below its 1024-byte limit. Commit the
// manifest last and serialize readers with writers so partial saves stay hidden.
export class SiteCookieStore {
  private static readonly prefix: string = 'site-cookie-v2:';
  private static tail: Promise<void> = Promise.resolve();

  private static async locked<T>(operation: () => Promise<T>): Promise<T> {
    const before = SiteCookieStore.tail; let release: () => void = () => {};
    SiteCookieStore.tail = new Promise<void>((resolve) => { release = resolve; });
    await before;
    try { return await operation(); } finally { release(); }
  }
  private static parts(raw: string): CookieParts {
    const fields = raw.split(':'); const count = Number(fields[2]);
    if (fields.length !== 4 || fields[0] !== 'site-cookie-v2' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(fields[1]) ||
      !Number.isInteger(count) || count < 1 || count > 32 || !/^[0-9a-f]{64}$/.test(fields[3])) {
      throw new AppError(ErrorCode.CORRUPT_FILE,'站点会话分片索引损坏，请重新保存会话');
    }
    return { generation: fields[1],count: count,digest: fields[3] };
  }
  private static partKey(key: string,generation: string,index: number): string { return key + ':' + generation + ':' + index.toString(); }
  private static async removeParts(key: string,raw: string): Promise<void> {
    if (!raw.startsWith(SiteCookieStore.prefix)) { return; }
    let parts: CookieParts;
    try { parts = SiteCookieStore.parts(raw); } catch (_) { return; }
    for (let index = 0; index < parts.count; index++) {
      try { await SecretStore.remove(SiteCookieStore.partKey(key,parts.generation,index)); } catch (_) { /* Cleanup must not invalidate an already committed session. */ }
    }
  }
  static read(key: string): Promise<string> {
    return SiteCookieStore.locked(async () => {
      const raw = await SecretStore.read(key);
      if (!raw.startsWith(SiteCookieStore.prefix)) { return raw; }
      const parts = SiteCookieStore.parts(raw); let encoded = '';
      for (let index = 0; index < parts.count; index++) {
        const chunk = await SecretStore.read(SiteCookieStore.partKey(key,parts.generation,index));
        if (!chunk || chunk.length > 900 || !/^[A-Za-z0-9+/=]+$/.test(chunk)) { throw new AppError(ErrorCode.CORRUPT_FILE,'站点会话分片缺失，请重新保存会话'); }
        encoded += chunk;
      }
      if (await payloadDigest(encoded) !== parts.digest) { throw new AppError(ErrorCode.CORRUPT_FILE,'站点会话校验失败，请重新保存会话'); }
      try {
        const bytes = new util.Base64Helper().decodeSync(encoded);
        if (bytes.length > 16416) { throw new Error('size'); }
        return new util.TextDecoder('utf-8',{ fatal: true }).decodeWithStream(bytes,{ stream: false });
      } catch (_) { throw new AppError(ErrorCode.CORRUPT_FILE,'站点会话编码损坏，请重新保存会话'); }
    });
  }
  static save(key: string,value: string): Promise<void> {
    return SiteCookieStore.locked(async () => {
      const bytes = new util.TextEncoder().encodeInto(value);
      if (bytes.length > 16416) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'站点会话超过16KiB，请清理该站点会话后重试'); }
      const old = await SecretStore.read(key);
      if (bytes.length <= 1024) { await SecretStore.save(key,value); await SiteCookieStore.removeParts(key,old); return; }
      const encoded = new util.Base64Helper().encodeToStringSync(bytes);
      const generation = util.generateRandomUUID(); const count = Math.ceil(encoded.length / 900);
      const manifest = SiteCookieStore.prefix + generation + ':' + count.toString() + ':' + await payloadDigest(encoded);
      try {
        for (let index = 0; index < count; index++) { await SecretStore.save(SiteCookieStore.partKey(key,generation,index),encoded.substring(index * 900,(index + 1) * 900)); }
        await SecretStore.save(key,manifest);
      } catch (error) { await SiteCookieStore.removeParts(key,manifest); throw error as Error; }
      await SiteCookieStore.removeParts(key,old);
    });
  }
  static clear(key: string): Promise<void> {
    return SiteCookieStore.locked(async () => {
      const old = await SecretStore.read(key); await SecretStore.remove(key); await SiteCookieStore.removeParts(key,old);
    });
  }
}
