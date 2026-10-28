import { FolderImages } from '../local/FolderImages';
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { LocalComicService, documentName } from '../local/LocalComicService';
import { CancelScope } from '../model/CancelScope';
import { viewError } from '../vm/ViewOperation';

@Entry
@Component
struct LocalImportPage {
  @State private title: string = '';
  @State private chapter: string = '';
  @State private status: string = '选择一个CBZ/ZIP或同一章的多张图片，按文件名自然排序。';
  @State private selected: string[] = [];
  @State private busy: boolean = false;
  private scope?: CancelScope;
  private closed: boolean = false;
  aboutToDisappear(): void { this.closed = true; this.scope?.cancel(); }
  private async select(): Promise<void> {
    if (this.busy) { return; }
    try {
      const uris = await new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext).select({ maxSelectNumber: 200,fileSuffixFilters: ['漫画与图片|.cbz,.zip,.epub,.png,.jpg,.jpeg,.webp'] });
      if (uris.length && !this.closed) { this.selected = uris; const name = documentName(uris[0]).replace(/\.[^.]+$/,''); if (!this.chapter) { this.chapter = uris.length === 1 ? name : '第1章'; } if (!this.title) { this.title = uris.length === 1 ? name : '本地漫画'; } this.status = '已选择 ' + uris.length.toString() + ' 个文件'; }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error); } }
  }
  private async selectFolder(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const uris = await new picker.DocumentViewPicker(this.getUIContext().getHostContext() as common.UIAbilityContext).select({ maxSelectNumber: 1,selectMode: picker.DocumentSelectMode.FOLDER });
      if (!uris.length || this.closed) { return; }
      const images = await FolderImages.list(uris[0]);
      if (!this.closed) { this.selected = images; if (!this.title) { this.title = documentName(uris[0]); } if (!this.chapter) { this.chapter = '第1章'; } this.status = '文件夹当前层共 ' + images.length.toString() + ' 张图片'; }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error) + '；若设备不支持文件夹授权，可选择多张图片或使用 CBZ'; } }
    finally { this.busy = false; }
  }
  private async importComic(): Promise<void> {
    if (this.busy || !this.selected.length) { return; } this.busy = true; const scope = new CancelScope(); this.scope = scope;
    try {
      const id = await new LocalComicService(this.getUIContext().getHostContext() as common.UIAbilityContext).import(this.title,this.chapter,this.selected,{ callId: 'local-import',deadlineMs: Date.now() + 900000,cancel: scope,ruleRevision: 1 },(done: number,total: number) => { if (!this.closed) { this.status = '正在校验并导入 ' + done.toString() + ' / ' + total.toString(); } });
      if (!this.closed) { this.status = '导入完成，已加入书架'; this.selected = []; this.getUIContext().getRouter().pushUrl({ url: 'pages/DetailPage',params: { mangaId: id } }); }
    } catch (error) { if (!this.closed) { this.status = viewError(error as Error); } } finally { this.busy = false; }
  }
  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('本地漫画').fontSize(26).fontWeight(FontWeight.Bold)
        Text('同一书名可继续添加章节；同书同章名会替换该章文件并保留进度。').fontSize(14)
        TextInput({ text: this.title,placeholder: '漫画书名' }).maxLength(100).enabled(!this.busy).onChange((value: string) => { this.title = value; })
        TextInput({ text: this.chapter,placeholder: '章节名称' }).maxLength(100).enabled(!this.busy).onChange((value: string) => { this.chapter = value; })
        Button('选择CBZ / ZIP / EPUB / 图片').enabled(!this.busy).onClick(() => this.select())
        Button('选择图片文件夹').enabled(!this.busy).onClick(() => this.selectFolder())
        Text(this.status).fontSize(14)
        Text('JPEG、PNG、WebP；每张32MiB、每章512MiB或2000张。ZIP仅支持未加密Stored/Deflate；支持图片型 EPUB（按 spine 顺序）、文件夹当前层图片；RAR 暂不支持。').fontSize(12)
        Button('校验并导入书架').enabled(!this.busy && this.selected.length > 0 && this.title.trim() !== '' && this.chapter.trim() !== '').onClick(() => this.importComic())
        if (this.busy) { Button('取消导入').onClick(() => this.scope?.cancel()) }
        Button('返回').onClick(() => this.getUIContext().getRouter().back())
      }.width('100%').padding(24).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.theme_f7f4ed'))
  }
}
