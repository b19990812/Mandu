import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';
import { JsonExtractor, JsonNode } from '../../parsing/JsonExtractor';

// The anonymous site provides both literal format constants and the encoded list to its browser.
// Only a fixed AES format is read; no script, eval, challenge or external code is executed.
export class CopyFormat {
  literal(body: string,name: string): string {
    if (['cct','ccz','contentKey'].indexOf(name) < 0 || body.length > 2097152) { throw new AppError(ErrorCode.POLICY_DENIED,'不支持该站点字段'); }
    const expression = name === 'contentKey' ? /\bvar\s+contentKey\s*=\s*'([A-Za-z0-9]{16}[a-f0-9]+)'/ : name === 'cct' ? /\bvar\s+cct\s*=\s*'([A-Za-z0-9._-]{16})'/ : /\bvar\s+ccz\s*=\s*'([A-Za-z0-9._-]{16})'/;
    const found = expression.exec(body); if (!found) {
      throw new AppError(ErrorCode.PARSE_ERROR,'COPY公开清单格式已改变或内容不可用');
    } return found[1];
  }
  async decode(raw: string,key: string): Promise<JsonNode> {
    if (raw.length < 48 || raw.length > 2097152 || key.length !== 16 || !/^[A-Za-z0-9]{16}[a-f0-9]+$/.test(raw) || (raw.length - 16) % 32 !== 0) { throw new AppError(ErrorCode.PARSE_ERROR,'COPY清单编码无效或超过限额'); }
    try {
      const encoder = new util.TextEncoder(); const bytes = new Uint8Array((raw.length - 16) / 2);
      for (let i = 0; i < bytes.length; i++) { bytes[i] = parseInt(raw.substring(16 + i * 2,18 + i * 2),16); }
      const secret = await cryptoFramework.createSymKeyGenerator('AES128').convertKey({ data: encoder.encodeInto(key) });
      const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
      const params: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec',iv: { data: encoder.encodeInto(raw.substring(0,16)) } };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE,secret,params); const result = await cipher.doFinal({ data: bytes });
      return new JsonExtractor().parse(util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(result.data));
    } catch (error) { if (error instanceof AppError) { throw error; } throw new AppError(ErrorCode.PARSE_ERROR,'COPY公开清单不能按受支持格式读取'); }
  }
}
