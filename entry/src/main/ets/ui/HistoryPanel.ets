import { common } from '@kit.AbilityKit';
import { HistoryRecord } from '../model/LibraryTypes';
import { HistoryVM } from '../vm/HistoryVM';
import { HISTORY_DELETE_RANGES, HistoryDeleteRange } from '../model/HistoryDeletion';

@Component
export struct HistoryPanel {
  @State private vm: HistoryVM = new HistoryVM();
  @State private bulk: boolean = false;
  @State private rangeIndex: number = 1;
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.vm.dispose(); }
  @Prop @Watch('reload') revision: number = 0;
  private reload(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  private async remove(range: string,mangaId: string = '',title: string = ''): Promise<void> {
    const plan = await this.vm.prepareRemoval(range,mangaId); if (!plan) { return; }
    const label = mangaId ? '《' + title + '》' : HISTORY_DELETE_RANGES.find((item: HistoryDeleteRange) => item.id === range)?.label || '';
    this.getUIContext().showAlertDialog({ title: range === 'all' && !mangaId ? '清空阅读历史' : '删除阅读历史',
      message: label + '：将删除 ' + plan.targets.length.toString() + ' 部漫画的历史记录。阅读进度、收藏、书签和下载会保留。',
      primaryButton: { value: '取消',action: () => {} },secondaryButton: { value: '删除历史',action: () => this.vm.applyRemoval(plan) } });
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text('阅读历史').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_254e50')).layoutWeight(1)
        Button(this.bulk ? '收起管理' : '批量删除').fontSize(13).enabled(!this.vm.busy).onClick(() => { this.bulk = !this.bulk; })
      }.width('100%')
      if (this.bulk) {
        Row({ space: 12 }) {
          Select(HISTORY_DELETE_RANGES.map((item: HistoryDeleteRange): SelectOption => ({ value: item.label })))
            .selected(this.rangeIndex).value(HISTORY_DELETE_RANGES[this.rangeIndex].label).font({ size: 14 }).layoutWeight(1)
            .enabled(!this.vm.busy).onSelect((index: number) => { if (index >= 0 && index < HISTORY_DELETE_RANGES.length) { this.rangeIndex = index; } })
          Button(this.rangeIndex === 5 ? '清空历史' : '删除所选时段').fontSize(13).enabled(!this.vm.busy && this.vm.count > 0)
            .onClick(() => this.remove(HISTORY_DELETE_RANGES[this.rangeIndex].id))
        }.width('100%')
        Text('按最近阅读时间筛选，仅删除历史列表记录。').fontSize(12).fontColor($r('app.color.theme_697365'))
      }
      Text(this.vm.status).fontSize(14).width('100%')
      List({ space: 12 }) {
        LazyForEach(this.vm.data, (item: HistoryRecord) => {
          ListItem() {
            Column({ space: 10 }) {
              Text(item.manga.detail.title).fontSize(20).fontWeight(FontWeight.Medium)
              Text(item.chapterTitle + ' · 图像' + (item.progress.pageIndex + 1).toString() + (item.progress.completed ? ' · 已读完' : '')).fontSize(14)
              Text(new Date(item.progress.updatedAt).toLocaleString()).fontSize(12).fontColor($r('app.color.theme_697365'))
              Row({ space: 12 }) {
                Button('继续阅读').enabled(!this.vm.busy).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/ReaderPage', params: { chapterId: item.progress.chapterId } }))
                Button('删除历史').enabled(!this.vm.busy).onClick(() => this.remove('all',item.manga.id,item.manga.detail.title))
              }
            }.width('100%').padding(16).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_ffffff'))
          }
        }, (item: HistoryRecord) => item.manga.id + ':' + item.progress.chapterId + ':' + item.progress.updatedAt.toString())
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_f8faf5'))
  }
}

