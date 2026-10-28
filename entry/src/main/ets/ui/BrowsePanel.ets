import { common } from '@kit.AbilityKit';
import { AppContainer } from '../app/AppContainer';
import { ManagedSource } from '../source/SourceImportService';
import { viewError } from '../vm/ViewOperation';
@Component
export struct BrowsePanel {
  @State private sources: ManagedSource[] = [];
  @State private status: string = '';
  @Prop @Watch('load') revision: number = 0;
  private active: boolean = false;
  private async openSource(item: ManagedSource): Promise<void> {
    if (!item.state.enabled) { this.status = '此源已停用，请先启用'; return; }
    try {
      await this.getUIContext().getRouter().pushUrl({ url: item.rule.capabilities.indexOf('discover') >= 0 ? 'pages/SourceHomePage' : 'pages/SearchPage',params: { sourceId: item.state.id } });
    } catch (error) { if (this.active) { this.status = '打开漫画源失败：' + viewError(error as Error); } }
  }
  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }
  private async load(): Promise<void> {
    try { const sources = await new AppContainer(this.getUIContext().getHostContext() as common.UIAbilityContext).listSources(); if (this.active) { this.sources = sources; } }
    catch (error) { if (this.active) { this.status = viewError(error as Error); } }
  }
  private async toggle(item: ManagedSource): Promise<void> {
    try {
      const app = new AppContainer(this.getUIContext().getHostContext() as common.UIAbilityContext);
      if (app.nativeSources.owns(item.state.id)) { await app.nativeSources.setEnabled(item.state.id,!item.state.enabled,item.state.revision); }
      else { await app.imports.setEnabled(item.state.id,!item.state.enabled,item.state.revision); }
      await this.load();
    } catch (error) { if (this.active) { this.status = viewError(error as Error); } }
  }
  build() {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        Text('浏览').fontSize(28).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('全局搜索').fontSize(13).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' }))
        Button('源规则').fontSize(13).backgroundColor($r('app.color.theme_466948')).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/RuleManagerPage' }))
      }.width('100%')
      Row({ space: 12 }) { Text('漫画源').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1); Button('扩展仓库').fontSize(13).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/ExtensionManagerPage' })) }.width('100%')
      if (this.status) { Text(this.status).fontSize(13) }
      List({ space: 10 }) {
        ForEach(this.sources,(item: ManagedSource) => {
          ListItem() {
            Row({ space: 14 }) {
              Text(item.rule.name.substring(0,1)).width(48).height(48).textAlign(TextAlign.Center).fontSize(22).backgroundColor($r('app.color.theme_d9e8d2')).borderRadius(14).onClick(() => this.openSource(item))
              Column({ space: 5 }) { Text(item.rule.name).fontSize(18); Text('v' + item.rule.sourceVersion.toString() + ' · ' + (item.rule.capabilities.indexOf('discover') >= 0 ? '点击进入首页' : item.rule.definition.format === 'native' ? '内置适配器' : item.rule.definition.format === 'html' ? 'HTML' : 'JSON') + (item.state.enabled ? '' : ' · 已禁用')).fontSize(12).fontColor($r('app.color.theme_697365')) }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                .onClick(() => this.openSource(item))
              Button('网站').fontSize(12).enabled(item.state.enabled).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SourceWebPage',params: { sourceId: item.state.id } }))
              Button(item.state.enabled ? '停用' : '启用').fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.theme_466948')).onClick(() => this.toggle(item))
            }.width('100%').padding(14).backgroundColor($r('app.color.theme_edf2e8')).borderRadius(14)
          }
        },(item: ManagedSource) => item.state.id + ':' + item.state.revision.toString())
      }.width('100%').layoutWeight(1)
      if (this.sources.length === 0) { Text('尚无可浏览的源，请导入并启用源规则。').fontSize(14) }
      Row({ space: 10 }) {
        Button('漫画源网站').fontSize(13).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/SourcesPage' }))
        Button('章节试读').fontSize(13).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/ChapterReaderPage' }))
      }
    }.width('100%').height('100%').padding(20).backgroundColor($r('app.color.theme_f8faf5'))
  }
}
