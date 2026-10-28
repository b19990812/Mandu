import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CancelScope } from '../model/CancelScope';
import { updateRuntime } from '../business/UpdateRuntime';
import { UpdateScheduler } from '../business/UpdateScheduler';

export default class LibraryUpdateAbility extends WorkSchedulerExtensionAbility {
  private scope?: CancelScope;
  onWorkStart(work: workScheduler.WorkInfo): void {
    if (work.workId !== UpdateScheduler.ID || this.scope) { return; }
    const scope = new CancelScope(); this.scope = scope;
    updateRuntime(this.context).run({ callId: 'scheduled-update',deadlineMs: Date.now() + 100000,cancel: scope,ruleRevision: 1 },true,() => {})
      .catch(() => hilog.warn(0x0001,'HSReader','SCHEDULED_UPDATE_STOPPED'))
      .finally(() => { if (this.scope === scope) { this.scope = undefined; } try { workScheduler.stopWork(work,false); } catch (_) {} });
  }
  onWorkStop(_work: workScheduler.WorkInfo): void { this.scope?.cancel(); }
}
