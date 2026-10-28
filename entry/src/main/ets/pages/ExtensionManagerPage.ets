import { common } from '@kit.AbilityKit';
import { ExtensionManagerVM } from '../vm/ExtensionManagerVM';
import { ExtensionEntry, AdditionalSource } from '../source/ExtensionCatalog';
import { SavedRepository } from '../source/ExtensionRepositoryService';

@Entry
@Component
struct ExtensionManagerPage {
  @State private vm: ExtensionManagerVM = new ExtensionManagerVM();
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.vm.dispose(); }
  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row({ space: 12 }) { Button('返回').onClick(() => this.getUIContext().getRouter().back()); Text('扩展仓库').fontSize(26).fontWeight(FontWeight.Bold) }.width('100%')
        Text(this.vm.status).width('100%').fontSize(14).padding(12).backgroundColor($r('app.color.theme_e6eeea'))
        TextInput({ text: this.vm.address,placeholder: 'HTTPS index.min.json 地址' }).maxLength(2048).enabled(!this.vm.busy).onChange((value: string) => this.vm.change(value))
        Button('读取并预览目录').enabled(!this.vm.busy).onClick(() => this.vm.fetch())
        if (this.vm.hasPreview) { Button('确认保存仓库目录').enabled(!this.vm.busy).onClick(() => this.vm.save()) }
        ForEach(this.vm.repositories,(repo: SavedRepository) => {
          Column({ space: 8 }) {
            Text(repo.address).fontSize(12).width('100%')
            Text('保存时间：' + new Date(repo.updatedAt).toLocaleString()).fontSize(12)
            Row({ space: 8 }) { Button('查看目录').enabled(!this.vm.busy).onClick(() => this.vm.show(repo)); Button('检查更新').enabled(!this.vm.busy).onClick(() => this.vm.fetch(repo.address)); Button('移除仓库').enabled(!this.vm.busy).onClick(() => this.vm.remove(repo)) }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor($r('app.color.theme_ffffff'))
        },(repo: SavedRepository) => repo.key)
        ForEach(this.vm.entries,(entry: ExtensionEntry) => {
          Column({ space: 6 }) {
            Text(entry.name + (entry.nsfw ? ' · 18+' : '')).fontSize(20).fontWeight(FontWeight.Medium)
            Text(entry.lang + ' · 上游 v' + entry.version + ' · code ' + entry.code.toString()).fontSize(13)
            Text(entry.baseUrl).fontSize(12)
            Text(entry.status).fontSize(14)
            if (entry.nativeId) { Button('启用本项目适配器').enabled(!this.vm.busy && !this.vm.hasPreview).onClick(() => this.vm.enable(entry)) }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor($r('app.color.theme_ffffff'))
        },(entry: ExtensionEntry) => entry.pkg + ':' + entry.externalId)
        Text('新增网站适配状态').fontSize(21).width('100%')
        ForEach(this.vm.additional,(item: AdditionalSource) => {
          Column({ space: 6 }) {
            Text(item.name).fontSize(18)
            Text(item.address).fontSize(13)
            Text(item.status).fontSize(14)
            if (item.nativeId) { Button('启用本项目适配器').enabled(!this.vm.busy).onClick(() => this.vm.enableAdditional(item)) }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(12).backgroundColor($r('app.color.theme_ffffff'))
        },(item: AdditionalSource) => item.address)
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.theme_f8faf5'))
  }
}
