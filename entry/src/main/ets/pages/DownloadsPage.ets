import { common } from '@kit.AbilityKit';
import { DownloadTaskRecord } from '../model/DownloadTypes';
import { DownloadsVM } from '../vm/DownloadsVM';

@Entry
@Component
struct DownloadsPage {
  @State private vm: DownloadsVM = new DownloadsVM();
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.vm.dispose(); }
  private remove(task: DownloadTaskRecord): void {
    this.getUIContext().showAlertDialog({ title: '删除离线文件', message: task.mangaTitle + ' · ' + task.chapterTitle + ' 的下载文件将被删除，书架和阅读进度保留。',
      primaryButton: { value: '保留', action: () => {} }, secondaryButton: { value: '删除文件', action: () => this.vm.action(task, 'delete') } });
  }
  build() {
    Column({ space: 12 }) {
      Text('下载 · ' + this.vm.count.toString()).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_254e50'))
      Text('切到后台时尝试完成当前图像，其余回到前台继续；强制结束后按页恢复。离线文件不受清缓存影响。').fontSize(13)
      Text(this.vm.background).fontSize(12).fontColor($r('app.color.theme_697365'))
      Text(this.vm.status).fontSize(13)
      if (this.vm.busy) { Button('取消导出').fontSize(12).onClick(() => this.vm.cancelExport()) }
      List({ space: 10 }) {
        LazyForEach(this.vm.data, (task: DownloadTaskRecord) => {
          ListItem() {
            Column({ space: 10 }) {
              Text(task.mangaTitle + ' · ' + task.chapterTitle).fontSize(18).fontWeight(FontWeight.Medium)
              Text(this.vm.label(task)).fontSize(13)
              if (task.state === 'queued') {
                Row({ space: 8 }) { Button('上移').fontSize(12).enabled(!this.vm.busy).onClick(() => this.vm.action(task,'up')); Button('下移').fontSize(12).enabled(!this.vm.busy).onClick(() => this.vm.action(task,'down')) }
              }
              Row({ space: 6 }) {
                if (task.state === 'running' || task.state === 'queued') {
                  Button('暂停').fontSize(13).enabled(!this.vm.busy).onClick(() => this.vm.action(task, 'pause'))
                } else if (task.state !== 'completed') {
                  Button(task.state === 'failed' ? '重试' : '继续').fontSize(13).enabled(!this.vm.busy).onClick(() => this.vm.action(task, 'resume'))
                }
                if (task.state !== 'completed' && task.state !== 'cancelled') {
                  Button('取消任务').fontSize(13).enabled(!this.vm.busy).onClick(() => this.vm.action(task, 'cancel'))
                }
                if (task.completed > 0) {
                  Button(task.state === 'completed' ? '离线阅读' : '阅读已下载页').fontSize(13).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/ReaderPage', params: { chapterId: task.chapterId, offlineOnly: true } }))
                }
              }
              if (task.completed > 0 && task.state !== 'running') {
                Row({ space: 8 }) {
                  if (task.sourceId !== 'org.hsmihon.local') { Button('检查并修复').fontSize(13).enabled(!this.vm.busy).onClick(() => this.vm.action(task, 'repair')) }
                  if (task.state === 'completed') { Button('导出CBZ').fontSize(13).enabled(!this.vm.busy).onClick(() => this.vm.export(task)) }
                  Button('删除离线文件').fontSize(13).enabled(!this.vm.busy).onClick(() => this.remove(task))
                }
              }
            }.width('100%').padding(16).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_ffffff'))
          }
        }, (task: DownloadTaskRecord) => task.id + ':' + task.updatedAt.toString() + ':' + task.state)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_f7f4ed'))
  }
}
