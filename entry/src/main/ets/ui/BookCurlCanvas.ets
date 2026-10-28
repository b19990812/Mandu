import { image } from '@kit.ImageKit';
import { bookProjection, BookProjection, spreadMargin } from '../reader/PageTurnGeometry';

@Component
export struct BookCurlCanvas {
  // Native handles must retain their identity; @Prop deep copies lose PixelMap's native context.
  front: image.PixelMap | undefined = undefined;
  behind: image.PixelMap | undefined = undefined;
  @Prop @Watch('paint') progress: number = 0;
  @Prop @Watch('paint') reverse: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;
  private paint(): void {
    if (!this.ready || !this.front || !this.behind) { return; }
    const ctx = this.context; const w = ctx.width; const h = ctx.height; if (w <= 0 || h <= 0) { return; }
    const p = Math.max(0,Math.min(1,this.progress)); ctx.clearRect(0,0,w,h);
    if (p >= 1) { ctx.drawImage(this.behind,0,0,w,h); return; }
    ctx.drawImage(this.front,0,0,w,h); if (p <= 0) { return; }
    const current = this.front.getImageInfoSync(); const target = this.behind.getImageInfoSync();
    if (!current?.size || !target?.size) { return; }
    const margin = spreadMargin(w); const leaf = w / 2 - margin; const origin = this.reverse ? -1 : 1;
    // The unturned page remains visible. The outgoing half reveals its new underlying page.
    const targetX = this.reverse ? margin : w / 2;
    ctx.drawImage(this.behind,targetX / w * target.size.width,0,leaf / w * target.size.width,target.size.height,targetX,0,leaf,h);
    const strength = Math.sin(Math.PI * p); const shadowWidth = leaf * 0.3 * strength;
    const shade = ctx.createLinearGradient(w / 2 - shadowWidth,0,w / 2 + shadowWidth,0);
    shade.addColorStop(0,'rgba(0,0,0,0)'); shade.addColorStop(0.5,'rgba(0,0,0,0.22)'); shade.addColorStop(1,'rgba(0,0,0,0)');
    ctx.fillStyle = shade; ctx.fillRect(w / 2 - shadowWidth,0,shadowWidth * 2,h);
    const count = 80; const points: BookProjection[] = []; const strips: number[] = [];
    for (let i = 0; i <= count; i++) { points.push(bookProjection(i / count,p,leaf)); if (i < count) { strips.push(i); } }
    strips.sort((a: number,b: number) => points[a].z + points[a + 1].z - points[b].z - points[b + 1].z);
    ctx.save(); ctx.beginPath(); ctx.rect(margin,0,w - margin * 2,h); ctx.clip();
    for (let at = 0; at < strips.length; at++) {
      const i = strips[at]; const a = points[i]; const b = points[i + 1];
      const face = Math.cos((a.angle + b.angle) / 2) >= 0; const texture = face ? this.front : this.behind;
      const info = face ? current : target; const increasing = face ? !this.reverse : this.reverse;
      const halfX = face ? this.reverse ? margin : w / 2 : this.reverse ? w / 2 : margin;
      const sourceX = (halfX + (increasing ? i : count - i - 1) / count * leaf) / w * info.size.width;
      const x1 = w / 2 + origin * a.x * a.scale; const x2 = w / 2 + origin * b.x * b.scale;
      const left = Math.min(x1,x2); const width = Math.max(0.25,Math.abs(x2 - x1) + 0.5); const scale = (a.scale + b.scale) / 2;
      const flip = (x2 > x1) !== increasing;
      ctx.save(); ctx.translate(flip ? left + width : left,(1 - scale) * h / 2); if (flip) { ctx.scale(-1,1); }
      ctx.drawImage(texture,sourceX,0,leaf / w * info.size.width / count,info.size.height,0,0,width,h * scale);
      ctx.fillStyle = 'rgba(0,0,0,' + (strength * (0.06 + 0.23 * Math.abs(Math.sin((a.angle + b.angle) / 2)))).toString() + ')';
      ctx.fillRect(0,0,width,h * scale); ctx.restore();
    }
    ctx.restore();
  }
  build() { Canvas(this.context).width('100%').height('100%').onReady(() => { this.ready = true; this.paint(); }).onAreaChange(() => this.paint()).hitTestBehavior(HitTestMode.None) }
}
