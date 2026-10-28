import { workScheduler } from '@kit.BackgroundTasksKit';
import { UpdatePolicy } from '../storage/UpdatePolicyRepository';

export class UpdateScheduler {
  static readonly ID: number = 1101;
  static async configure(policy: UpdatePolicy): Promise<void> {
    let old: workScheduler.WorkInfo | undefined;
    try { old = await workScheduler.getWorkStatus(UpdateScheduler.ID); } catch (_) {}
    const cycle = policy.hours * 3600000;
    const network = policy.wifiOnly ? workScheduler.NetworkType.NETWORK_TYPE_WIFI : workScheduler.NetworkType.NETWORK_TYPE_ANY;
    if (old && policy.hours > 0 && old.repeatCycleTime === cycle && old.networkType === network) { return; }
    if (old) { workScheduler.stopWork(old,true); }
    if (policy.hours > 0) {
      workScheduler.startWork({ workId: UpdateScheduler.ID,bundleName: 'com.hsmihon.reader',abilityName: 'LibraryUpdateAbility',isRepeat: true,repeatCycleTime: cycle,networkType: network,isPersisted: true });
    }
  }
}
