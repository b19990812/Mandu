import { common } from '@kit.AbilityKit';
import { ChapterReaderVM } from '../vm/ChapterReaderVM';
import { TrialReaderSessions } from '../reader/TrialReaderSessions';

@Entry
@Component
struct ChapterReaderPage {
  @State private vm: ChapterReaderVM = new ChapterReaderVM();
  private async open(demo: boolean = false,long: boolean = false): Promise<void> {
    await this.vm.open(demo,long); const token = this.vm.handoff();
    if (token) { this.getUIContext().getRouter().pushUrl({ url: 'pages/ReaderPage',params: { trialToken: token } }).catch(() => { TrialReaderSessions.discard(token); this.vm.status = '阅读器打开失败，请重试'; }); }
  }

  aboutToAppear(): void {
    this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }
  aboutToDisappear(): void { this.vm.dispose(); }

  build() {
    Scroll() {
    Column({ space: 12 }) {
      Text('章节试读').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#254E50')
      Text('阅读时轻触画面展开菜单，双击或双指缩放。').fontSize(14).fontColor('#485C5A')
      Select([{ value: '包子漫画' },{ value: 'COPY 漫画' }]).selected(this.vm.sourceId === 'org.hsmihon.copy' ? 1 : 0)
        .value(this.vm.sourceId === 'org.hsmihon.copy' ? 'COPY 漫画' : '包子漫画').enabled(!this.vm.busy)
        .onSelect((index: number) => { if (index < 0 || index > 1) { return; } const id = index === 0 ? 'org.hsmihon.baozi' : 'org.hsmihon.copy'; if (id === this.vm.sourceId) { return; } this.vm.sourceId = id; this.vm.chapterUrl = index === 0 ? 'https://www.twmanga.com/comic/chapter/silingfashiwojishitianzai-mantudezhuyuanzhuheiniaoshe_rjogsq/0_286.html' : 'https://www.mangacopy.com/comic/naoodngxueshenghui/chapter/50fea5ac-c587-11ec-8361-024352452ce0'; })
      TextInput({ text: this.vm.chapterUrl, placeholder: '粘贴所选漫画源的章节第一页网址' })
        .type(InputType.URL).maxLength(2048).enabled(!this.vm.busy)
        .onChange((value: string) => { this.vm.chapterUrl = value; })
      Row({ space: 12 }) {
        Button('打开章节').backgroundColor('#254E50').enabled(!this.vm.busy).onClick(() => this.open())
        Button('取消加载').enabled(this.vm.busy).onClick(() => this.vm.cancel())
      }
      Button('读取内置示例（合成图）').enabled(!this.vm.busy).onClick(() => this.open(true))
      Button('读取长图示例（合成图）').enabled(!this.vm.busy).onClick(() => this.open(true,true))
      Text(this.vm.status).fontSize(14).fontColor('#485C5A').width('100%')
      if (this.vm.title !== '') { Text(this.vm.title).fontSize(16).maxLines(2).width('100%') }
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(20)
    }.width('100%').height('100%').backgroundColor('#F7F4ED')
  }
}
