import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { SourceSiteView } from '../model/SourceSiteTypes';
import { isTabletLandscape } from '../ui/TabletLayout';
import { SourceSitesVM } from '../vm/SourceSitesVM';
import { COPY_API_SITES, COPY_DEFAULT_API } from '../source/CopyAccess';

@Entry
@Component
struct SourcesPage {
  @State private vm: SourceSitesVM = new SourceSitesVM();
  @State private siteColumns: number = 0;
  private readonly scroller: Scroller = new Scroller();
  private revealEditor: boolean = false;

  aboutToAppear(): void {
    this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  aboutToDisappear(): void { this.vm.dispose(); }

  @Styles
  private actionSize() {
    .constraintSize({ minHeight: this.siteColumns > 0 ? 44 : undefined })
  }

  @Builder
  private openActions(site: SourceSiteView) {
    Button('漫画源首页').fontSize(14).actionSize().enabled(!this.vm.busy && this.vm.editingSourceId === '')
      .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SourceHomePage',params: { sourceId: site.sourceId } }))
    Button('打开网站首页').fontSize(14).actionSize().enabled(!this.vm.busy && this.vm.editingSourceId === '')
      .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SourceWebPage',params: { sourceId: site.sourceId } }))
  }

  @Builder
  private addressActions(site: SourceSiteView) {
    Button('修改网址').fontSize(14).actionSize()
      .enabled(!this.vm.busy && this.vm.editingSourceId === '')
      .onClick(() => {
        this.revealEditor = this.siteColumns > 0;
        this.vm.edit(site);
      })
    Button('恢复默认').fontSize(14).actionSize()
      .enabled(!this.vm.busy && this.vm.editingSourceId === '' && (site.baseUrl !== site.defaultBaseUrl || site.sourceId === 'org.hsmihon.copy' && (site.copyProtocol !== 'api' || site.copyApiBaseUrl !== COPY_DEFAULT_API)))
      .onClick(() => this.vm.reset(site))
  }

  @Builder
  private rollbackAction(site: SourceSiteView) {
    if (site.previousBaseUrl !== '') {
      Button('切回上次网址').fontSize(14).actionSize()
        .enabled(!this.vm.busy && this.vm.editingSourceId === '')
        .onClick(() => this.vm.rollback(site))
    }
  }

  @Builder
  private addressLabel(site: SourceSiteView) {
    Text(site.baseUrl === site.defaultBaseUrl ? '默认网址' : '自定义网址')
      .fontSize(12).fontColor($r('app.color.theme_697874'))
  }

  @Builder
  private siteCard(site: SourceSiteView) {
    Column({ space: this.siteColumns > 0 ? 5 : 12 }) {
      if (this.siteColumns > 0) {
        Row({ space: 8 }) {
          Text(site.name).fontSize(18).fontWeight(FontWeight.Medium)
            .layoutWeight(1).wordBreak(WordBreak.BREAK_WORD)
          this.addressLabel(site)
        }.width('100%')
      } else {
        Text(site.name).fontSize(20).fontWeight(FontWeight.Medium)
      }
      Text(site.baseUrl).fontSize(this.siteColumns > 0 ? 14 : 15).width('100%').fontColor($r('app.color.theme_254e50'))
        .wordBreak(this.siteColumns > 0 ? WordBreak.BREAK_WORD : WordBreak.NORMAL)
      if (this.siteColumns === 0) { this.addressLabel(site) }
      if (site.sourceId === 'org.hsmihon.copy') {
        Text(site.copyProtocol === 'web' ? '网页接入' : 'API 接入（匿名）').fontSize(14)
        if (site.copyProtocol !== 'web') {
          Text(site.copyApiBaseUrl || COPY_DEFAULT_API).fontSize(13)
            .wordBreak(this.siteColumns > 0 ? WordBreak.BREAK_WORD : WordBreak.NORMAL)
        }
      }
      if (site.sourceId === 'org.hsmihon.manhuagui') {
        Text('网页接入（HTML 解析）').fontSize(14)
      }
      if (this.siteColumns > 0) {
        Flex({
          wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(4) }
        }) {
          this.openActions(site)
          this.addressActions(site)
          this.rollbackAction(site)
        }.width('100%')
      } else {
        this.openActions(site)
        Row({ space: 12 }) { this.addressActions(site) }
        this.rollbackAction(site)
      }
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding({ left: this.siteColumns > 0 ? 12 : 16, right: this.siteColumns > 0 ? 12 : 16,
      top: this.siteColumns > 0 ? 8 : 16, bottom: this.siteColumns > 0 ? 8 : 16 })
    .backgroundColor($r('app.color.theme_ffffff')).borderRadius(12)
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: this.siteColumns > 0 ? 8 : 20 }) {
        Text('漫画源网站').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_254e50'))
        Text('网站迁移后可更换根网址。页面或接口结构变化时，仍需更新对应源规则。')
          .fontSize(14).fontColor($r('app.color.theme_485c5a'))
        if (this.siteColumns > 0) {
          GridRow({ columns: this.siteColumns, gutter: 8 }) {
            ForEach(this.vm.sites, (site: SourceSiteView) => {
              GridCol({ span: 1 }) { this.siteCard(site) }
            }, (site: SourceSiteView) => site.sourceId)
          }.width('100%')
        } else {
          ForEach(this.vm.sites, (site: SourceSiteView) => {
            this.siteCard(site)
          }, (site: SourceSiteView) => site.sourceId)
        }
        if (this.vm.editingSourceId !== '') {
          Column({ space: 12 }) {
            Text('修改：' + this.vm.editingName).fontSize(20).fontWeight(FontWeight.Medium)
            if (this.vm.editingSourceId === 'org.hsmihon.copy') {
              Text('接入方式').fontSize(14)
              Select([{ value: 'API（匿名浏览与阅读）' },{ value: '网页' }])
                .selected(this.vm.copyMode === 'api' ? 0 : 1).enabled(!this.vm.busy)
                .onSelect((index: number) => { this.vm.copyMode = index === 0 ? 'api' : 'web'; })
              if (this.vm.copyMode === 'api') {
                Text('API 线路（仅填写 HTTPS 根网址）').fontSize(14)
                Select(COPY_API_SITES.map((address: string): SelectOption => { return { value: address }; }))
                  .value('选择内置线路').enabled(!this.vm.busy)
                  .onSelect((index: number) => { this.vm.copyApiDraft = COPY_API_SITES[index]; })
                TextInput({ text: this.vm.copyApiDraft,placeholder: COPY_DEFAULT_API })
                  .type(InputType.URL).maxLength(2048).enabled(!this.vm.busy)
                  .onChange((value: string) => { this.vm.copyApiDraft = value; })
                Text('线路需手动选择；需要登录的内容会提示。').fontSize(12)
              }
              Text('网站根网址（用于打开网页）').fontSize(14)
            }
            TextInput({ text: this.vm.draft, placeholder: 'https://新域名/' })
              .type(InputType.URL).maxLength(2048).enabled(!this.vm.busy)
              .onChange((value: string) => { this.vm.draft = value; })
            Row({ space: 12 }) {
              Button('保存网址').backgroundColor($r('app.color.theme_254e50')).enabled(!this.vm.busy)
                .onClick(() => this.vm.save())
              Button('取消').enabled(!this.vm.busy).onClick(() => this.vm.cancelEdit())
            }
          }
          .alignItems(HorizontalAlign.Start).width('100%').padding(16)
          .backgroundColor($r('app.color.theme_e6eeea')).borderRadius(12)
          .onAreaChange(() => {
            if (this.revealEditor) {
              this.revealEditor = false;
              this.scroller.scrollEdge(Edge.Bottom);
            }
          })
        }
        if (this.vm.status !== '') {
          Text(this.vm.status).fontSize(14).fontColor($r('app.color.theme_485c5a')).width('100%')
        }
        Button('重新读取').enabled(!this.vm.busy && this.vm.editingSourceId === '')
          .onClick(() => this.vm.reload())
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: this.siteColumns > 0 ? 10 : 24, bottom: this.siteColumns > 0 ? 10 : 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').backgroundColor($r('app.color.theme_f7f4ed'))
    .onAreaChange((_old: Area, area: Area) => {
      this.siteColumns = isTabletLandscape(area) ? (Number(area.width) >= 1120 ? 2 : 1) : 0;
    })
  }
}
