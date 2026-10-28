import { common } from '@kit.AbilityKit';
import BuildProfile from 'BuildProfile';
import { DebugLabVM } from '../vm/DebugLabVM';

@Entry
@Component
struct DebugLabPage {
  @State private vm: DebugLabVM = new DebugLabVM();

  aboutToAppear(): void {
    this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  aboutToDisappear(): void { this.vm.dispose(); }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('开发实验室 · P0').fontSize(26).fontWeight(FontWeight.Bold)
        Text('API 26 / ' + BuildProfile.BUILD_MODE_NAME + ' / ' + BuildProfile.TARGET_NAME).fontSize(14)
        Text('以下按钮调用真实系统能力。构建成功与设备验收分别记录。').fontSize(14)
        Text(this.vm.status).fontSize(15).width('100%').padding(12).backgroundColor('#E6EEEA')
        Text('数据库与私有文件').fontSize(20).fontWeight(FontWeight.Medium)
        Button('解析器自检').enabled(!this.vm.busy).onClick(() => this.vm.parserProbe())
        Button('归档解码与限额验证').enabled(!this.vm.busy).onClick(() => this.vm.archiveProbe())
        Button('本地JSON/HTML双源全链路').enabled(!this.vm.busy).onClick(() => this.vm.sourceScenario())
        Button('规则更新与回滚验证').enabled(!this.vm.busy).onClick(() => this.vm.ruleUpdateScenario())
        Button('普通图片与释放验证').enabled(!this.vm.busy).onClick(() => this.vm.imageProbe(false))
        Button('长图区域解码验证').enabled(!this.vm.busy).onClick(() => this.vm.imageProbe(true))
        Button('写入持久化探针').enabled(!this.vm.busy).onClick(() => this.vm.writeStorage())
        Button('读取已有探针（重启后使用）').enabled(!this.vm.busy).onClick(() => this.vm.readStorage())
        Text('本地样本服务').fontSize(20).fontWeight(FontWeight.Medium)
        TextInput({ text: this.vm.baseUrl, placeholder: 'http://电脑IP:8765' })
          .enabled(!this.vm.busy).onChange((value: string) => { this.vm.baseUrl = value; })
        Button('GET /health').enabled(!this.vm.busy).onClick(() => this.vm.request())
        Button('系统下载代理边界验证').enabled(!this.vm.busy).onClick(() => this.vm.agentProbe())
        Button('流式写入并核对文件').enabled(!this.vm.busy).onClick(() => this.vm.stream())
        Button('验证 1.5 秒超时').enabled(!this.vm.busy)
          .onClick(() => this.vm.request('/fault/slow?ms=5000', 1500))
        Button('同域跳转').enabled(!this.vm.busy).onClick(() => this.vm.request('/fault/redirect'))
        Button('跨域跳转（预期 POLICY_DENIED）').enabled(!this.vm.busy)
          .onClick(() => this.vm.request('/fault/cross-host'))
        Button('取消当前操作').enabled(this.vm.busy).onClick(() => this.vm.cancel())
      }
      .width('100%').padding(24).alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').backgroundColor('#F7F4ED')
  }
}
