import { TrackingService } from '../tracking/TrackingService';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { AppTheme } from '../business/AppTheme';
import { UpdateScheduler } from '../business/UpdateScheduler';
import { CancelScope } from '../model/CancelScope';
import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppContainer } from '../app/AppContainer';
import { ReaderLifecycle } from '../reader/ReaderLifecycle';

export default class EntryAbility extends UIAbility {
  private updateTimer: number = -1;
  private updateScope?: CancelScope;
  private checkUpdates(): void {
    new TrackingService(ReaderDatabase.shared(this.context)).flush().catch(() => {});
    if (!this.app || this.updateScope) { return; }
    const scope = new CancelScope(); this.updateScope = scope;
    this.app.libraryUpdates.run({ callId: 'foreground-update',deadlineMs: Date.now() + 600000,cancel: scope,ruleRevision: 1 },true,() => {})
      .catch(() => hilog.warn(0x0001,'HSReader','LIBRARY_UPDATE_STOPPED'))
      .finally(() => { if (this.updateScope === scope) { this.updateScope = undefined; } });
  }
  private stopUpdates(): void { if (this.updateTimer >= 0) { clearInterval(this.updateTimer); this.updateTimer = -1; } this.updateScope?.cancel(); }
  private app?: AppContainer;
  private mainWindow?: window.Window;
  private downloadEntry: boolean = false;
  onCreate(want: Want,_launch: AbilityConstant.LaunchParam): void { this.downloadEntry = want.parameters?.['readerPage'] === 'downloads'; }
  onNewWant(want: Want,_launch: AbilityConstant.LaunchParam): void { if (want.parameters?.['readerPage'] === 'downloads') { this.downloadEntry = true; this.showDownloads(); } }
  private showDownloads(): void {
    if (!this.downloadEntry || !this.mainWindow) { return; } this.downloadEntry = false;
    this.mainWindow.getUIContext().getRouter().pushUrl({ url: 'pages/DownloadsPage' }).catch(() => hilog.warn(0x0001,'HSReader','DOWNLOAD_NOTIFICATION_ROUTE_FAILED'));
  }
  onForeground(): void {
    AppTheme.read(this.context).then((theme: string) => AppTheme.apply(this.context,theme)).catch(() => {});
    ReaderLifecycle.foreground();
    if (!this.app) { this.app = new AppContainer(this.context); }
    this.app.updatePolicy.read().then((policy) => UpdateScheduler.configure(policy)).catch(() => hilog.warn(0x0001,'HSReader','UPDATE_SCHEDULE_FAILED'));
    this.checkUpdates();
    if (this.updateTimer < 0) { this.updateTimer = setInterval(() => this.checkUpdates(),60000); }
    this.app.downloads.start().then(() => this.app?.downloads.setForeground(true), () => hilog.error(0x0001, 'HSReader', 'DOWNLOAD_RECOVERY_FAILED'));
  }
  onBackground(): void { this.stopUpdates(); ReaderLifecycle.background(); this.app?.downloads.setForeground(false); }
  onDestroy(): void { this.stopUpdates(); }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/HomePage', (error) => {
      if (error.code) {
        hilog.error(0x0001, 'HSReader', 'PAGE_LOAD_FAILED code=%{public}d', error.code);
      }
      else { this.mainWindow = windowStage.getMainWindowSync(); this.showDownloads(); }
    });
  }
}
