import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// Only user-requested, already active image transfers hold this lease.
// The coordinator never resolves/submits new pages after entering background.
export class BackgroundTransferLease {
  private readonly context: common.UIAbilityContext;
  private tail: Promise<void> = Promise.resolve();
  private users: number = 0;
  private running: boolean = false;
  private lastAttempt: number = 0;
  private state: string = '空闲时不占用后台任务';
  constructor(context: common.UIAbilityContext) { this.context = context; }
  status(): string { return this.state; }
  private async exclusive(work: () => Promise<void>): Promise<void> {
    const previous = this.tail; let release: () => void = () => {}; this.tail = new Promise<void>((resolve) => { release = resolve; }); await previous;
    try { await work(); } finally { release(); }
  }
  async acquire(): Promise<() => Promise<void>> {
    await this.exclusive(async () => {
      this.users++;
      if (this.running || Date.now() - this.lastAttempt < 60000) { return; } this.lastAttempt = Date.now();
      try {
        const parameters: Record<string,string> = {}; parameters['readerPage'] = 'downloads';
        const agent = await wantAgent.getWantAgent({ wants: [{ bundleName: 'com.hsmihon.reader',abilityName: 'EntryAbility',parameters: parameters }],operationType: wantAgent.OperationType.START_ABILITY,requestCode: 1001,wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] });
        await backgroundTaskManager.startBackgroundRunning(this.context,['dataTransfer'],agent);
        this.running = true; this.state = '当前图像已申请系统后台传输';
      } catch (error) {
        this.state = '后台传输未获准（' + ((error as BusinessError).code || 0).toString() + '），请保持前台';
        hilog.warn(0x0001,'HSReader','BACKGROUND_TRANSFER_DENIED sdk=%{public}d',(error as BusinessError).code || 0);
      }
    });
    let released = false;
    return async (): Promise<void> => {
      if (released) { return; } released = true;
      await this.exclusive(async () => {
        this.users = Math.max(0,this.users - 1); if (this.users > 0) { return; }
        if (this.running) {
          try { await backgroundTaskManager.stopBackgroundRunning(this.context); this.running = false; this.state = '当前传输结束，已释放后台任务'; this.lastAttempt = 0; }
          catch (error) { this.state = '后台任务释放待确认，请重新打开应用'; hilog.error(0x0001,'HSReader','BACKGROUND_TRANSFER_STOP_FAILED sdk=%{public}d',(error as BusinessError).code || 0); }
        }
      });
    };
  }
}
