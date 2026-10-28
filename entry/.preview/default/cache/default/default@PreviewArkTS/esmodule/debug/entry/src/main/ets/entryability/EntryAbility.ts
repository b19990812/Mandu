import UIAbility from "@ohos:app.ability.UIAbility";
import hilog from "@ohos:hilog";
import type window from "@ohos:window";
export default class EntryAbility extends UIAbility {
    onWindowStageCreate(windowStage: window.WindowStage): void {
        windowStage.loadContent('pages/HomePage', (error) => {
            if (error.code) {
                hilog.error(0x0001, 'HSReader', 'PAGE_LOAD_FAILED code=%{public}d', error.code);
            }
        });
    }
}
