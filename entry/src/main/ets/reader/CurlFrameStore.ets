import { image } from '@kit.ImageKit';
import { CURL_MAX_PIXELS } from './PageTurnGeometry';

class CurlFrameEntry {
  map?: image.PixelMap;
  pending?: Promise<boolean>;
}

// Each bounded pager slot owns at most one prepared texture. Gesture callbacks only read it.
export class CurlFrameStore {
  private entries: Map<string,CurlFrameEntry> = new Map();
  private bytes: number = 0;
  private readonly retire: (maps: image.PixelMap[]) => void;
  constructor(retire: (maps: image.PixelMap[]) => void) { this.retire = retire; }
  get(key: string): image.PixelMap | undefined { return this.entries.get(key)?.map; }
  invalidate(key: string): void {
    const keys: string[] = []; this.entries.forEach((_entry: CurlFrameEntry,existing: string) => { if (existing !== key) { keys.push(existing); } }); this.retain(keys);
  }
  capture(key: string, snapshot: () => Promise<image.PixelMap>): Promise<boolean> {
    const existing = this.entries.get(key);
    if (existing?.map) { return Promise.resolve(true); }
    if (existing?.pending) { return existing.pending; }
    const entry = new CurlFrameEntry(); this.entries.set(key,entry);
    const pending = this.read(key,entry,snapshot); entry.pending = pending; return pending;
  }
  private async read(key: string, entry: CurlFrameEntry, snapshot: () => Promise<image.PixelMap>): Promise<boolean> {
    let map: image.PixelMap | undefined;
    try {
      map = await snapshot();
      const size = map.getImageInfoSync().size;
      const bytes = map.getPixelBytesNumber();
      if (this.entries.get(key) !== entry || size.width * size.height > CURL_MAX_PIXELS || bytes > 33554432 || this.bytes + bytes > 100663296) { return false; }
      entry.map = map; this.bytes += bytes; map = undefined; return true;
    } catch (_) { return false; }
    finally {
      entry.pending = undefined;
      if (map) { this.retire([map]); }
      if (!entry.map && this.entries.get(key) === entry) { this.entries.delete(key); }
    }
  }
  retain(keys: string[]): void {
    const retired: image.PixelMap[] = [];
    this.entries.forEach((entry: CurlFrameEntry,key: string) => {
      if (keys.indexOf(key) >= 0) { return; }
      this.entries.delete(key);
      if (entry.map) { this.bytes -= entry.map.getPixelBytesNumber(); retired.push(entry.map); }
    });
    if (retired.length) { this.retire(retired); }
  }
  clear(): void { this.retain([]); }
}
