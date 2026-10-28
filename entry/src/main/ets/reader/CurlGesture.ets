import { spreadMargin } from './PageTurnGeometry';

export class CurlGesture {
  corner: number = 1;
  fingerY: number = 1;
  velocity: number = 0;
  private startY: number = 0;
  begin(y: number,height: number): void {
    this.startY = y; this.corner = y < height / 2 ? 0 : 1; this.fingerY = Math.max(0,Math.min(1,y / Math.max(1,height))); this.velocity = 0;
  }
  move(offsetY: number,height: number,velocityX: number,width: number): void {
    this.fingerY = Math.max(0,Math.min(1,(this.startY + offsetY) / Math.max(1,height)));
    this.velocity = Math.max(-4,Math.min(4,velocityX / Math.max(1,width)));
  }
  resume(height: number): void { this.startY = this.fingerY * Math.max(1,height); }
  travel(width: number,book: boolean): number { return book ? Math.max(1,width - 2 * spreadMargin(width)) : Math.max(1,width) * 2; }
  progress(offset: number,width: number,book: boolean): number { return Math.min(1,Math.abs(offset) / this.travel(width,book)); }
}
