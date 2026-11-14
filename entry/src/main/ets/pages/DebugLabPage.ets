import { common } from '@kit.AbilityKit';
import BuildProfile from 'BuildProfile';
import { DebugLabVM } from '../vm/DebugLabVM';
import { ReaderTraceEntry } from '../diagnostic/ReaderTrace';

@Entry
@Component
struct DebugLabPage {
  @State private vm: DebugLabVM = new DebugLabVM();

  aboutToAppear(): void {
    this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  aboutToDisappear(): void { this.vm.dispose(); }

  private formatTraceTime(timestamp: number): string {
    const date = new Date(timestamp);
    const month = date.getMonth() + 1; const day = date.getDate();
    const hours = date.getHours(); const minutes = date.getMinutes(); const seconds = date.getSeconds();
    return month.toString() + '/' + day.toString() + ' ' + (hours < 10 ? '0' : '') + hours.toString() + ':' +
      (minutes < 10 ? '0' : '') + minutes.toString() + ':' + (seconds < 10 ? '0' : '') + seconds.toString();
  }

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
        Text('阅读性能日志').fontSize(20).fontWeight(FontWeight.Medium)
        Text('日志最多保留最近 1500 条；离开阅读器时写入本地私有存储。字段只包含来源标识、页号、阶段、耗时、缓存层级和数值计时。')
          .fontSize(13).fontColor('#53645E')
        TextInput({ text: this.vm.traceQuery,placeholder: '检索阶段、缓存层级、角色、页号或来源标识' })
          .onChange((value: string) => { this.vm.traceQuery = value; })
        Row({ space: 10 }) {
          Button('检索最近日志').onClick(() => this.vm.searchReaderLogs())
          Button('清空阅读日志').onClick(() => this.vm.clearReaderLogs())
        }
        Text('匹配结果：' + this.vm.traceRows.length.toString() + ' / 当前保留：' + this.vm.traceTotal.toString()).fontSize(13)
        ForEach(this.vm.traceRows,(entry: ReaderTraceEntry) => {
          Column({ space: 3 }) {
            Text('#' + entry.sequence.toString() + '  ' + entry.stage + '  ' + entry.durationMs.toString() + ' ms  [' + entry.outcome + ']')
              .fontSize(13).fontWeight(FontWeight.Medium).width('100%')
            Text('时间 ' + this.formatTraceTime(entry.timestamp) + ' · 会话 ' + entry.sessionId.substring(0,8) + ' · 操作 ' + entry.operationId.substring(0,8) +
              ' · ' + (entry.pageIndex > 0 ? '页 ' + entry.pageIndex.toString() : '章节') +
              (entry.partIndex > 0 ? ' · 分块 ' + entry.partIndex.toString() : '') + ' · ' + entry.role + ' · ' + entry.sourceId)
              .fontSize(11).fontColor('#53645E').width('100%')
            Text('缓存 ' + (entry.cacheTier || '—') + ' · 数量 ' + entry.count.toString() + ' · 字节 ' + entry.bytes.toString() +
              (entry.stage === 'network-http' && entry.metrics.length >= 5 ? ' · DNS/TCP/TLS/首字节/正文(ms) ' + entry.metrics.slice(0,5).join('/') : ''))
              .fontSize(11).fontColor('#53645E').width('100%')
          }.width('100%').padding(9).backgroundColor('#E6EEEA').borderRadius(6)
        },(entry: ReaderTraceEntry) => entry.sequence.toString())
      }
      .width('100%').padding(24).alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').backgroundColor('#F7F4ED')
  }
}
