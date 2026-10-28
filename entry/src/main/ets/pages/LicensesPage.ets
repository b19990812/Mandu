import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

@Entry
@Component
struct LicensesPage {
  @State private text: string = '';
  aboutToAppear(): void {
    try { const context = this.getUIContext().getHostContext() as common.UIAbilityContext; this.text = util.TextDecoder.create('utf-8').decodeToString(context.resourceManager.getRawFileContentSync('THIRD_PARTY_LICENSES.txt')); }
    catch (_) { this.text = '许可证读取失败'; }
  }
  build() { Scroll() { Text(this.text).fontSize(14).width('100%').padding(24) }.width('100%').height('100%').backgroundColor($r('app.color.theme_f7f4ed')) }
}
