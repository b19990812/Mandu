import { common } from '@kit.AbilityKit';
import { PREFETCH_PAGE_CHOICES } from '../model/ReaderPreferences';
import { SettingsVM } from '../vm/SettingsVM';
import { READER_MODES } from '../model/ReaderDisplay';

@Entry
@Component
struct SettingsPage {
  @State private vm: SettingsVM = new SettingsVM();
  aboutToAppear(): void { this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext); }
  aboutToDisappear(): void { this.vm.dispose(); }
  build() {
    Scroll() {
      Column({ space: 18 }) {
        Text('设置 · ' + this.vm.version).fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.theme_254e50'))
        Text(this.vm.status).fontSize(14)
        Text('应用主题').fontSize(18)
        Select([{ value: '跟随系统' },{ value: '浅色' },{ value: '深色' }]).selected(['system','light','dark'].indexOf(this.vm.theme)).value(['跟随系统','浅色','深色'][['system','light','dark'].indexOf(this.vm.theme)]).onSelect((index: number) => this.vm.setTheme(['system','light','dark'][index]))
        Text('默认阅读方式').fontSize(18)
        Select([{ value: '水平滑动' },{ value: '纵向单页' },{ value: '无缝条漫' },{ value: '间隔连续' },{ value: '双页仿真卷页' },{ value: '点击单页' },{ value: '单页仿真卷页' }]).selected(READER_MODES.indexOf(this.vm.mode)).value(['水平滑动','纵向单页','无缝条漫','间隔连续','双页仿真卷页','点击单页','单页仿真卷页'][READER_MODES.indexOf(this.vm.mode)]).onSelect((index: number) => { if (index >= 0 && index < READER_MODES.length) { this.vm.mode = READER_MODES[index]; } })
        Text('页式阅读方向').fontSize(18)
        Select([{ value: '从左到右' },{ value: '从右到左' }]).selected(this.vm.direction === 'ltr' ? 0 : 1).value(this.vm.direction === 'ltr' ? '从左到右' : '从右到左').onSelect((index: number) => { if (index === 0 || index === 1) { this.vm.direction = index === 0 ? 'ltr' : 'rtl'; } })
        Text('阅读背景与适配（条漫固定适合宽度）').fontSize(18)
        Select([{ value: '深色' },{ value: '灰色' },{ value: '浅色' }]).selected(['dark','gray','light'].indexOf(this.vm.background)).value(['深色','灰色','浅色'][['dark','gray','light'].indexOf(this.vm.background)]).onSelect((i: number) => { if (i >= 0 && i < 3) { this.vm.background = ['dark','gray','light'][i]; } })
        Select([{ value: '自动适配' },{ value: '适合宽度' },{ value: '适合高度' }]).selected(['auto','width','height'].indexOf(this.vm.scale)).value(['自动适配','适合宽度','适合高度'][['auto','width','height'].indexOf(this.vm.scale)]).onSelect((i: number) => { if (i >= 0 && i < 3) { this.vm.scale = ['auto','width','height'][i]; } })
        Select([{ value: '左右侧点击翻页' },{ value: '三等分点击翻页' },{ value: '点击仅菜单' }]).selected(['sides','thirds','menu'].indexOf(this.vm.tapZones)).value(['左右侧点击翻页','三等分点击翻页','点击仅菜单'][['sides','thirds','menu'].indexOf(this.vm.tapZones)]).onSelect((i: number) => { if (i >= 0 && i < 3) { this.vm.tapZones = ['sides','thirds','menu'][i]; } })
        Row({ space: 12 }) { Text('反转左右点击翻页').layoutWeight(1); Toggle({ type: ToggleType.Switch,isOn: this.vm.invertTap }).onChange((value: boolean) => { this.vm.invertTap = value; }) }.width('100%')
        Row({ space: 12 }) { Text('隐身阅读：不写入进度与历史').layoutWeight(1); Toggle({ type: ToggleType.Switch,isOn: this.vm.incognito }).onChange((value: boolean) => { this.vm.incognito = value; }) }.width('100%')
        Row({ space: 12 }) { Text('预加载相邻图像').layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.vm.prefetch }).onChange((value: boolean) => { this.vm.prefetch = value; }) }.width('100%')
        Row({ space: 12 }) { Text('仅 Wi-Fi 预加载').layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.vm.prefetchWifi }).onChange((value: boolean) => { this.vm.prefetchWifi = value; }) }.width('100%')
        Row({ space: 12 }) { Text('章末继续翻页时自动进入下一章').layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.vm.autoNext }).onChange((value: boolean) => { this.vm.autoNext = value; }) }.width('100%')
        Row({ space: 12 }) { Text('提前准备下一章首图').layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.vm.preloadNext }).onChange((value: boolean) => { this.vm.preloadNext = value; }) }.width('100%')
        Row({ space: 12 }) { Text('换章时跳过已读章节').layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.vm.skipRead }).onChange((value: boolean) => { this.vm.skipRead = value; }) }.width('100%')
        Text('提前缓存后续图片（前一张同时保留）').fontSize(18)
        Select(PREFETCH_PAGE_CHOICES.map((pages: number): SelectOption => ({ value: pages.toString() + ' 张' }))).selected(PREFETCH_PAGE_CHOICES.indexOf(this.vm.prefetchPages)).value(this.vm.prefetchPages.toString() + ' 张').enabled(this.vm.prefetch).onSelect((index: number) => { if (index >= 0 && index < PREFETCH_PAGE_CHOICES.length) { this.vm.prefetchPages = PREFETCH_PAGE_CHOICES[index]; } })
        Row({ space: 12 }) { Text('下载仅使用 Wi-Fi').layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.vm.wifiOnly }).onChange((value: boolean) => { this.vm.wifiOnly = value; }) }.width('100%')
        Text('浏览缓存上限').fontSize(18)
        Select([{ value: '128 MiB' },{ value: '256 MiB' },{ value: '512 MiB' },{ value: '1024 MiB' }]).selected([128,256,512,1024].indexOf(this.vm.cacheMiB)).value(this.vm.cacheMiB.toString() + ' MiB').onSelect((index: number) => { if (index >= 0 && index < 4) { this.vm.cacheMiB = [128,256,512,1024][index]; } })
        Button('保存设置').enabled(!this.vm.busy).onClick(() => this.vm.save())
        Text('可回收浏览缓存：' + (this.vm.reclaimable / 1048576).toFixed(2) + ' MiB').fontSize(14)
        Button('清理浏览缓存').enabled(!this.vm.busy).onClick(() => this.vm.clean())
        Text('离线章节保存在下载目录；请在下载管理中单独删除。').fontSize(13)
        Button('Tracking 账号与同步').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/TrackingPage' }))
        Text('备份与恢复').fontSize(18)
        Text('备份书架、目录、分类、逐章进度与阅读设置。漫画图片、源规则和账号需另行保存。合并恢复保留较新进度和已有设置。').fontSize(13)
        Button('导出备份').enabled(!this.vm.busy).onClick(() => this.vm.exportBackup())
        Button('选择备份并预览').enabled(!this.vm.busy).onClick(() => this.vm.previewBackup())
        if (this.vm.backupPreview) { Text(this.vm.backupPreview).fontSize(13) }
        Button('确认合并恢复').enabled(!this.vm.busy && this.vm.backupReady).onClick(() => this.vm.restoreBackup())
        Button('导出脱敏诊断').enabled(!this.vm.busy).onClick(() => this.vm.exportDiagnostic())
        Button('第三方许可证').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/LicensesPage' }))
      }.width('100%').padding(24).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.theme_f7f4ed'))
  }
}
