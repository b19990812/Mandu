import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import * as renderer from 'libpagecurl.so';

// No PixelMap is copied through @Prop, and no image is decoded by a gesture.
// The native worker reads one upload buffer; the EGL thread owns GPU resources.
export class CurlGpuBridge {
  readonly id: string = 'curl-' + util.generateRandomUUID();
  private loaded: boolean = false;
  private keys: string[] = [];
  private resident: Set<string> = new Set();
  private jobs: Map<string,Promise<boolean>> = new Map();
  private priority: string = '';
  attach(): void { this.loaded = true; renderer.retain(this.id,this.keys.join('|')); renderer.prioritize(this.id,this.priority); }
  detach(): void { this.loaded = false; this.resident.clear(); }
  retain(keys: string[]): void {
    this.keys = keys.slice();
    this.resident.forEach((key: string) => { if (keys.indexOf(key) < 0) { this.resident.delete(key); } });
    if (this.loaded) { renderer.retain(this.id,keys.join('|')); }
  }
  ready(key: string): boolean { return this.loaded && this.resident.has(key); }
  prioritize(keys: string[]): void {
    const priority = keys.join('|'); if (priority === this.priority) { return; }
    this.priority = priority; if (this.loaded) { renderer.prioritize(this.id,priority); }
  }
  async cache(key: string,map: image.PixelMap): Promise<boolean> {
    if (!this.loaded || this.keys.indexOf(key) < 0) { return false; }
    if (this.resident.has(key)) { return true; }
    const existing = this.jobs.get(key); if (existing) { return existing; }
    const job = renderer.cache(this.id,key,map).then((ok: boolean): boolean => {
      if (ok && this.loaded && this.keys.indexOf(key) >= 0) { this.resident.add(key); return true; } return false;
    }).catch((): boolean => false);
    this.jobs.set(key,job);
    try { return await job; } finally { if (this.jobs.get(key) === job) { this.jobs.delete(key); } }
  }
  async drain(): Promise<void> { await Promise.all(Array.from(this.jobs.values())); }
  present(front: string,behind: string,progress: number,corner: number,fingerY: number,reverse: boolean,book: boolean,velocity: number,margin: number): number {
    if (!this.ready(front) || !this.ready(behind)) { return 0; }
    return renderer.present(this.id,front,behind,progress,corner,fingerY,reverse ? 1 : 0,book ? 1 : 0,velocity,margin);
  }
  presented(sequence: number): boolean { return this.loaded && sequence > 0 && renderer.presented(this.id,sequence); }
  clear(): void { if (this.loaded) { renderer.clear(this.id); } }
  metrics(): string { return this.loaded ? renderer.metrics(this.id) : 'surface-unavailable'; }
}
