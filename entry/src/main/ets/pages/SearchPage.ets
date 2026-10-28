import { common } from '@kit.AbilityKit';
import { SearchVM, SearchResultRow } from '../vm/SearchVM';
import { MangaRecord } from '../model/LibraryTypes';
import { MangaCover } from '../ui/MangaCover';

@Entry
@Component
struct SearchPage {
  @State private vm: SearchVM = new SearchVM();
  private input: TextInputController = new TextInputController();
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext,'*'); }
  aboutToDisappear(): void { this.vm.dispose(); }
  private open(manga: MangaRecord): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/DetailPage',params: { mangaId: manga.id } });
  }
  private action(row: SearchResultRow): void {
    if (row.action === 'expand' || row.action === 'collapse') { this.vm.toggleSource(row.sourceId); }
    else { this.vm.searchSource(row.sourceId); }
  }
  private submit(): void { this.input.stopEditing(); this.vm.search(); }
  private emptySlots(row: SearchResultRow): number[] {
    const slots: number[] = []; for (let i = row.mangas?.length || 0; i < this.vm.columns; i++) { slots.push(i); } return slots;
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Button('返回').fontSize(12).onClick(() => this.getUIContext().getRouter().back())
        Text('全局搜索').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_254e50')).layoutWeight(1)
      }.width('100%')
      Text('搜索所有已激活漫画源 · 点击源标题可折叠').fontSize(13).fontColor($r('app.color.theme_697874'))
      TextInput({ text: this.vm.query, placeholder: '输入漫画名称或关键词',controller: this.input }).maxLength(256).enabled(this.vm.sourceId !== '')
        .enterKeyType(EnterKeyType.Search).onChange((value: string) => this.vm.change(value)).onSubmit(() => this.submit())
      Row({ space: 12 }) {
        Button('搜索全部来源').enabled(!this.vm.busy && this.vm.sourceId !== '' && this.vm.query.trim() !== '').onClick(() => this.submit())
        Button('取消搜索').enabled(this.vm.busy).onClick(() => this.vm.cancel())
      }
      if (this.vm.sources.length === 0) { Button('导入源规则').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/RuleManagerPage' })) }
      Row({ space: 8 }) {
        Text(this.vm.status).fontSize(13).layoutWeight(1)
        Button('全部展开').fontSize(12).enabled(this.vm.groups.length > 0).onClick(() => this.vm.foldAll(false))
        Button('全部折叠').fontSize(12).enabled(this.vm.groups.length > 0).onClick(() => this.vm.foldAll(true))
      }.width('100%')
      List({ space: 12 }) {
        LazyForEach(this.vm.groupedData, (row: SearchResultRow) => {
          ListItem() {
            if (row.kind === 'source') {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text(row.label).fontSize(19).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_273326'))
                  Text(row.detail).fontSize(12).fontColor($r('app.color.theme_697874'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(row.action === 'unfold' ? '展开 ▸' : '折叠 ▾').fontSize(14).fontColor($r('app.color.theme_466948'))
              }.width('100%').padding({ left: 16,right: 16,top: 12,bottom: 12 }).backgroundColor($r('app.color.theme_edf2e8')).borderRadius(14)
            } else if (row.kind === 'covers') {
              Row({ space: 14 }) {
                ForEach(row.mangas || [],(manga: MangaRecord) => {
                  Column({ space: 8 }) {
                    MangaCover({ sourceId: manga.detail.ref.sourceId,mangaId: manga.detail.ref.remoteId,address: manga.detail.cover || '',title: manga.detail.title })
                    Text(manga.detail.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.theme_273326')).maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(20).height(42).width('100%')
                  }.layoutWeight(1).padding(8).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_ffffff')).borderRadius(14)
                    .onClick(() => this.open(manga))
                },(manga: MangaRecord) => manga.id)
                ForEach(this.emptySlots(row),(slot: number) => { Blank().layoutWeight(1) },(slot: number) => slot.toString())
              }.width('100%').alignItems(VerticalAlign.Top)
            } else {
              Row({ space: 10 }) {
                Text(row.label).fontSize(13).fontColor($r('app.color.theme_697874')).layoutWeight(1)
                if (row.action !== '') {
                  Button(row.action === 'expand' ? '查看全部' : row.action === 'collapse' ? '收起结果' : row.action === 'retry' ? '重试此源' : row.action === 'continue' ? '继续搜索' : '加载更多').fontSize(12)
                    .enabled(row.action === 'expand' || row.action === 'collapse' || !this.vm.busy).onClick(() => this.action(row))
                }
              }.width('100%').padding({ left: 14,right: 14,top: 6,bottom: 12 })
            }
          }.width('100%').onClick(() => { if (row.kind === 'source') { this.vm.toggleFold(row.sourceId); } })
        }, (row: SearchResultRow) => row.key)
      }.layoutWeight(1).width('100%').cachedCount(0)
    }.width('100%').height('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_f8faf5'))
      .onAreaChange((_old: Area,area: Area) => this.vm.setColumns(Math.max(2,Math.min(7,Math.floor((Number(area.width) - 26) / 154)))))
  }
}
