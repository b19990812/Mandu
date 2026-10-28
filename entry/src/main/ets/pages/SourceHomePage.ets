import { common } from '@kit.AbilityKit';
import { SourceHomeVM } from '../vm/SourceHomeVM';
import { SourceFeed, SourceFilter, SourceFilterChoice, SourceBrowseItem } from '../model/SourceTypes';
import { MangaCover } from '../ui/MangaCover';
import { discoveryColumns } from '../source/discovery/DiscoverySupport';

interface SourceHomeParams { sourceId?: string; }

@Entry
@Component
struct SourceHomePage {
  @State private vm: SourceHomeVM = new SourceHomeVM();
  @State private viewportWidth: number = 360;
  @State private filtersExpanded: boolean = false;
  private visible: boolean = true;
  aboutToAppear(): void {
    this.visible = true;
    const params = this.getUIContext().getRouter().getParams() as SourceHomeParams;
    this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext,params?.sourceId || '');
  }
  aboutToDisappear(): void { this.visible = false; this.vm.dispose(); }
  private async open(item: SourceBrowseItem): Promise<void> {
    const id = await this.vm.openItem(item);
    if (id && this.visible) { this.getUIContext().getRouter().pushUrl({ url: 'pages/DetailPage',params: { mangaId: id } }); }
  }
  @Builder
  private filter(group: SourceFilter) {
    Row({ space: 8 }) {
      Text(group.title).fontSize(13).fontColor($r('app.color.theme_697365')).width(32)
      Select(group.choices.map((choice: SourceFilterChoice): SelectOption => ({ value: choice.title })))
        .selected(this.vm.choiceIndex(group)).value(this.vm.choiceTitle(group)).font({ size: 13 }).width(this.viewportWidth < 480 ? 200 : 170)
        .onSelect((index: number) => this.vm.chooseFilter(group,index))
    }.margin({ right: 16,bottom: 8 })
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button('返回').fontSize(12).onClick(() => this.getUIContext().getRouter().back())
        Text(this.vm.name).fontSize(this.viewportWidth < 480 ? 21 : 28).fontWeight(FontWeight.Bold).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button('全局搜索').fontSize(12).enabled(this.vm.sourceId !== '').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' }))
        Button('网站').fontSize(12).enabled(this.vm.sourceId !== '').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SourceWebPage',params: { sourceId: this.vm.sourceId } }))
      }.width('100%')
      if (this.vm.supported) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.vm.feeds,(feed: SourceFeed) => {
              Button(feed.title).fontSize(14).backgroundColor(this.vm.feed === feed.id ? $r('app.color.theme_d9e8d2') : $r('app.color.theme_eff2eb'))
                .fontColor($r('app.color.theme_29452d')).onClick(() => this.vm.chooseFeed(feed.id))
            },(feed: SourceFeed) => feed.id)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      if (this.vm.filters.length > 0) {
        Row({ space: 8 }) {
          Button(this.viewportWidth >= 680 || this.filtersExpanded ? '筛选条件' : '展开筛选').fontSize(12).onClick(() => { this.filtersExpanded = !this.filtersExpanded; })
          Text(this.vm.selected.length ? '已选 ' + this.vm.selected.length.toString() + ' 项' : '全部条件').fontSize(12).fontColor($r('app.color.theme_697365')).layoutWeight(1)
          Button('重置').fontSize(12).enabled(this.vm.selected.length > 0).onClick(() => this.vm.resetFilters())
        }.width('100%')
        if (this.viewportWidth >= 680 || this.filtersExpanded) {
          Flex({ wrap: FlexWrap.Wrap }) { ForEach(this.vm.filters,(group: SourceFilter) => { this.filter(group) },(group: SourceFilter) => group.id) }.width('100%')
        }
      }
      Row({ space: 8 }) {
        Text(this.vm.status).fontSize(12).fontColor($r('app.color.theme_697365')).maxLines(2).layoutWeight(1)
        if (this.vm.busy) { Button('取消').fontSize(12).onClick(() => this.vm.cancel()) }
        else if (this.vm.supported) { Button('刷新').fontSize(12).onClick(() => this.vm.load()) }
      }.width('100%')
      if (this.vm.busy && this.vm.count === 0) { LoadingProgress().width(30).height(30) }
      Grid() {
        LazyForEach(this.vm.data,(item: SourceBrowseItem) => {
          GridItem() {
            Column({ space: 6 }) {
              MangaCover({ sourceId: item.manga.ref.sourceId,mangaId: item.manga.ref.remoteId,address: item.manga.cover || '',title: item.manga.title })
              Text(item.manga.title).fontSize(14).fontWeight(FontWeight.Medium).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              if (item.subtitle) { Text(item.subtitle).fontSize(11).fontColor($r('app.color.theme_697365')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%') }
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.onClick(() => this.open(item)).enabled(!this.vm.busy && !this.vm.opening)
        },(item: SourceBrowseItem) => item.manga.ref.sourceId + ':' + item.manga.ref.remoteId + ':' + (item.manga.cover || ''))
      }.columnsTemplate('1fr '.repeat(discoveryColumns(this.viewportWidth - 40)).trim()).columnsGap(12).rowsGap(16).width('100%').layoutWeight(1).cachedCount(1)
      if (this.vm.supported && this.vm.hasNext) { Button('加载更多').fontSize(14).enabled(!this.vm.busy && !this.vm.opening).onClick(() => this.vm.load(true)) }
    }.width('100%').height('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_f8faf5'))
      .onAreaChange((_old: Area,area: Area) => { const width = Number(area.width); if (width > 0 && Math.abs(width - this.viewportWidth) > 1) { this.viewportWidth = width; } })
  }
}
