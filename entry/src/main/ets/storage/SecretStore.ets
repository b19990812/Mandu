import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { payloadDigest } from './PayloadDigest';
import { AppError, ErrorCode } from '../model/ErrorTypes';
export class SecretStore {
  private static async selector(key: string): Promise<asset.AssetMap> {
    const query: asset.AssetMap = new Map(); query.set(asset.Tag.ALIAS,new util.TextEncoder().encodeInto(await payloadDigest(key))); return query;
  }
  static async save(key: string,value: string): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(value);
    if (!bytes.length || bytes.length > 1024) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'安全存储单项上限1024字节，未保存凭据'); }
    const attrs = await SecretStore.selector(key); attrs.set(asset.Tag.SECRET,bytes); attrs.set(asset.Tag.CONFLICT_RESOLUTION,asset.ConflictResolution.OVERWRITE);
    await asset.add(attrs);
  }
  static async read(key: string): Promise<string> {
    const query = await SecretStore.selector(key); query.set(asset.Tag.RETURN_TYPE,asset.ReturnType.ALL);
    try { const results = await asset.query(query); const value = results[0]?.get(asset.Tag.SECRET); return value instanceof Uint8Array ? new util.TextDecoder('utf-8').decodeWithStream(value,{ stream: false }) : ''; } catch (_) { return ''; }
  }
  static async remove(key: string): Promise<void> { await asset.remove(await SecretStore.selector(key)); }
}
