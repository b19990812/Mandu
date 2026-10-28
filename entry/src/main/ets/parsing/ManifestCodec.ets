import { AppError, ErrorCode } from '../model/ErrorTypes';
import { DownloadManifest } from '../model/DownloadTypes';
import { JsonExtractor } from '../parsing/JsonExtractor';
import { checkParseText } from '../parsing/ParseLimits';

// Shared durable manifest protocol; no dependency on download execution or storage.
export class ManifestCodec {
  encode(ruleKey: string, pageKeys: string[]): string {
    const text = '{"schemaVersion":1,"ruleKey":' + JSON.stringify(ruleKey) + ',"pages":' + JSON.stringify(pageKeys) + '}';
    checkParseText(text); this.decode(text); return text;
  }
  decode(text: string): DownloadManifest {
    const root = new JsonExtractor().parse(text); const schema = root.members.get('schemaVersion');
    const rule = root.members.get('ruleKey'); const pages = root.members.get('pages');
    if (root.kind !== 'object' || root.members.size !== 3 || !schema || schema.kind !== 'number' || schema.scalar !== '1' ||
      !rule || rule.kind !== 'string' || !/^[a-f0-9]{64}$/.test(rule.scalar) || !pages || pages.kind !== 'array' || pages.items.length < 1 || pages.items.length > 2000) {
      throw new AppError(ErrorCode.CORRUPT_FILE, '离线清单结构不兼容或损坏');
    }
    const seen: Set<string> = new Set(); const keys: string[] = [];
    pages.items.forEach((node) => {
      if (node.kind !== 'string' || node.scalar === '' || node.scalar.length > 2048 || seen.has(node.scalar)) { throw new AppError(ErrorCode.CORRUPT_FILE, '离线图像标识无效或重复'); }
      keys.push(node.scalar); seen.add(node.scalar);
    });
    return { ruleKey: rule.scalar, pageKeys: keys };
  }
}
