import { image } from '@kit.ImageKit';

class CurlSnapshotJob {
  readonly key: string;
  readonly snapshot: () => Promise<image.PixelMap>;
  readonly resolve: (map: image.PixelMap) => void;
  readonly reject: (error: Error) => void;
  constructor(key: string,snapshot: () => Promise<image.PixelMap>,resolve: (map: image.PixelMap) => void,reject: (error: Error) => void) {
    this.key = key; this.snapshot = snapshot; this.resolve = resolve; this.reject = reject;
  }
}

// Serialize component snapshots, but let the preceding native upload overlap.
// Pending work follows the latest reading intent; an in-flight snapshot still
// completes through CurlFrameStore's generation checks and normal retirement.
export class CurlSnapshotQueue {
  private keys: string[] = [];
  private paused: boolean = false;
  private active: boolean = false;
  private jobs: CurlSnapshotJob[] = [];
  order(keys: string[],paused: boolean): void {
    this.keys = keys.slice(); this.paused = paused;
    this.jobs = this.jobs.filter((job: CurlSnapshotJob) => {
      if (keys.indexOf(job.key) >= 0) { return true; }
      job.reject(new Error('卷页快照已过期')); return false;
    });
    this.pump();
  }
  capture(key: string,snapshot: () => Promise<image.PixelMap>): Promise<image.PixelMap> {
    return new Promise<image.PixelMap>((resolve,reject) => {
      if (this.keys.indexOf(key) < 0) { reject(new Error('卷页快照已过期')); return; }
      this.jobs.push(new CurlSnapshotJob(key,snapshot,resolve,reject)); this.pump();
    });
  }
  private pump(): void {
    if (this.active || this.paused || !this.jobs.length) { return; }
    this.jobs.sort((a: CurlSnapshotJob,b: CurlSnapshotJob) => this.keys.indexOf(a.key) - this.keys.indexOf(b.key));
    const job = this.jobs.shift(); if (!job) { return; }
    this.active = true;
    Promise.resolve().then(() => job.snapshot()).then(job.resolve,job.reject).finally(() => { this.active = false; this.pump(); });
  }
}
