import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContainer } from '../app/AppContainer';
import { ChapterReaderService, ReaderSession } from '../business/ChapterReaderService';
import { AppError } from '../model/ErrorTypes';
import { CancelScope } from '../model/CancelScope';
import { CallContext } from '../model/RequestTypes';
import { BAOZI_SAMPLE_CHAPTER } from '../source/adapters/BaoziChapterSource';
import { TrialReaderSessions } from '../reader/TrialReaderSessions';

@Observed
export class ChapterReaderVM {
  chapterUrl: string = BAOZI_SAMPLE_CHAPTER;
  sourceId: string = 'org.hsmihon.baozi';
  title: string = '';
  status: string = '选择漫画源并粘贴章节网址，将进入全屏阅读器。';
  busy: boolean = false;
  total: number = 0;
  private service?: ChapterReaderService;
  private session?: ReaderSession;
  private scope?: CancelScope;
  private generation: number = 0;
  private disposed: boolean = false;

  initialize(context: common.UIAbilityContext): void {
    this.disposed = false;
    this.service = new AppContainer(context).reader;
  }

  private context(timeout: number): CallContext {
    if (this.scope) { this.scope.cancel(); }
    this.scope = new CancelScope();
    return { callId: 'reader-' + (++this.generation).toString(), deadlineMs: Date.now() + timeout,
      cancel: this.scope, ruleRevision: 1 };
  }

  async open(demo: boolean = false,long: boolean = false): Promise<void> {
    if (this.busy || this.disposed || !this.service) { return; }
    this.session?.cache.dispose(); this.session = undefined;
    const ctx = this.context(60000);
    const generation = this.generation;
    this.busy = true;
    this.status = demo ? '正在读取内置合成示例…' : '正在读取完整章节清单…';
    try {
      const session = demo ? await this.service.openDemo(ctx,long) : await this.service.open(this.chapterUrl,ctx,this.sourceId);
      if (this.disposed || generation !== this.generation || ctx.cancel.cancelled) { session.cache.dispose(); return; }
      this.session = session;
      this.title = session.manifest.label;
      this.total = session.manifest.pages.length;
      this.status = '章节清单已读取，共' + this.total.toString() + '个图像资源';
    } catch (error) { this.fail(error as Error, generation); }
    finally { if (generation === this.generation) { this.busy = false; } }
  }

  private fail(error: Error, generation: number): void {
    const code = error instanceof AppError ? error.code : 'SYSTEM_ERROR';
    hilog.error(0x0001, 'HSReader', 'CHAPTER_READER code=%{public}s', code);
    if (!this.disposed && generation === this.generation) {
      this.status = error instanceof AppError ? error.code + '：' + error.message : '读取失败，请检查网络或重试';
    }
  }

  cancel(): void { if (this.scope) { this.scope.cancel(); } }

  dispose(): void {
    this.disposed = true;
    this.cancel();
    if (this.session) { this.session.cache.dispose(); }
  }
  handoff(): string {
    if (!this.session) { return ''; }
    const token = TrialReaderSessions.put(this.session); this.session = undefined; return token;
  }
}
