import { common } from '@kit.AbilityKit';
import { MangaRecord, CategoryRecord } from '../model/LibraryTypes';
import { LibraryVM } from '../vm/LibraryVM';
import { MangaCover } from './MangaCover';

@Component
export struct LibraryPanel {
  @State private vm: LibraryVM = new LibraryVM();
  @State private manage: boolean = false;
  @State private columns: number = 3;
  @State private selection: boolean = false;
  @Prop @Watch('refresh') revision: number = 0;
  onBrowse: () => void = () => {};
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.vm.dispose(); }
  private refresh(): void { this.vm.load(); }
  build() {
    Column({ space: 12 }) {
      Row() {
        Text('书架').fontSize(28).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('分类').type(ButtonType.Normal).fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).onClick(() => { this.manage = !this.manage; })
        Button('全局搜索').type(ButtonType.Normal).fontSize(14).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' }))
      }.width('100%')
      TextInput({ text: this.vm.query,placeholder: '搜索书架标题 / 作者' }).maxLength(128).onChange((value: string) => this.vm.search(value))
      Row({ space: 8 }) {
        Select([{ value: '最近更新' },{ value: '标题' },{ value: '未读数量' },{ value: '最近阅读' }]).selected(['updated','title','unread','read'].indexOf(this.vm.order)).value(['最近更新','标题','未读数量','最近阅读'][['updated','title','unread','read'].indexOf(this.vm.order)]).onSelect((index: number) => { if (index >= 0 && index < 4) { this.vm.order = ['updated','title','unread','read'][index]; this.vm.apply(); } })
        Select([{ value: '全部' },{ value: '有未读' },{ value: '有离线' }]).selected(['all','unread','offline'].indexOf(this.vm.filter)).value(['全部','有未读','有离线'][['all','unread','offline'].indexOf(this.vm.filter)]).onSelect((index: number) => { if (index >= 0 && index < 3) { this.vm.filter = ['all','unread','offline'][index]; this.vm.apply(); } })
        Button(this.selection ? '取消选择' : '选择').fontSize(12).onClick(() => { this.selection = !this.selection; if (!this.selection) { this.vm.selected = []; } })
      }.width('100%')
      Scroll() {
        Row({ space: 8 }) {
          Button('全部').fontSize(13).backgroundColor(this.vm.selectedCategory === '' ? $r('app.color.theme_d9e8d2') : $r('app.color.theme_eff2eb')).fontColor($r('app.color.theme_29452d')).onClick(() => this.vm.select(''))
          ForEach(this.vm.categories,(category: CategoryRecord) => { Button(category.name).fontSize(13).backgroundColor(this.vm.selectedCategory === category.id ? $r('app.color.theme_d9e8d2') : $r('app.color.theme_eff2eb')).fontColor($r('app.color.theme_29452d')).onClick(() => this.vm.select(category.id)) },(category: CategoryRecord) => category.id)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      if (this.manage) {
        TextInput({ text: this.vm.categoryName,placeholder: '分类名称' }).maxLength(32).onChange((value: string) => { this.vm.categoryName = value; })
        Row({ space: 8 }) {
          Button('新增分类').fontSize(13).enabled(!this.vm.busy).onClick(() => this.vm.categoryAction('add'))
          Button('重命名').fontSize(13).enabled(!this.vm.busy && this.vm.selectedCategory !== '').onClick(() => this.vm.categoryAction('rename'))
          Button('删除分类').fontSize(13).enabled(!this.vm.busy && this.vm.selectedCategory !== '').onClick(() => this.vm.categoryAction('delete'))
        }
      }
      if (this.selection) {
        Row({ space: 8 }) {
          Button('全选 / 清空').fontSize(12).onClick(() => this.vm.selectAll())
          Text('已选 ' + this.vm.selected.length.toString()).fontSize(12)
          Button('移出书架').fontSize(12).enabled(!this.vm.busy && this.vm.selected.length > 0).onClick(() => this.vm.batch('remove'))
        }
        if (this.vm.categories.length > 0) {
          Row({ space: 8 }) {
            Select(this.vm.categories.map((category: CategoryRecord): SelectOption => ({ value: category.name }))).value(this.vm.categories.find((category: CategoryRecord) => category.id === this.vm.batchCategory)?.name || '选择目标分类').onSelect((index: number) => { if (index >= 0 && index < this.vm.categories.length) { this.vm.batchCategory = this.vm.categories[index].id; } })
            Button('加入分类').fontSize(12).enabled(!this.vm.busy && this.vm.batchCategory !== '' && this.vm.selected.length > 0).onClick(() => this.vm.batch('assign'))
            Button('移出分类').fontSize(12).enabled(!this.vm.busy && this.vm.batchCategory !== '' && this.vm.selected.length > 0).onClick(() => this.vm.batch('unassign'))
          }
        }
      }
      Text(this.vm.status).fontSize(12).fontColor($r('app.color.theme_697365')).width('100%')
      Grid() {
        LazyForEach(this.vm.data,(manga: MangaRecord) => {
          GridItem() {
            Column({ space: 8 }) {
              MangaCover({ sourceId: manga.detail.ref.sourceId,mangaId: manga.detail.ref.remoteId,address: manga.detail.cover || '',title: manga.detail.title })
              Text(manga.detail.title).fontSize(14).fontWeight(FontWeight.Medium).maxLines(2).width('100%')
              Text((this.selection && this.vm.selected.indexOf(manga.id) >= 0 ? '✓ ' : '') + '未读 ' + (manga.unreadCount || 0).toString() + ' · 离线 ' + (manga.offlineCount || 0).toString()).fontSize(11).fontColor($r('app.color.theme_697365')).maxLines(1)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.onClick(() => { if (this.selection) { this.vm.toggle(manga.id); } else { this.getUIContext().getRouter().pushUrl({ url: 'pages/DetailPage',params: { mangaId: manga.id } }); } })
            .gesture(LongPressGesture().onAction(() => { this.selection = true; this.vm.toggle(manga.id); }))
        },(manga: MangaRecord) => manga.id)
      }.columnsTemplate('1fr '.repeat(this.columns).trim()).columnsGap(12).rowsGap(18).layoutWeight(1).width('100%').cachedCount(1)
        .onAreaChange((_old: Area,area: Area) => { this.columns = Math.max(2,Math.min(8,Math.floor(Number(area.width) / 132))); })
      if (this.vm.count === 0) { Button('浏览漫画').backgroundColor($r('app.color.theme_466948')).onClick(() => this.onBrowse()) }
    }.width('100%').height('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.theme_f8faf5'))
  }
}

