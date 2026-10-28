import { common } from '@kit.AbilityKit';
import { CategoryRecord, ChapterRecord } from '../model/LibraryTypes';
import { DetailVM } from '../vm/DetailVM';
import { MangaCover } from '../ui/MangaCover';
interface DetailParams { mangaId: string; }
@Entry
@Component
struct DetailPage {
  @State private vm: DetailVM = new DetailVM();
  @State private selection: boolean = false;
  @State private expanded: boolean = false;
  @State private categoriesVisible: boolean = false;
  aboutToAppear(): void { const params = this.getUIContext().getRouter().getParams() as DetailParams; this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext,params.mangaId || ''); }
  onPageShow(): void { this.vm.reloadCached(); }
  aboutToDisappear(): void { this.vm.dispose(); }
  private read(id: string): void { this.getUIContext().getRouter().pushUrl({ url: 'pages/ReaderPage',params: { chapterId: id } }); }
  onBackPress(): boolean { if (this.selection) { this.selection = false; this.vm.selected = []; return true; } return false; }
  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Row({ space: 8 }) {
          Button('返回').fontSize(13).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).onClick(() => this.getUIContext().getRouter().back())
          Text(this.selection ? '已选择 ' + this.vm.selected.length.toString() + ' 章' : '漫画详情').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
          Button(this.vm.busy ? '取消' : '刷新').fontSize(13).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).onClick(() => { if (this.vm.busy) { this.vm.cancel(); } else { this.vm.refresh(); } })
        }.width('100%').height(52).padding({ left: 8,right: 8 })
        List({ space: 12 }) {
          ListItem() {
            Row({ space: 18 }) {
              MangaCover({ sourceId: this.vm.sourceId,mangaId: this.vm.remoteId,address: this.vm.cover,title: this.vm.title }).width(112)
              Column({ space: 10 }) {
                Text(this.vm.title).fontSize(25).fontWeight(FontWeight.Bold).maxLines(4)
                if (this.vm.authors) { Text(this.vm.authors).fontSize(14).fontColor($r('app.color.theme_697365')) }
                Text(this.vm.sourceId).fontSize(12).fontColor($r('app.color.theme_697365')).maxLines(2)
                Button(this.vm.favorite ? '已加入书架' : '加入书架').fontSize(13).backgroundColor(this.vm.favorite ? $r('app.color.theme_d5e7ca') : $r('app.color.theme_466948')).fontColor(this.vm.favorite ? $r('app.color.theme_29452d') : $r('app.color.theme_on_accent')).enabled(!this.vm.busy).onClick(() => this.vm.toggleFavorite())
                Button('Tracking').fontSize(12).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/TrackingPage',params: { mangaId: (this.getUIContext().getRouter().getParams() as DetailParams).mangaId } }))
                Button('跨源迁移').fontSize(12).enabled(!this.vm.busy).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/MigrationPage',params: { mangaId: (this.getUIContext().getRouter().getParams() as DetailParams).mangaId,title: this.vm.title } }))
                if (this.vm.favorite) { Button('分类').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).onClick(() => { this.categoriesVisible = !this.categoriesVisible; }) }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').padding({ top: 12,bottom: 12 })
          }
          if (this.categoriesVisible && this.vm.categories.length > 0) {
            ListItem() { Flex({ wrap: FlexWrap.Wrap }) { ForEach(this.vm.categories,(category: CategoryRecord) => { Button((this.vm.assigned.indexOf(category.id) >= 0 ? '✓ ' : '') + category.name).fontSize(12).margin(4).enabled(!this.vm.busy).onClick(() => this.vm.assign(category)) },(category: CategoryRecord) => category.id) } }
          }
          ListItem() {
            Column({ space: 10 }) {
              Text(this.vm.description || '暂无简介').fontSize(14).fontColor($r('app.color.theme_43503e')).maxLines(this.expanded ? 100 : 3).width('100%')
              if (this.vm.description.length > 80) { Text(this.expanded ? '收起简介' : '展开简介').fontSize(12).fontColor($r('app.color.theme_466948')).onClick(() => { this.expanded = !this.expanded; }) }
              if (this.vm.tags) { Text(this.vm.tags).fontSize(12).fontColor($r('app.color.theme_697365')) }
              Text(this.vm.status).fontSize(12).fontColor($r('app.color.theme_697365')).width('100%')
            }.alignItems(HorizontalAlign.Start).padding({ bottom: 8 })
          }
          ListItem() {
            Row() {
              Text('章节 · ' + this.vm.count.toString()).fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
              Button(this.vm.reverse ? '顺序' : '倒序').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).onClick(() => this.vm.sort())
              Button(this.selection ? '取消选择' : '选择').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).onClick(() => { this.selection = !this.selection; if (!this.selection) { this.vm.selected = []; } })
            }.width('100%')
          }
          if (this.selection) {
            ListItem() { Row({ space: 8 }) { Button('全选 / 清空').fontSize(13).onClick(() => this.vm.all()); Button('下载所选 ' + this.vm.selected.length.toString()).fontSize(13).enabled(!this.vm.busy && this.vm.selected.length > 0).onClick(() => this.vm.download(this.vm.selected.slice())); Button('下载管理').fontSize(13).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/DownloadsPage' })) } }
            ListItem() { Row({ space: 8 }) {
              Button('标记已读').fontSize(13).enabled(!this.vm.busy && this.vm.selected.length > 0).onClick(() => this.vm.mark(true))
              Button('标记未读').fontSize(13).enabled(!this.vm.busy && this.vm.selected.length > 0).onClick(() => this.vm.mark(false))
            } }
          }
          ListItem() { Column({ space: 8 }) {
            TextInput({ text: this.vm.chapterQuery,placeholder: '搜索章节标题' }).maxLength(128).onChange((value: string) => this.vm.searchChapters(value))
            Row({ space: 8 }) {
              Select([{ value: '全部' },{ value: '未读' },{ value: '已读' },{ value: '书签' },{ value: '已下载' }]).selected(['all','unread','read','bookmark','offline'].indexOf(this.vm.filter)).value(['全部','未读','已读','书签','已下载'][['all','unread','read','bookmark','offline'].indexOf(this.vm.filter)])
                .onSelect((index: number) => { if (index >= 0 && index < 5) { this.vm.filterChapters(['all','unread','read','bookmark','offline'][index]); } })
              Text('显示 ' + this.vm.visibleCount.toString() + ' / ' + this.vm.count.toString()).fontSize(12).fontColor($r('app.color.theme_697365'))
            }
          } }
          LazyForEach(this.vm.data,(chapter: ChapterRecord) => {
            ListItem() {
              Row({ space: 10 }) {
                if (this.selection) { Checkbox().select(this.vm.selected.indexOf(chapter.id) >= 0).onChange(() => this.vm.select(chapter.id)) }
                Column({ space: 5 }) {
                  Text(chapter.title + (chapter.active ? '' : '（目录已移除）')).fontSize(16).fontWeight(FontWeight.Medium)
                  Text((chapter.read ? '已读' : '未读') + (chapter.lastReadAt > 0 && !chapter.read ? ' · 读至第' + (chapter.lastPage + 1).toString() + '张' : '') + (chapter.downloaded ? ' · 已下载' : ' · 在线')).fontSize(12).fontColor($r('app.color.theme_697365'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ top: 14,bottom: 14 }).onClick(() => { if (this.selection) { this.vm.select(chapter.id); } else { this.read(chapter.id); } })
                Button(chapter.bookmarked ? '★' : '☆').fontSize(20).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).accessibilityText(chapter.bookmarked ? '取消章节书签' : '添加章节书签').enabled(!this.vm.busy).onClick(() => this.vm.bookmark(chapter))
                Button(chapter.downloaded ? '已离线' : '下载').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).enabled(!this.vm.busy && !chapter.downloaded).onClick(() => this.vm.download([chapter.id]))
              }.width('100%').padding({ left: 10,right: 4 }).backgroundColor(this.vm.selected.indexOf(chapter.id) >= 0 ? $r('app.color.theme_d9e8d2') : $r('app.color.theme_eff3eb')).borderRadius(12)
            }.gesture(LongPressGesture().onAction(() => { this.selection = true; this.vm.select(chapter.id); }))
          },(chapter: ChapterRecord) => chapter.id)
        }.width('100%').layoutWeight(1).padding({ left: 20,right: 20 }).contentEndOffset(92)
      }.width('100%').height('100%')
      if (!this.selection && this.vm.continueId) { Button('开始或继续阅读').fontSize(16).height(52).padding({ left: 24,right: 24 }).backgroundColor($r('app.color.theme_d0e7c2')).fontColor($r('app.color.theme_233d21')).margin(20).enabled(!this.vm.busy).onClick(() => this.read(this.vm.continueId)) }
    }.width('100%').height('100%').backgroundColor($r('app.color.theme_f8faf5'))
  }
}
