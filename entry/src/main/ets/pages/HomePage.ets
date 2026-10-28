import BuildProfile from 'BuildProfile';
import { LibraryPanel } from '../ui/LibraryPanel';
import { HistoryPanel } from '../ui/HistoryPanel';
import { BrowsePanel } from '../ui/BrowsePanel';
import { UpdatesPanel } from '../ui/UpdatesPanel';

@Entry
@Component
struct HomePage {
  @State private selected: number = 0;
  @State private revision: number = 0;
  onPageShow(): void { this.revision++; }
  private open(page: string): void { this.getUIContext().getRouter().pushUrl({ url: 'pages/' + page }); }
  @Builder
  private tab(index: number,title: string,symbol: string) {
    Column({ space: 3 }) {
      Text(symbol).fontSize(22).fontWeight(FontWeight.Medium).width(64).height(30).textAlign(TextAlign.Center)
        .backgroundColor(this.selected === index ? $r('app.color.theme_d5e7ca') : Color.Transparent).borderRadius(20).fontColor($r('app.color.theme_304a2c'))
      Text(title).fontSize(12).fontWeight(this.selected === index ? FontWeight.Bold : FontWeight.Normal).fontColor($r('app.color.theme_465540'))
    }.layoutWeight(1).height(58).justifyContent(FlexAlign.Center).onClick(() => { this.selected = index; })
  }
  @Builder
  private moreItem(title: string,description: string,page: string) {
    Row({ space: 12 }) {
      Column({ space: 5 }) { Text(title).fontSize(18).fontColor($r('app.color.theme_273326')); Text(description).fontSize(12).fontColor($r('app.color.theme_697365')) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(24).fontColor($r('app.color.theme_697365'))
    }.width('100%').padding(18).backgroundColor($r('app.color.theme_edf2e8')).borderRadius(14).onClick(() => this.open(page))
  }
  build() {
    Column() {
      Column() {
        if (this.selected === 0) { LibraryPanel({ revision: this.revision,onBrowse: () => { this.selected = 3; } }) }
        else if (this.selected === 1) { UpdatesPanel({ revision: this.revision }) }
        else if (this.selected === 2) { HistoryPanel({ revision: this.revision }) }
        else if (this.selected === 3) { BrowsePanel({ revision: this.revision }) }
        else {
          Scroll() {
            Column({ space: 14 }) {
              Text('更多').fontSize(28).fontWeight(FontWeight.Bold).width('100%')
              Text('漫读 · HarmonyOS').fontSize(16).fontColor($r('app.color.theme_697365')).width('100%').padding({ bottom: 12 })
              this.moreItem('下载管理','下载队列、暂停恢复、离线章节','DownloadsPage')
              this.moreItem('本地漫画','导入CBZ、ZIP或多张图片','LocalImportPage')
              this.moreItem('设置','阅读、缓存、网络与许可证','SettingsPage')
              this.moreItem('源规则','本地导入、手动更新与回滚','RuleManagerPage')
              this.moreItem('漫画源网站','修改目标网站地址','SourcesPage')
              this.moreItem('章节试读','从网址打开共用沉浸阅读器','ChapterReaderPage')
              if (BuildProfile.DEBUG && BuildProfile.TARGET_NAME.toString() === 'lab') { this.moreItem('打开开发实验室','开发构建专用验证入口','DebugLabPage') }
            }.width('100%').padding(20)
          }.width('100%').height('100%')
        }
      }.width('100%').layoutWeight(1)
      Row() {
        this.tab(0,'书架','▤')
        this.tab(1,'更新','↻')
        this.tab(2,'历史','◷')
        this.tab(3,'浏览','⌕')
        this.tab(4,'更多','•••')
      }.width('100%').height(68).backgroundColor($r('app.color.theme_e9f0e3')).padding({ left: 4,right: 4 })
    }.width('100%').height('100%').backgroundColor($r('app.color.theme_f8faf5'))
  }
}
