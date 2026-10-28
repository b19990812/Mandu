import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { FileStore } from './FileStore';

// Controls only the self-owned fixture site. No real site data or settings are changed.
export class DemoSiteRepository {
  private readonly files: FileStore;
  constructor(context: common.Context) { this.files = new FileStore(context.filesDir, 'demo_site'); }
  revision(): number { return this.files.readText('revision', 1) === '2' ? 2 : 1; }
  async setRevision(revision: number): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(revision === 2 ? '2' : '1');
    await this.files.writeStream('revision', async (sink) => { await sink.write(bytes.buffer as ArrayBuffer); });
  }
}
