import { image } from '@kit.ImageKit';
// Cylindrical strip projection: the page texture bends back over a moving fold,
// with reverse-face tint and fold shadow. This is not a translated page or crossfade.
@Component
export struct PaperCurlCanvas {
  // The pager owns these native handles for the lifetime of this turn.
  front: image.PixelMap | undefined = undefined;
  behind: image.PixelMap | undefined = undefined;
  @Prop @Watch('paint') progress: number = 0;
  @Prop @Watch('paint') reverse: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;
  private paint(): void {
    if (!this.ready || !this.front || !this.behind) { return; }
    const ctx = this.context; const w = ctx.width; const h = ctx.height;
    if (w <= 0 || h <= 0) { return; }
    const p = Math.max(0,Math.min(1,this.progress)); ctx.clearRect(0,0,w,h); ctx.drawImage(this.behind,0,0,w,h);
    if (p >= 1) { return; }
    const axis = w * (1 - 2 * p); const radius = Math.max(0.1,w * 0.14 * Math.sin(Math.PI * p));
    const info = this.front.getImageInfoSync(); if (!info?.size) { return; }
    const strips = 64; const step = w / strips;
    const project = (u: number): number => { const theta = (u - axis) / radius; return u <= axis ? u : theta <= Math.PI ? axis + radius * Math.sin(theta) : axis - (u - axis - Math.PI * radius); };
    for (let i = 0; i < strips; i++) {
      const u = i * step; const v = (i + 1) * step; const x1 = project(u); const x2 = project(v);
      const left = Math.min(x1,x2); const width = Math.max(0.2,Math.abs(x2 - x1));
      const x = this.reverse ? w - left - width : left;
      if (x + width < 0 || x > w) { continue; }
      const theta = Math.max(0,(u + step / 2 - axis) / radius);
      const sx = (this.reverse ? w - v : u) / w * info.size.width;
      ctx.drawImage(this.front,sx,0,info.size.width / strips,info.size.height,x,0,width + 0.5,h);
      if (theta > Math.PI / 2) { ctx.fillStyle = 'rgba(242,237,221,0.88)'; ctx.fillRect(x,0,width + 0.5,h); }
      const shade = theta > 0 && theta < Math.PI ? Math.min(0.38,Math.sin(theta) * 0.38) : 0;
      if (shade > 0) { ctx.fillStyle = 'rgba(0,0,0,' + shade.toString() + ')'; ctx.fillRect(x,0,width + 0.5,h); }
    }
    const fold = this.reverse ? w - axis : axis;
    if (fold > 0 && fold < w && p > 0) {
      const shadow = ctx.createLinearGradient(fold - radius * 0.25,0,fold + radius * 0.25,0);
      shadow.addColorStop(0,'rgba(0,0,0,0)'); shadow.addColorStop(0.5,'rgba(0,0,0,0.24)'); shadow.addColorStop(1,'rgba(0,0,0,0)');
      ctx.fillStyle = shadow; ctx.fillRect(fold - radius * 0.25,0,radius * 0.5,h);
    }
  }
  build() { Canvas(this.context).width('100%').height('100%').onReady(() => { this.ready = true; this.paint(); }).onAreaChange(() => this.paint()).hitTestBehavior(HitTestMode.None) }
}
