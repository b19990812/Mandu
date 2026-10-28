import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';

export class RuleFilePicker {
  private readonly context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async select(): Promise<string | undefined> {
    const uris = await new picker.DocumentViewPicker(this.context).select({ maxSelectNumber: 1, fileSuffixFilters: ['源规则 JSON|.json'] });
    if (uris.length === 0) { return undefined; }
    // Use the granted URI directly; never convert it to an arbitrary filesystem path.
    const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(file.fd).size;
      if (size < 1 || size > 262144) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE, '规则文件必须为1～256KiB以内'); }
      const buffer = new ArrayBuffer(size + 1);
      const count = fs.readSync(file.fd, buffer);
      if (count !== size) { throw new AppError(ErrorCode.CORRUPT_FILE, '文件读取期间发生变化，请重选'); }
      try { return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(buffer, 0, count)); }
      catch (_) { throw new AppError(ErrorCode.PARSE_ERROR, '规则文件不是有效UTF-8'); }
    } finally { fs.closeSync(file); }
  }
  sample(filename: string): string {
    if (['json-v1.json', 'json-v2.json', 'html-v1.json', 'html-v2.json', 'invalid-v3.json'].indexOf(filename) < 0) {
      throw new AppError(ErrorCode.POLICY_DENIED, '未知内置规则');
    }
    return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(this.context.resourceManager.getRawFileContentSync('demo-rules/' + filename));
  }
}
