import { common } from '@kit.AbilityKit';
import { UpdatesVM } from '../vm/UpdatesVM';
import { ChapterUpdate } from '../storage/UpdateRepository';
@Component
export struct UpdatesPanel {
  @State private vm: UpdatesVM = new UpdatesVM();
  @Prop @Watch('reload') revision: number = 0;
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.vm.dispose(); }
  private reload(): void { this.vm.load(); }
  build() {
    Column({ space: 14 }) {
      Row() { Text('更新').fontSize(28).fontWeight(FontWeight.Bold).layoutWeight(1); Button(this.vm.busy ? '取消' : '检查更新').fontSize(13).backgroundColor($r('app.color.theme_466948')).onClick(() => { if (this.vm.busy) { this.vm.cancel(); } else { this.vm.refresh(); } }) }.width('100%')
      Column({ space: 8 }) {
        Row() {
          Text('自动检查').layoutWeight(1)
          Select([{ value: '关闭' },{ value: '6小时' },{ value: '12小时' },{ value: '24小时' },{ value: '48小时' }])
            .selected([0,6,12,24,48].indexOf(this.vm.policy.hours)).value(this.vm.policy.hours ? this.vm.policy.hours.toString() + '小时' : '关闭')
            .onSelect((index: number) => { this.vm.policy.hours = [0,6,12,24,48][index]; this.vm.savePolicy(); })
        }.width('100%')
        Row() {
          Text('检查范围').layoutWeight(1)
          Select(this.vm.categoryOptions()).selected(this.vm.categoryIndex()).value(this.vm.categoryName())
            .onSelect((index: number) => { this.vm.policy.category = index > 0 ? this.vm.categories[index - 1].id : ''; this.vm.savePolicy(); })
        }.width('100%')
        Row() { Text('仅 Wi-Fi 检查').layoutWeight(1); Toggle({ type: ToggleType.Switch,isOn: this.vm.policy.wifiOnly }).onChange((value: boolean) => { this.vm.policy.wifiOnly = value; this.vm.savePolicy(); }) }.width('100%')
        Row() { Text('跳过还有未读章节的作品').layoutWeight(1); Toggle({ type: ToggleType.Switch,isOn: this.vm.policy.skipUnread }).onChange((value: boolean) => { this.vm.policy.skipUnread = value; this.vm.savePolicy(); }) }.width('100%')
        Row() { Text('自动下载发现的新章').layoutWeight(1); Toggle({ type: ToggleType.Switch,isOn: this.vm.policy.autoDownload }).onChange((value: boolean) => { this.vm.policy.autoDownload = value; this.vm.savePolicy(); }) }.width('100%')
        Text('前台到期检查，后台由系统择机检查；后台发现的新章排队等待前台下载。首次获取目录不下载全书。').fontSize(12).fontColor($r('app.color.theme_697365'))
      }.width('100%').enabled(!this.vm.busy)
      Text(this.vm.status).fontSize(13).fontColor($r('app.color.theme_697365')).width('100%')
      List({ space: 10 }) {
        LazyForEach(this.vm.data,(update: ChapterUpdate) => {
          ListItem() { Column({ space: 6 }) { Text(update.title).fontSize(17).fontWeight(FontWeight.Medium); Text(update.chapter).fontSize(14); Text(new Date(update.discoveredAt).toLocaleString()).fontSize(12).fontColor($r('app.color.theme_697365')) }.width('100%').padding(16).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_edf2e8')).borderRadius(14) }
            .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/ReaderPage',params: { chapterId: update.chapterId } }))
        },(update: ChapterUpdate) => update.chapterId)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(20).backgroundColor($r('app.color.theme_f8faf5'))
  }
}
