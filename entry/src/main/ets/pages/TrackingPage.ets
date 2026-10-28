import { common } from '@kit.AbilityKit';
import { TrackingVM } from '../vm/TrackingVM';
interface TrackingParams { mangaId?: string; }
@Entry
@Component
struct TrackingPage {
  @State private vm: TrackingVM = new TrackingVM();
  aboutToAppear(): void { const params = this.getUIContext().getRouter().getParams() as TrackingParams; this.vm.initialize(this.getUIContext().getHostContext() as common.UIAbilityContext,params?.mangaId || ''); }
  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('Bangumi Tracking').fontSize(26)
        Text(this.vm.status).fontSize(14)
        Text(this.vm.account ? '已授权：' + this.vm.account : '尚未授权').fontSize(16)
        Text('在 Bangumi 官方令牌管理页创建具有收藏写权限的个人访问令牌，再粘贴到此处。').fontSize(13)
        TextInput({ text: this.vm.token,placeholder: '个人访问令牌' }).type(InputType.Password).maxLength(900).enabled(!this.vm.busy).onChange((value: string) => { this.vm.token = value; })
        Button('验证并保存授权').enabled(!this.vm.busy && this.vm.token !== '').onClick(() => this.vm.login())
        Button('移除授权').enabled(!this.vm.busy && this.vm.account !== '').onClick(() => this.vm.logout())
        if (this.vm.mangaId) {
          TextInput({ text: this.vm.subjectId,placeholder: 'Bangumi 书籍条目数字 ID' }).type(InputType.Number).enabled(!this.vm.busy).onChange((value: string) => this.vm.changeSubject(value))
          Button('校验条目').enabled(!this.vm.busy).onClick(() => this.vm.inspect())
          Text(this.vm.subjectName).fontSize(18)
          Text('同步已读话数（请核对目标条目的编号）').fontSize(14)
          TextInput({ text: this.vm.chapters }).type(InputType.Number).enabled(!this.vm.busy).onChange((value: string) => { this.vm.chapters = value; })
          Select([{ value: '想读' },{ value: '读过' },{ value: '在读' },{ value: '搁置' },{ value: '抛弃' }]).selected(this.vm.collection - 1).value(['想读','读过','在读','搁置','抛弃'][this.vm.collection - 1]).onSelect((index: number) => { this.vm.collection = index + 1; })
          Text('评分：' + this.vm.score.toString() + '（0为未评分）')
          Slider({ value: this.vm.score,min: 0,max: 10,step: 1 }).onChange((value: number) => { this.vm.score = value; })
          Button('确认绑定并加入同步队列').enabled(!this.vm.busy && this.vm.subjectName !== '' && this.vm.account !== '').onClick(() => this.vm.queue())
        }
        Text('待同步：' + this.vm.pending.toString()).fontSize(14)
        Button('发送待同步记录').enabled(!this.vm.busy && this.vm.account !== '').onClick(() => this.vm.sync())
        Text('离线记录保留，前台每分钟重试。同步会修改所绑定条目的话数、收藏状态和评分；不覆盖本地阅读进度。').fontSize(12)
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').backgroundColor($r('app.color.theme_f7f4ed'))
  }
}
