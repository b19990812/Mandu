import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class ReaderWindow {
  private static savedBrightness: number = -1;
  private static savedOrientation: window.Orientation = window.Orientation.UNSPECIFIED;
  private static effectsActive: boolean = false;
  static effects(context: common.UIAbilityContext,active: boolean,brightness: number = -1,orientation: string = 'system'): void {
    ReaderWindow.tail = ReaderWindow.tail.then(async () => {
      const host = await window.getLastWindow(context);
      if (active) {
        if (!ReaderWindow.effectsActive) { ReaderWindow.savedBrightness = host.getWindowProperties().brightness; ReaderWindow.savedOrientation = host.getPreferredOrientation(); ReaderWindow.effectsActive = true; }
        await host.setWindowBrightness(brightness);
        await host.setPreferredOrientation(orientation === 'portrait' ? window.Orientation.PORTRAIT : orientation === 'landscape' ? window.Orientation.LANDSCAPE : ReaderWindow.savedOrientation);
      } else if (ReaderWindow.effectsActive) {
        await host.setWindowBrightness(ReaderWindow.savedBrightness); await host.setPreferredOrientation(ReaderWindow.savedOrientation); ReaderWindow.effectsActive = false;
      }
    }).catch(() => hilog.warn(0x0001,'HSReader','READER_EFFECT_FAILED'));
  }
  private static tail: Promise<void> = Promise.resolve();
  static immersive(context: common.UIAbilityContext,active: boolean): void {
    ReaderWindow.tail = ReaderWindow.tail.then(async () => {
      const host = await window.getLastWindow(context);
      await host.setWindowLayoutFullScreen(active);
      await host.setWindowSystemBarEnable(active ? [] : ['status','navigation']);
      await host.setWindowKeepScreenOn(active);
    }).catch(() => hilog.warn(0x0001,'HSReader','READER_WINDOW_MODE_FAILED'));
  }
}
