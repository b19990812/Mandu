import { CancelScope } from '../model/CancelScope';

interface PreloadTask { index: number; scope: CancelScope; started: boolean; }

// Keep overlapping requests alive across turns. Compressed files go to the existing
// bounded disk cache; this queue never allocates PixelMaps or offline download rows.
export class ReaderPreloader {
  private readonly tasks: Map<number, PreloadTask> = new Map();
  private readonly load: (index: number, scope: CancelScope) => Promise<void>;
  private active: number = 0;
  private order: number[] = [];
  constructor(load: (index: number, scope: CancelScope) => Promise<void>) { this.load = load; }
  update(index: number, span: number, total: number, ahead: number): void {
    const order: number[] = [];
    for (let page = index + span; page < Math.min(total,index + span + ahead); page++) { order.push(page); }
    if (index > 0) { order.push(index - 1); }
    this.order = order;
    this.tasks.forEach((task: PreloadTask,page: number) => {
      if (order.indexOf(page) < 0) { task.scope.cancel(); this.tasks.delete(page); }
    });
    order.forEach((page: number) => {
      if (!this.tasks.has(page)) { this.tasks.set(page,{ index: page,scope: new CancelScope(),started: false }); }
    });
    this.pump();
  }
  private pump(): void {
    for (let i = 0; i < this.order.length && this.active < 2; i++) {
      const task = this.tasks.get(this.order[i]); if (!task || task.started) { continue; }
      task.started = true; this.active++;
      this.load(task.index,task.scope).catch(() => {}).finally(() => { this.active--; this.pump(); });
    }
  }
  clear(): void { this.order = []; this.tasks.forEach((task: PreloadTask) => task.scope.cancel()); this.tasks.clear(); }
}
