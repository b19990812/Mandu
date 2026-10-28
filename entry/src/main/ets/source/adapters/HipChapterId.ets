import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../../model/ErrorTypes';

export interface HipChapterIdentity { apiHid: string; mangaId: string; chapterId: string; }

// Public directory and reader IDs encode the same identity with different prefixes.
// Keep the directory ID as the stable chapter key; only convert the API request ID.
export class HipChapterId {
  private encode(value: string): string {
    return new util.Base64Helper().encodeToStringSync(new util.TextEncoder().encodeInto(value)).replace(/=+$/,'').replace(/\+/g,'-').replace(/\//g,'_');
  }
  private decode(value: string): string {
    if (!/^[A-Za-z0-9_]{1,128}$/.test(value)) { return this.fail(); }
    try {
      const bytes = new util.Base64Helper().decodeSync(value.replace(/_/g,'/') + '='.repeat((4 - value.length % 4) % 4));
      const text = util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(bytes);
      if (this.encode(text) !== value) { return this.fail(); } return text;
    } catch (_) { return this.fail(); }
  }
  parse(mangaRemoteId: string,frontendHid: string): HipChapterIdentity {
    const parts = frontendHid.split('-'); if (parts.length !== 2) { return this.fail(); }
    const manga = /^m:([1-9][0-9]{0,11})$/.exec(this.decode(mangaRemoteId.split('-')[0]));
    const chapter = /^m:([1-9][0-9]{0,11})-c:([1-9][0-9]{0,11})$/.exec(this.decode(parts[0]));
    const order = /^([1-9][0-9]{0,11}):[0-9]{1,10}(?:\.[0-9]{1,6})?$/.exec(this.decode(parts[1]));
    if (!manga || !chapter || !order || manga[1] !== chapter[1] || manga[1] !== order[1]) { return this.fail(); }
    return { apiHid: this.encode('c:' + chapter[2]) + '-' + parts[1],mangaId: manga[1],chapterId: chapter[2] };
  }
  private fail(): never { throw new AppError(ErrorCode.RULE_INVALID,'HIP章节标识格式或作品身份不符'); }
}
