import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { DownloadTaskRecord } from '../model/DownloadTypes';
import { isTabletLandscape } from '../ui/TabletLayout';
import { DownloadsVM } from '../vm/DownloadsVM';

@Entry
@Component
struct DownloadsPage {
  @State private vm: DownloadsVM = new DownloadsVM();
  @State private compact: boolean = false;
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.vm.dispose(); }
  private remove(task: DownloadTaskRecord): void {
    this.getUIContext().showAlertDialog({ title: '删除离线文件', message: task.mangaTitle + ' · ' + task.chapterTitle + ' 的下载文件将被删除，书架和阅读进度保留。',
      primaryButton: { value: '保留', action: () => {} }, secondaryButton: { value: '删除文件', action: () => this.vm.action(task, 'delete') } });
  }
  @Styles
  private actionSize() {
    .constraintSize({ minHeight: this.compact ? 44 : undefined })
  }

  @Builder
  private queueActions(task: DownloadTaskRecord) {
    Button('上移').fontSize(12).actionSize().enabled(!this.vm.busy).onClick(() => this.vm.action(task,'up'))
    Button('下移').fontSize(12).actionSize().enabled(!this.vm.busy).onClick(() => this.vm.action(task,'down'))
  }

  @Builder
  private taskActions(task: DownloadTaskRecord) {
    if (task.state === 'running' || task.state === 'queued') {
      Button('暂停').fontSize(13).actionSize().enabled(!this.vm.busy).onClick(() => this.vm.action(task, 'pause'))
    } else if (task.state !== 'completed') {
      Button(task.state === 'failed' ? '重试' : '继续').fontSize(13).actionSize()
        .enabled(!this.vm.busy).onClick(() => this.vm.action(task, 'resume'))
    }
    if (task.state !== 'completed' && task.state !== 'cancelled') {
      Button('取消任务').fontSize(13).actionSize().enabled(!this.vm.busy).onClick(() => this.vm.action(task, 'cancel'))
    }
    if (task.completed > 0) {
      Button(task.state === 'completed' ? '离线阅读' : '阅读已下载页').fontSize(13).actionSize()
        .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/ReaderPage', params: { chapterId: task.chapterId, offlineOnly: true } }))
    }
  }

  @Builder
  private fileActions(task: DownloadTaskRecord) {
    if (task.sourceId !== 'org.hsmihon.local') {
      Button('检查并修复').fontSize(13).actionSize().enabled(!this.vm.busy).onClick(() => this.vm.action(task, 'repair'))
    }
    if (task.state === 'completed') {
      Button('导出CBZ').fontSize(13).actionSize().enabled(!this.vm.busy).onClick(() => this.vm.export(task))
    }
    Button('删除离线文件').fontSize(13).actionSize().enabled(!this.vm.busy).onClick(() => this.remove(task))
  }

  @Builder
  private compactTask(task: DownloadTaskRecord) {
    Row({ space: 14 }) {
      Column({ space: 2 }) {
        Text(task.mangaTitle).fontSize(16).fontWeight(FontWeight.Medium).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).wordBreak(WordBreak.BREAK_WORD)
        Text(task.chapterTitle).fontSize(14).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).wordBreak(WordBreak.BREAK_WORD)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Column({ space: 4 }) {
        Text(this.vm.label(task)).fontSize(13).wordBreak(WordBreak.BREAK_WORD)
        if (task.total > 0) {
          Progress({ value: task.completed, total: task.total, type: ProgressType.Linear })
            .width('100%').style({ strokeWidth: 4 })
        }
      }.width('15%').alignItems(HorizontalAlign.Start)
      Flex({
        wrap: FlexWrap.Wrap, justifyContent: FlexAlign.End,
        space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(4) }
      }) {
        this.taskActions(task)
        if (task.state === 'queued') { this.queueActions(task) }
        if (task.completed > 0 && task.state !== 'running') { this.fileActions(task) }
      }.width('46%')
    }.width('100%').padding({ left: 12, right: 12, top: 5, bottom: 5 }).backgroundColor($r('app.color.theme_ffffff'))
  }

  build() {
    Column({ space: this.compact ? 6 : 12 }) {
      Text('下载 · ' + this.vm.count.toString()).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_254e50'))
      Text('切到后台时尝试完成当前图像，其余回到前台继续；强制结束后按页恢复。离线文件不受清缓存影响。').fontSize(13)
      if (this.compact) {
        Row({ space: 12 }) {
          Text(this.vm.background).fontSize(12).fontColor($r('app.color.theme_697365'))
          Text(this.vm.status).fontSize(13)
          if (this.vm.busy) { Button('取消导出').fontSize(12).actionSize().onClick(() => this.vm.cancelExport()) }
        }
      } else {
        Text(this.vm.background).fontSize(12).fontColor($r('app.color.theme_697365'))
        Text(this.vm.status).fontSize(13)
        if (this.vm.busy) { Button('取消导出').fontSize(12).onClick(() => this.vm.cancelExport()) }
      }
      List({ space: this.compact ? 6 : 10 }) {
        LazyForEach(this.vm.data, (task: DownloadTaskRecord) => {
          ListItem() {
            if (this.compact) {
              this.compactTask(task)
            } else {
              Column({ space: 10 }) {
                Text(task.mangaTitle + ' · ' + task.chapterTitle).fontSize(18).fontWeight(FontWeight.Medium)
                Text(this.vm.label(task)).fontSize(13)
                if (task.state === 'queued') { Row({ space: 8 }) { this.queueActions(task) } }
                Row({ space: 6 }) { this.taskActions(task) }
                if (task.completed > 0 && task.state !== 'running') {
                  Row({ space: 8 }) { this.fileActions(task) }
                }
              }.width('100%').padding(16).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_ffffff'))
            }
          }
        }, (task: DownloadTaskRecord) => task.id + ':' + task.updatedAt.toString() + ':' + task.state)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%')
      .padding({ left: 20, right: 20, top: this.compact ? 10 : 20, bottom: this.compact ? 10 : 20 })
      .alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_f7f4ed'))
      .onAreaChange((_old: Area, area: Area) => { this.compact = isTabletLandscape(area); })
  }
}
