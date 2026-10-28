import { util } from '@kit.ArkTS';
import { ReaderSession } from '../business/ChapterReaderService';
import { AppError, ErrorCode } from '../model/ErrorTypes';

interface Launch { session: ReaderSession; created: number; }
// A one-time native navigation handoff. No network URL or callback is passed in router params.
export class TrialReaderSessions {
  private static launches: Map<string,Launch> = new Map();
  static put(session: ReaderSession): string {
    TrialReaderSessions.launches.forEach((launch: Launch,key: string) => { if (Date.now() - launch.created > 120000) { launch.session.cache.dispose(); TrialReaderSessions.launches.delete(key); } });
    if (TrialReaderSessions.launches.size >= 4) { throw new AppError(ErrorCode.CONFLICT,'阅读器正在打开，请稍后重试'); }
    const key = util.generateRandomUUID(); TrialReaderSessions.launches.set(key,{ session: session,created: Date.now() }); return key;
  }
  static take(key: string): ReaderSession {
    const launch = TrialReaderSessions.launches.get(key); TrialReaderSessions.launches.delete(key);
    if (!launch || Date.now() - launch.created > 120000) { launch?.session.cache.dispose(); throw new AppError(ErrorCode.NOT_FOUND,'章节打开请求已过期，请返回重新打开'); }
    return launch.session;
  }
  static discard(key: string): void { const launch = TrialReaderSessions.launches.get(key); TrialReaderSessions.launches.delete(key); launch?.session.cache.dispose(); }
}
