import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export async function payloadDigest(text: string): Promise<string> {
  const digest = cryptoFramework.createMd('SHA256');
  await digest.update({ data: new util.TextEncoder().encodeInto(text) });
  const result = await digest.digest();
  return Array.from(result.data).map((value: number) => value.toString(16).padStart(2, '0')).join('');
}
