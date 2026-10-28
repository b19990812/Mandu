import { RuleSubscription } from '../source/RuleSubscriptionService';
import { common } from '@kit.AbilityKit';
import { ManagedSource } from '../source/SourceImportService';
import { RuleManagerVM } from '../vm/RuleManagerVM';

@Entry
@Component
struct RuleManagerPage {
  @State private vm: RuleManagerVM = new RuleManagerVM();
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.vm.dispose(); }
  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('源规则').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_254e50'))
        Text(this.vm.status).fontSize(15).width('100%').padding(12).backgroundColor($r('app.color.theme_e6eeea'))
        Text('规则订阅').fontSize(21)
        TextInput({ text: this.vm.subscriptionUrl,placeholder: 'HTTPS 规则 JSON 网址' }).enabled(!this.vm.busy).onChange((value: string) => { this.vm.subscriptionUrl = value; })
        TextInput({ text: this.vm.expectedDigest,placeholder: '可选：发布者提供的 SHA256' }).maxLength(64).enabled(!this.vm.busy).onChange((value: string) => { this.vm.expectedDigest = value; })
        Button('下载订阅并预览').enabled(!this.vm.busy && this.vm.subscriptionUrl.trim() !== '').onClick(() => this.vm.fetchSubscription())
        ForEach(this.vm.subscriptions,(item: RuleSubscription) => {
          Column({ space: 6 }) {
            Text(item.sourceId).fontSize(15)
            Text(item.address).fontSize(12)
            Row({ space: 8 }) {
              Button('检查订阅更新').enabled(!this.vm.busy).onClick(() => this.vm.fetchSubscription(item))
              Button('取消订阅').enabled(!this.vm.busy).onClick(() => this.vm.removeSubscription(item))
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        },(item: RuleSubscription) => item.sourceId)
        Button('选择本地JSON文件').enabled(!this.vm.busy).onClick(() => this.vm.pick())
        TextArea({ text: this.vm.input, placeholder: '也可粘贴源规则JSON' }).height(180).maxLength(262144).enabled(!this.vm.busy)
          .onChange((value: string) => this.vm.change(value))
        Button('校验并预览').enabled(!this.vm.busy && this.vm.input !== '').onClick(() => this.vm.inspect())
        if (this.vm.hasPreview) {
          Text(this.vm.previewText).width('100%').fontSize(14).padding(12).backgroundColor($r('app.color.theme_ffffff'))
          Button('确认规则并激活').enabled(!this.vm.busy).onClick(() => this.vm.activate())
        }
        Text('已导入源').fontSize(21).fontWeight(FontWeight.Medium)
        Button('重新读取规则').enabled(!this.vm.busy).onClick(() => this.vm.reload())
        if (this.vm.sources.length === 0) { Text('尚未导入源，可先使用下方自有演示规则。').fontSize(14) }
        ForEach(this.vm.sources, (item: ManagedSource) => {
          Column({ space: 10 }) {
            Text(item.rule.name + ' · v' + item.rule.sourceVersion.toString()).fontSize(18).fontWeight(FontWeight.Medium)
            Text(item.state.id + '\n' + item.rule.baseUrl + '\n' + (item.state.enabled ? '已启用' : '已禁用')).fontSize(13)
            Row({ space: 10 }) {
              Button(item.state.enabled ? '禁用' : '启用').enabled(!this.vm.busy).onClick(() => this.vm.toggle(item))
              Button('回滚上一版本').enabled(!this.vm.busy && item.state.lastGood !== '').onClick(() => this.vm.rollback(item))
              Button('移除').enabled(!this.vm.busy).onClick(() => this.vm.remove(item))
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(14).backgroundColor($r('app.color.theme_ffffff'))
        }, (item: ManagedSource) => item.state.id + ':' + item.state.revision.toString())
        Text('自有演示规则').fontSize(21).fontWeight(FontWeight.Medium)
        Text('以下只控制内置合成网站，用来观察网站改版后替换规则的效果。').fontSize(14)
        Row({ space: 10 }) {
          Button('JSON v1').enabled(!this.vm.busy).onClick(() => this.vm.sample('json-v1.json'))
          Button('JSON v2').enabled(!this.vm.busy).onClick(() => this.vm.sample('json-v2.json'))
        }
        Row({ space: 10 }) {
          Button('HTML v1').enabled(!this.vm.busy).onClick(() => this.vm.sample('html-v1.json'))
          Button('HTML v2').enabled(!this.vm.busy).onClick(() => this.vm.sample('html-v2.json'))
          Button('非法v3示例').enabled(!this.vm.busy).onClick(() => this.vm.sample('invalid-v3.json'))
        }
        Text('演示网站当前结构：v' + this.vm.demoRevision.toString()).fontSize(14)
        Row({ space: 10 }) {
          Button('网站结构v1').enabled(!this.vm.busy).onClick(() => this.vm.setDemoRevision(1))
          Button('网站结构v2').enabled(!this.vm.busy).onClick(() => this.vm.setDemoRevision(2))
        }
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.theme_f7f4ed'))
  }
}
