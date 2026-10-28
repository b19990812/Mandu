import { url } from '@kit.ArkTS';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { payloadDigest } from '../storage/PayloadDigest';
import { RcpTransport } from '../network/RcpTransport';
import { UrlPolicy } from '../network/UrlPolicy';
import { CallContext } from '../model/RequestTypes';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { JsonExtractor } from '../parsing/JsonExtractor';
import { checkCall, requireHttpSuccess } from './SourceHttp';
import { ExtensionCatalog, ExtensionEntry, repositoryAddress } from './ExtensionCatalog';

export interface RepositoryPreview { address: string; key: string; raw: string; previous: string; entries: ExtensionEntry[]; }
export interface SavedRepository { key: string; address: string; updatedAt: number; entries: ExtensionEntry[]; }
export class ExtensionRepositoryService {
  private readonly db: ReaderDatabase;
  constructor(db: ReaderDatabase) { this.db = db; }
  async list(): Promise<SavedRepository[]> {
    const rows = await this.db.read((db) => db.rows("SELECT key,value FROM reader_settings WHERE key LIKE 'extension.repository.%' ORDER BY key",[],(row): string[] => [row.getString(0),row.getString(1)]));
    return rows.map((row: string[]): SavedRepository => {
      const data = new JsonExtractor().parse(row[1]); if (data.kind !== 'array' || data.items.length !== 3 || data.items[0].kind !== 'string' || data.items[1].kind !== 'string' || data.items[2].kind !== 'number') { throw new AppError(ErrorCode.CORRUPT_FILE,'仓库记录损坏'); }
      const address = repositoryAddress(data.items[0].scalar); return { key: row[0],address: address,updatedAt: Number(data.items[2].scalar),entries: new ExtensionCatalog().parse(data.items[1].scalar,address) };
    });
  }
  async fetch(input: string,ctx: CallContext): Promise<RepositoryPreview> {
    const address = repositoryAddress(input); const key = 'extension.repository.' + await payloadDigest(address);
    const previous = await this.db.read(async (db) => { const rows = await db.rows('SELECT value FROM reader_settings WHERE key=?',[key],(row) => row.getString(0)); return rows[0] || ''; });
    const response = await new RcpTransport(new UrlPolicy([new url.URL(address).hostname]),true,false).send({ sourceId: 'extension-repository',url: address,headers: [{ name: 'Accept',value: 'application/json' }],maxBytes: 524288 },ctx);
    requireHttpSuccess(response); checkCall(ctx); const entries = new ExtensionCatalog().parse(response.body,address);
    return { address: address,key: key,raw: response.body,previous: previous,entries: entries };
  }
  async save(preview: RepositoryPreview): Promise<void> {
    const address = repositoryAddress(preview.address); const key = 'extension.repository.' + await payloadDigest(address); new ExtensionCatalog().parse(preview.raw,address);
    if (key !== preview.key) { throw new AppError(ErrorCode.CONFLICT,'仓库预览身份已改变'); }
    await this.db.transaction(async (db) => {
      const rows = await db.rows("SELECT key,value FROM reader_settings WHERE key LIKE 'extension.repository.%'",[],(row): string[] => [row.getString(0),row.getString(1)]);
      const before = rows.find((row: string[]) => row[0] === key); if ((before ? before[1] : '') !== preview.previous) { throw new AppError(ErrorCode.CONFLICT,'仓库已被更新，请重新预览'); }
      if (before) {
        const old = new JsonExtractor().parse(before[1]); const previousEntries = new ExtensionCatalog().parse(old.items[1].scalar,address); const nextEntries = new ExtensionCatalog().parse(preview.raw,address);
        previousEntries.forEach((entry: ExtensionEntry) => { const next = nextEntries.find((item: ExtensionEntry) => item.pkg === entry.pkg && item.externalId === entry.externalId); if (next && next.code < entry.code) { throw new AppError(ErrorCode.CONTENT_CHANGED,'仓库返回了较低版本，保留现有目录'); } });
      }
      if (!before && rows.length >= 8) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'最多保存8个扩展仓库'); }
      await db.run('INSERT OR REPLACE INTO reader_settings(key,value) VALUES(?,?)',[key,JSON.stringify([address,preview.raw,Date.now()])]);
    });
  }
  async remove(key: string): Promise<void> {
    if (!/^extension\.repository\.[a-f0-9]{64}$/.test(key)) { throw new AppError(ErrorCode.CONFIG_INVALID,'仓库标识无效'); }
    await this.db.transaction((db) => db.run('DELETE FROM reader_settings WHERE key=?',[key]));
  }
}
