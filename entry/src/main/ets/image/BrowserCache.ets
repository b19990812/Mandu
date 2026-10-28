import { fileIo as fs } from '@kit.CoreFileKit';
import { FileStore } from '../storage/FileStore';
import { FilePins } from '../storage/FilePins';
import { payloadDigest } from '../storage/PayloadDigest';
import { JsonExtractor } from '../parsing/JsonExtractor';
import { ReaderAsset } from './ReaderAssetCache';

interface CacheRecord { indexKey: string; fileKey: string; asset: ReaderAsset; createdAt: number; usedAt: number; }
export interface CachedAssetLease { asset: ReaderAsset; release: () => void; }

// Rebuildable index, stable resource identity, generated filenames, no remote URLs.
// Offline downloads use filesDir and are outside this service's root.
export class BrowserCache {
  private static tail: Promise<void> = Promise.resolve();
  private static budget: number = 536870912;
  private readonly files: FileStore;
  constructor(cacheDir: string) { this.files = new FileStore(cacheDir, 'reader_assets'); }
  static setBudget(miB: number): void { BrowserCache.budget = Math.max(128, Math.min(1024, miB)) * 1048576; }
  private async exclusive<T>(work: () => Promise<T>): Promise<T> {
    const previous = BrowserCache.tail; let release: () => void = () => {};
    BrowserCache.tail = new Promise<void>((resolve) => { release = resolve; }); await previous;
    try { return await work(); } finally { release(); }
  }
  async identity(sourceId: string, chapterId: string, pageKey: string, revision: string): Promise<string> {
    return (await payloadDigest(JSON.stringify([sourceId,'anonymous',chapterId,pageKey,revision]))).substring(0,40) + '_index';
  }
  private record(key: string): CacheRecord | undefined {
    try {
      const raw = this.files.readText(key, 4096); if (!raw) { return undefined; }
      const parser = new JsonExtractor(); const root = parser.parse(raw);
      const value = (name: string): string => parser.at(root,name)?.scalar || '';
      const fileKey = value('file'); const width = Number(value('width')); const height = Number(value('height')); const bytes = Number(value('bytes'));
      const createdAt = Number(value('created')); const usedAt = Number(value('used'));
      if (!/^[a-f0-9]{32}(?:_[0-9]+_[0-9]+)?$/.test(fileKey) || width < 1 || width > 8192 || height < 1 || height > 60000 || width * height > 134217728 || bytes < 1 || bytes > 33554432 || !Number.isFinite(createdAt) || !Number.isFinite(usedAt) || this.files.size(fileKey) !== bytes) { return undefined; }
      return { indexKey: key, fileKey: fileKey, asset: { uri: 'file://' + this.files.localPath(fileKey), width: width, height: height, bytes: bytes }, createdAt: createdAt, usedAt: usedAt };
    } catch (_) { return undefined; }
  }
  async acquire(indexKey: string): Promise<CachedAssetLease | undefined> {
    return this.exclusive(async (): Promise<CachedAssetLease | undefined> => {
      const record = this.record(indexKey); if (!record || Date.now() - record.createdAt > 43200000) { return undefined; }
      record.usedAt = Date.now(); await this.write(record);
      return { asset: record.asset,release: FilePins.pin(this.files.localPath(record.fileKey)) };
    });
  }
  async put(indexKey: string, fileKey: string, asset: ReaderAsset): Promise<void> {
    await this.exclusive(async () => {
      const now = Date.now(); await this.write({ indexKey: indexKey, fileKey: fileKey, asset: asset, createdAt: now, usedAt: now }); await this.trim(false);
    });
  }
  private async write(record: CacheRecord): Promise<void> {
    await this.files.writeText(record.indexKey, '{"schema":1,"file":' + JSON.stringify(record.fileKey) + ',"width":' + record.asset.width.toString() + ',"height":' + record.asset.height.toString() + ',"bytes":' + record.asset.bytes.toString() + ',"created":' + record.createdAt.toString() + ',"used":' + record.usedAt.toString() + '}');
  }
  async reclaimable(): Promise<number> { return this.exclusive(async () => this.files.keys().filter((key: string) => /^[a-f0-9]{32}(?:_[0-9]+_[0-9]+)?$/.test(key) && !FilePins.inUse(this.files.localPath(key))).reduce((sum: number, key: string) => sum + (this.files.size(key) || 0), 0)); }
  async clean(): Promise<number> { return this.exclusive(() => this.trim(true)); }
  private async trim(all: boolean): Promise<number> {
    const keys = this.files.keys(); const records: CacheRecord[] = []; const referenced: Set<string> = new Set(); let removed = 0;
    keys.filter((key: string) => /^[a-f0-9]{40}_index$/.test(key)).forEach((key: string) => {
      const record = this.record(key); if (record) { records.push(record); referenced.add(record.fileKey); } else { this.files.remove(key); }
    });
    let size = records.reduce((sum: number, record: CacheRecord) => sum + record.asset.bytes, 0);
    records.sort((a: CacheRecord,b: CacheRecord) => a.usedAt - b.usedAt).forEach((record: CacheRecord) => {
      if ((all || size > BrowserCache.budget || Date.now() - record.createdAt > 43200000) && !FilePins.inUse(this.files.localPath(record.fileKey))) {
        this.files.remove(record.fileKey); this.files.remove(record.indexKey); size -= record.asset.bytes; removed += record.asset.bytes;
      }
    });
    keys.filter((key: string) => /^[a-f0-9]{32}(?:_[0-9]+_[0-9]+)?(?:\.part)?$/.test(key)).forEach((name: string) => {
      const key = name.replace(/\.part$/, ''); if (referenced.has(key) || FilePins.inUse(this.files.localPath(key))) { return; }
      const path = this.files.localPath(key) + (name.endsWith('.part') ? '.part' : '');
      if (fs.accessSync(path)) { const bytes = fs.statSync(path).size; this.files.remove(key); removed += bytes; }
    });
    return removed;
  }
}
