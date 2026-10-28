import { common } from '@kit.AbilityKit';
import { SearchVM } from '../vm/SearchVM';
import { MigrationVM } from '../vm/MigrationVM';
import { MangaRecord } from '../model/LibraryTypes';
interface MigrationParams { mangaId: string; title: string; }
@Entry
@Component
struct MigrationPage {
  @State private search: SearchVM = new SearchVM();
  @State private vm: MigrationVM = new MigrationVM();
  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const params = this.getUIContext().getRouter().getParams() as MigrationParams;
    this.vm.initialize(context,params.mangaId); this.search.query = params.title || ''; this.search.initialize(context,'*');
  }
  aboutToDisappear(): void { this.search.dispose(); this.vm.dispose(); }
  build() {
    Column({ space: 12 }) {
      Text('跨源迁移').fontSize(26)
      TextInput({ text: this.search.query,placeholder: '目标作品名称' }).onChange((value: string) => { this.search.query = value; })
      Button('搜索其他来源').enabled(!this.search.busy && !this.vm.busy).onClick(() => this.search.search())
      Text(this.search.status).fontSize(12)
      Text(this.vm.status).fontSize(14)
      if (this.vm.ready) {
        Scroll() { Text(this.vm.summary).width('100%') }.height('30%')
        Button('确认复制到目标作品').enabled(!this.vm.busy).onClick(() => this.vm.apply())
      }
      List({ space: 8 }) {
        LazyForEach(this.search.data,(item: MangaRecord) => {
          ListItem() { Button(item.detail.title + ' · ' + item.detail.ref.sourceId).enabled(!this.vm.busy).onClick(() => this.vm.select(item.id)) }
        },(item: MangaRecord) => item.id)
        if (this.search.hasNext) { ListItem() { Button('更多搜索结果').enabled(!this.search.busy).onClick(() => this.search.search(true)) } }
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(20).backgroundColor($r('app.color.theme_f7f4ed'))
  }
}
