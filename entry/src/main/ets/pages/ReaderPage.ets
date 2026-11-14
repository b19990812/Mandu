import { ReaderEffects } from '../reader/ReaderEffects';
import { HorizontalPager } from '../ui/HorizontalPager';
import { common } from '@kit.AbilityKit';
import { ReaderVM } from '../vm/ReaderVM';
import { RetainedCanvas as ReadingCanvas } from '../ui/RetainedCanvas';
import { WebtoonViewer } from '../ui/WebtoonViewer';
import { ReaderWindow } from '../reader/ReaderWindow';
import { ReaderLifecycle } from '../reader/ReaderLifecycle';
import { readerBackground, READER_MODES } from '../model/ReaderDisplay';
import { EhentaiBrowserHost } from '../ui/EhentaiBrowserHost';
import { EHENTAI_ID } from '../network/EhentaiAccess';

interface ReaderParams { chapterId?: string; offlineOnly?: boolean; trialToken?: string; }

@Entry
@Component
struct ReaderPage {
  @State private effects: ReaderEffects = new ReaderEffects();
  @State private vm: ReaderVM = new ReaderVM();
  @State private menuVisible: boolean = false;
  @State private optionsVisible: boolean = false;
  @State private zoom: number = 1;
  @State private viewportHeight: number = 720;
  private pageVisible: boolean = true;
  private lifecycle?: () => void;
  private scroller: Scroller = new Scroller();
  aboutToAppear(): void {
    this.effects.read(this.getUIContext().getHostContext() as common.UIAbilityContext).then(() => { if (this.pageVisible) { this.applyEffects(); } });
    const params = this.getUIContext().getRouter().getParams() as ReaderParams;
    this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext,params.chapterId || '',params.offlineOnly === true,params.trialToken || '');
    this.lifecycle = ReaderLifecycle.subscribe((foreground: boolean) => { this.applyEffects(foreground && this.pageVisible); ReaderWindow.immersive(this.getUIContext().getHostContext() as common.UIAbilityContext,foreground && this.pageVisible); });
  }
  aboutToDisappear(): void { this.pageVisible = false; this.applyEffects(false); this.lifecycle?.(); this.vm.dispose(); }
  onPageShow(): void { this.pageVisible = true; this.applyEffects(); this.vm.setPageVisible(true); ReaderWindow.immersive(this.getUIContext().getHostContext() as common.UIAbilityContext,ReaderLifecycle.isForeground); }
  onPageHide(): void { this.pageVisible = false; this.applyEffects(false); this.vm.setPageVisible(false); ReaderWindow.immersive(this.getUIContext().getHostContext() as common.UIAbilityContext,false); }
  onBackPress(): boolean { if (this.optionsVisible) { this.optionsVisible = false; return true; } if (this.menuVisible) { this.menuVisible = false; return true; } return false; }
  private applyEffects(active: boolean = true): void { ReaderWindow.effects(this.getUIContext().getHostContext() as common.UIAbilityContext,active,this.effects.brightness,this.effects.orientation); }
  private saveEffects(): void { this.effects.save(this.getUIContext().getHostContext() as common.UIAbilityContext).catch(() => {}); this.applyEffects(); }
  private turn(direction: number): void { this.tapTurn(direction * (this.vm.mode !== 'vertical' && this.vm.direction === 'rtl' ? -1 : 1)); }
  private display(key: string,value: string): void { this.vm.display({ background: key === 'background' ? value : this.vm.background,scale: key === 'scale' ? value : this.vm.scale,tapZones: key === 'tap' ? value : this.vm.tapZones,invertTap: key === 'invert' ? value === 'true' : this.vm.invertTap }); }
  private tapTurn(direction: number): void { if (this.vm.busy) { return; } this.zoom = 1; this.vm.turnPage(direction); }
  private async chapter(id: string): Promise<void> { this.zoom = 1; await this.vm.changeChapter(id); }
  private website(): void {
    if (!this.vm.sourceId || this.vm.sourceId === 'org.hsmihon.local') { return; }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SourceWebPage',params: { sourceId: this.vm.sourceId } });
  }
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.vm.sourceId === EHENTAI_ID) { EhentaiBrowserHost() }
      Column() {
      if (this.vm.active && this.vm.usesPager() && this.vm.total > 0) {
        HorizontalPager({ vm: this.vm,epoch: this.vm.readerEpoch,requestRevision: this.vm.pagerRevision,zoom: this.zoom,readingDirection: this.vm.direction,gestures: this.vm.mode !== 'tap',
          visualKey: this.vm.mode + ':' + this.vm.background + ':' + this.vm.scale + ':' + this.vm.direction,
          onZoom: (zoom: number) => { this.zoom = zoom; },onMenu: () => { this.menuVisible = !this.menuVisible; } })
      } else if (this.vm.active && this.vm.isStrip() && this.vm.total > 0) {
        WebtoonViewer({ vm: this.vm,revision: this.vm.stripRevision,controller: this.scroller,zoom: this.zoom,
          onZoom: (zoom: number) => { this.zoom = zoom; },onMenu: () => { this.menuVisible = !this.menuVisible; } })
      } else if (this.vm.active && this.vm.asset) {
        ReadingCanvas({ asset: this.vm.asset,traceKey: this.vm.tracePage(this.vm.displayIndex,'visible').operationId,zoom: this.zoom,ratio: this.vm.ratio,controller: this.scroller,
          turnDirection: this.vm.turnDirection,backdrop: this.vm.background,scaleMode: this.vm.scale,vertical: this.vm.mode === 'vertical',tapZones: this.vm.tapZones,invertTap: this.vm.invertTap,
          onPosition: (ratio: number) => this.vm.scroll(ratio),onEnd: () => this.vm.reachedEnd(),onZoom: (zoom: number) => { this.zoom = zoom; },
          onTurn: (direction: number) => this.turn(direction),onTapTurn: (direction: number) => this.tapTurn(direction),onMenu: () => { this.menuVisible = !this.menuVisible; } })
      } else {
        Column({ space: 20 }) {
          Text(this.vm.status).fontSize(16).fontColor('#E1E9E4').padding(24)
          Button('打开阅读菜单').onClick(() => { this.menuVisible = true; })
          if (!this.vm.busy && !this.vm.pagerMoving) { Button('重新打开章节').onClick(() => this.vm.open()) }
          Button('返回').onClick(() => this.getUIContext().getRouter().back())
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).onClick(() => { this.menuVisible = true; })
      }
      }.width('100%').height('100%').grayscale(this.effects.filter === 'gray' ? 1 : 0).invert(this.effects.filter === 'invert' ? 1 : 0).sepia(this.effects.filter === 'sepia' ? 1 : 0)
      if (this.vm.busy) { LoadingProgress().width(36).height(36).align(Alignment.Center).color('#E1EEEA').hitTestBehavior(HitTestMode.None) }
      if (!this.menuVisible) {
        Text(this.vm.total > 0 ? (this.vm.incognito ? '隐身 · ' : '') + (this.vm.index + 1).toString() + ' / ' + this.vm.total.toString() + ' · 菜单' : '阅读菜单').fontSize(12).fontColor('#F4F7F4')
          .padding({ left: 10,right: 10,top: 5,bottom: 5 }).backgroundColor('#77101515').borderRadius(12).margin({ bottom: 12 }).accessibilityText('阅读菜单').onClick(() => { this.menuVisible = true; })
      }
      if (this.menuVisible) {
        Column() {
          Row({ space: 10 }) {
            Button('返回').fontSize(13).height(38).onClick(() => this.getUIContext().getRouter().back())
            Text(this.vm.title).fontSize(16).fontColor('#FFFFFF').maxLines(2).layoutWeight(1)
            Button('阅读设置').fontSize(13).height(38).onClick(() => { this.optionsVisible = !this.optionsVisible; })
          }.width('100%').padding(12).backgroundColor('#EC1D2523')
          Blank().onClick(() => { this.menuVisible = false; this.optionsVisible = false; })
          Column({ space: 8 }) {
            Text(this.vm.status).fontSize(12).fontColor('#CBD8D4').maxLines(2).width('100%')
            if (this.vm.busy) { Button('取消加载').fontSize(12).height(36).onClick(() => this.vm.cancel()) }
            if (this.vm.sourceId && this.vm.sourceId !== 'org.hsmihon.local') { Button('网站首页').fontSize(12).height(36).onClick(() => this.website()) }
            Row({ space: 8 }) {
              Button(this.vm.mode === 'spread' ? '上一组' : '上一图').fontSize(13).height(38).enabled(!this.vm.busy && this.vm.displayIndex > 0).onClick(() => this.tapTurn(-1))
              Slider({ value: this.vm.index + 1,min: 1,max: Math.max(2,this.vm.total),step: 1 }).layoutWeight(1).enabled(this.vm.total > 1 && !this.vm.busy && !this.vm.pagerMoving)
                .onChange((value: number,mode: SliderChangeMode) => { if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.zoom = 1; this.vm.jump(Math.min(this.vm.total - 1,Math.round(value) - 1)); } })
              Text(this.vm.mode === 'spread' ? (this.vm.displayIndex + 1).toString() + '–' + Math.min(this.vm.total,this.vm.displayIndex + 2).toString() + ' / ' + this.vm.total.toString() : (this.vm.index + 1).toString() + ' / ' + this.vm.total.toString()).fontColor('#FFFFFF').fontSize(13)
              Button(this.vm.mode === 'spread' ? '下一组' : '下一图').fontSize(13).height(38).enabled(!this.vm.busy && (this.vm.displayIndex + (this.vm.mode === 'spread' ? 2 : 1) < this.vm.total || this.vm.autoNext && this.vm.nextId !== '')).onClick(() => this.tapTurn(1))
            }.width('100%')
            Row({ space: 8 }) {
              if (!this.vm.trialMode) {
                Button('上一章').fontSize(12).height(36).enabled(this.vm.previousId !== '' && !this.vm.busy && !this.vm.pagerMoving).onClick(() => this.chapter(this.vm.previousId))
                Button('下一章').fontSize(12).height(36).enabled(this.vm.nextId !== '' && !this.vm.busy && !this.vm.pagerMoving).onClick(() => this.chapter(this.vm.nextId))
              }
              Button('重试图像').fontSize(12).height(36).enabled(!this.vm.busy && !this.vm.pagerMoving).onClick(() => this.vm.retry())
              Button('收起菜单').fontSize(12).height(36).onClick(() => { this.menuVisible = false; this.optionsVisible = false; })
            }
          }.width('100%').padding(12).backgroundColor('#EC1D2523')
        }.width('100%').height('100%')
      }
      if (this.optionsVisible && this.menuVisible) {
        Stack({ alignContent: Alignment.Center }) {
        Column() {}.width('100%').height('100%')
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => { this.optionsVisible = false; })
        Scroll() {
        Column({ space: 12 }) {
          Text('阅读设置').fontSize(19).fontColor('#FFFFFF')
          Row({ space: 8 }) {
            Select([{ value: '水平滑动' },{ value: '纵向单页' },{ value: '无缝条漫' },{ value: '间隔连续' },{ value: '双页仿真卷页' },{ value: '点击单页' },{ value: '单页仿真卷页' },{ value: '连续滑动（无缝）' }]).fontColor('#FFFFFF').backgroundColor('#40554B').selected(READER_MODES.indexOf(this.vm.mode)).value(['水平滑动','纵向单页','无缝条漫','间隔连续','双页仿真卷页','点击单页','单页仿真卷页','连续滑动（无缝）'][READER_MODES.indexOf(this.vm.mode)]).onSelect((index: number) => { if (index >= 0 && index < READER_MODES.length) { this.zoom = 1; this.vm.switchMode(READER_MODES[index]); } })
            Button(this.vm.direction === 'ltr' ? '从左到右' : '从右到左').fontSize(13).onClick(() => this.vm.switchDirection())
          }
          Row({ space: 8 }) {
            Select([{ value: '深色背景' },{ value: '灰色背景' },{ value: '浅色背景' }]).fontColor('#FFFFFF').backgroundColor('#40554B').selected(['dark','gray','light'].indexOf(this.vm.background)).value(['深色背景','灰色背景','浅色背景'][['dark','gray','light'].indexOf(this.vm.background)]).onSelect((i: number) => { if (i >= 0 && i < 3) { this.display('background',['dark','gray','light'][i]); } })
            Select([{ value: '自动适配' },{ value: '适合宽度' },{ value: '适合高度' }]).fontColor('#FFFFFF').backgroundColor('#40554B').selected(['auto','width','height'].indexOf(this.vm.scale)).value(['自动适配','适合宽度','适合高度'][['auto','width','height'].indexOf(this.vm.scale)]).enabled(!this.vm.isStrip()).onSelect((i: number) => { if (i >= 0 && i < 3) { this.zoom = 1; this.display('scale',['auto','width','height'][i]); } })
          }
          Row({ space: 8 }) {
            Select([{ value: '左右侧点击' },{ value: '三等分点击' },{ value: '点击仅菜单' }]).fontColor('#FFFFFF').backgroundColor('#40554B').selected(['sides','thirds','menu'].indexOf(this.vm.tapZones)).value(['左右侧点击','三等分点击','点击仅菜单'][['sides','thirds','menu'].indexOf(this.vm.tapZones)]).onSelect((i: number) => { if (i >= 0 && i < 3) { this.display('tap',['sides','thirds','menu'][i]); } })
            Button(this.vm.invertTap ? '点击方向：反转' : '点击方向：默认').fontSize(12).onClick(() => this.display('invert',(!this.vm.invertTap).toString()))
          }
          Select([{ value: '原色' },{ value: '灰度' },{ value: '反色' },{ value: '暖色' }]).selected(['none','gray','invert','sepia'].indexOf(this.effects.filter)).value(['原色','灰度','反色','暖色'][['none','gray','invert','sepia'].indexOf(this.effects.filter)]).onSelect((i: number) => { this.effects.filter = ['none','gray','invert','sepia'][i]; this.saveEffects(); })
          Select([{ value: '跟随方向' },{ value: '锁定竖屏' },{ value: '锁定横屏' }]).selected(['system','portrait','landscape'].indexOf(this.effects.orientation)).value(['跟随方向','锁定竖屏','锁定横屏'][['system','portrait','landscape'].indexOf(this.effects.orientation)]).onSelect((i: number) => { this.effects.orientation = ['system','portrait','landscape'][i]; this.saveEffects(); })
          Text(this.effects.brightness < 0 ? '亮度：跟随系统' : '阅读亮度：' + Math.round(this.effects.brightness * 100).toString() + '%').fontColor('#FFFFFF')
          Slider({ value: Math.max(5,this.effects.brightness * 100),min: 5,max: 100,step: 1 }).onChange((value: number) => { this.effects.brightness = value / 100; this.saveEffects(); })
          Button('亮度跟随系统').onClick(() => { this.effects.brightness = -1; this.saveEffects(); })
          Text('连续滑动：纵向无缝拼接，拖动跟手，松手停在当前位置。水平、卷页及双页仿真支持跟手拖动；左右区轻点即翻，中间轻点菜单、双击缩放，也可双指缩放。放大后优先平移；点击单页关闭拖动翻页。').fontSize(12).fontColor('#CBD8D4').maxLines(5)
          Row({ space: 8 }) {
            Button('缩小').fontSize(13).enabled(this.zoom > 1).onClick(() => { this.zoom = Math.max(1,this.zoom - 0.5); })
            Text(Math.round(this.zoom * 100).toString() + '%').fontColor('#FFFFFF').fontSize(14).width(46)
            Button('放大').fontSize(13).enabled(this.zoom < 4).onClick(() => { this.zoom = Math.min(4,this.zoom + 0.5); })
            Button('还原').fontSize(13).onClick(() => { this.zoom = 1; })
          }
          if (!this.vm.trialMode) {
            Text(this.vm.incognito ? '隐身：不保存进度/历史；主动书签和下载仍保留' : '模式、方向和显示设置仅保存到当前漫画').fontSize(12).fontColor('#CBD8D4')
            Row({ space: 8 }) {
              Button(this.vm.bookmarked ? '取消章节书签' : '添加章节书签').fontSize(13).onClick(() => this.vm.toggleBookmark())
              Button('恢复全局阅读设置').fontSize(13).onClick(() => this.vm.resetReading())
            }
            Row({ space: 8 }) {
              Button('下载本章').fontSize(13).onClick(() => this.vm.download())
              Button('下载管理').fontSize(13).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/DownloadsPage' }))
            }
            Button('标记本章已读完').fontSize(13).enabled(!this.vm.incognito && this.vm.index + 1 === this.vm.total).onClick(() => this.vm.save(true))
          }
          Button('完成').fontSize(13).onClick(() => { this.optionsVisible = false; })
        }.padding(20).width('100%')
        }.height(Math.min(this.viewportHeight * 0.85,this.vm.trialMode ? 390 : 560)).width('90%').constraintSize({ maxWidth: 680 }).backgroundColor('#F02B3430').borderRadius(20).scrollBar(BarState.Auto)
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(readerBackground(this.vm.background)).onAreaChange((_old: Area,area: Area) => { const height = Number(area.height); if (height > 0) { this.viewportHeight = height; } })
  }
}
