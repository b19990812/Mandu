import { EpubImages } from './EpubImages';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { DownloadedPage } from '../model/DownloadTypes';
import { checkCall } from '../source/SourceHttp';
import { FileStore } from '../storage/FileStore';
import { FilePins } from '../storage/FilePins';
import { ReaderDatabase } from '../storage/ReaderDatabase';
import { payloadDigest } from '../storage/PayloadDigest';
import { FileVerifier, VerifiedImage } from '../image/FileVerifier';
import { ManifestCodec } from '../parsing/ManifestCodec';
import { ArchiveInput, ComicArchive, ComicEntry, naturalName } from './ComicArchive';

export const LOCAL_SOURCE: string = 'org.hsmihon.local';
export function documentName(uri: string): string {
  const name = uri.split('?')[0].split('/').pop() || '本地章节';
  try { return decodeURIComponent(name); } catch (_) { return name; }
}
interface LocalImage { name: string; read: () => Promise<ArrayBuffer>; }

export class LocalComicService {
  private static importing: boolean = false;
  private readonly db: ReaderDatabase;
  private readonly files: FileStore;
  constructor(context: common.UIAbilityContext) { this.db = ReaderDatabase.shared(context); this.files = new FileStore(context.filesDir,'downloads'); }
  private input(fd: number): ArchiveInput {
    const size = fs.statSync(fd).size;
    return { size: size,read: (offset: number,length: number): ArrayBuffer => {
      if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) || offset < 0 || length < 0 || length > ComicArchive.MAX_IMAGE + 1 || offset + length > size) { throw new AppError(ErrorCode.CORRUPT_FILE,'本地文件读取范围无效'); }
      const bytes = new ArrayBuffer(length); let read = 0;
      while (read < length) { const part = new ArrayBuffer(length - read); const count = fs.readSync(fd,part,{ offset: offset + read,length: part.byteLength }); if (count < 1) { throw new AppError(ErrorCode.CORRUPT_FILE,'本地文件提前结束'); } new Uint8Array(bytes).set(new Uint8Array(part,0,count),read); read += count; }
      if (fs.statSync(fd).size !== size) { throw new AppError(ErrorCode.CONTENT_CHANGED,'导入期间文件发生变化'); } return bytes;
    } };
  }
  async import(title: string, chapterTitle: string, uris: string[], ctx: CallContext, progress: (done: number,total: number) => void): Promise<string> {
    if (LocalComicService.importing) { throw new AppError(ErrorCode.CONFLICT,'已有本地导入正在进行'); }
    LocalComicService.importing = true;
    try { return await this.perform(title,chapterTitle,uris,ctx,progress); } finally { LocalComicService.importing = false; }
  }
  private async perform(title: string, chapterTitle: string, uris: string[], ctx: CallContext, progress: (done: number,total: number) => void): Promise<string> {
    const book = title.trim(); const chapter = chapterTitle.trim();
    if (!book || book.length > 100 || !chapter || chapter.length > 100 || /[\u0000-\u001f\u007f]/.test(book + chapter) || uris.length < 1 || uris.length > 2000) { throw new AppError(ErrorCode.CONFIG_INVALID,'请填写1～100字的书名和章节名，并选择文件'); }
    const archive = uris.length === 1 && /\.(?:cbz|zip|epub)$/i.test(documentName(uris[0]));
    if (!archive && uris.some((uri: string) => !ComicArchive.image(documentName(uri)))) { throw new AppError(ErrorCode.UNSUPPORTED,'一次选择一个CBZ/ZIP，或选择JPEG/PNG/WebP图片'); }
    let zipFile: fs.File | undefined = undefined; const images: LocalImage[] = [];
    const created: string[] = []; let committed = false;
    const mangaId = await payloadDigest(JSON.stringify([LOCAL_SOURCE,book])); const chapterId = await payloadDigest(JSON.stringify([mangaId,chapter]));
    const existing = await this.db.read(async (db) => (await db.rows('SELECT id,state FROM downloads WHERE chapter_id=?',[chapterId],(row): string[] => [row.getString(0),row.getString(1)]))[0]);
    if (existing && existing[1] === 'running') { throw new AppError(ErrorCode.CONFLICT,'章节任务正在运行，暂停后重试'); }
    const taskId = existing ? existing[0] : util.generateRandomUUID();
    const oldKeys = await this.db.read((db) => db.rows('SELECT file_key FROM download_pages WHERE task_id=?',[taskId],(row) => row.getString(0)));
    if (oldKeys.some((key: string) => FilePins.inUse(this.files.localPath(key)))) { throw new AppError(ErrorCode.CONFLICT,'章节正在阅读，请关闭后再重新导入'); }
    try {
      if (archive) {
        zipFile = fs.openSync(uris[0],fs.OpenMode.READ_ONLY); const input = this.input(zipFile.fd); const decoder = new ComicArchive();
        const ordered = /\.epub$/i.test(documentName(uris[0])) ? await new EpubImages().entries(input,ctx) : decoder.entries(input);
        ordered.forEach((entry: ComicEntry) => images.push({ name: entry.name,read: async (): Promise<ArrayBuffer> => decoder.image(input,entry) }));
      } else {
        const sorted = uris.slice().sort((a: string,b: string) => naturalName(documentName(a),documentName(b)));
        sorted.forEach((uri: string) => images.push({ name: documentName(uri),read: async (): Promise<ArrayBuffer> => {
          const file = fs.openSync(uri,fs.OpenMode.READ_ONLY);
          try { const input = this.input(file.fd); if (input.size < 1 || input.size > ComicArchive.MAX_IMAGE) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'每张图片最大32MiB'); } return input.read(0,input.size); } finally { fs.closeSync(file); }
        } }));
      }
      const pages: DownloadedPage[] = []; const epoch = Date.now().toString(); let totalBytes = 0;
      for (let i = 0; i < images.length; i++) {
        checkCall(ctx); if (await this.files.freeBytes() < 234881024) { throw new AppError(ErrorCode.STORAGE_FULL,'导入需要至少224MiB剩余空间'); }
        const key = taskId.replace(/-/g,'') + '_' + epoch + i.toString().padStart(4,'0');
        const bytes = await images[i].read(); totalBytes += bytes.byteLength;
        if (totalBytes > ComicArchive.MAX_TOTAL) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'单章图片总量最大512MiB'); }
        checkCall(ctx); const pin = FilePins.pin(this.files.localPath(key)); created.push(key);
        let verified: VerifiedImage | undefined = undefined;
        try { await this.files.writeStream(key,async (sink) => { await sink.write(bytes); },async (path: string) => { verified = await new FileVerifier().verify(path,ctx); }); }
        finally { pin(); }
        if (!verified) { throw new AppError(ErrorCode.CORRUPT_FILE,'本地图像没有通过校验'); }
        const image = verified as VerifiedImage;
        pages.push({ taskId: taskId,pageKey: await payloadDigest(JSON.stringify([images[i].name,image.digest])),ordinal: i,fileKey: key,bytes: image.bytes,width: image.width,height: image.height,digest: image.digest });
        progress(i + 1,images.length);
      }
      const ruleKey = await payloadDigest(JSON.stringify(pages.map((page: DownloadedPage) => page.pageKey))); const manifest = new ManifestCodec().encode(ruleKey,pages.map((page: DownloadedPage) => page.pageKey));
      checkCall(ctx);
      await this.db.transaction(async (db) => {
        checkCall(ctx); const now = Date.now();
        const current = await db.rows('SELECT id FROM downloads WHERE chapter_id=?',[chapterId],(row) => row.getString(0));
        if (current.length && current[0] !== taskId || oldKeys.some((key: string) => FilePins.inUse(this.files.localPath(key)))) { throw new AppError(ErrorCode.CONFLICT,'章节状态已改变，请重新导入'); }
        await db.run('INSERT OR IGNORE INTO manga(id,source_id,remote_id,locator,title,description,tags,favorite,updated_at) VALUES(?,?,?,?,?,?,?,1,?)',[mangaId,LOCAL_SOURCE,book,'/local/' + mangaId,book,'本地导入漫画','["本地"]',now]);
        await db.run('UPDATE manga SET favorite=1,updated_at=? WHERE id=?',[now,mangaId]);
        const ordinal = await db.rows('SELECT COALESCE(MAX(ordinal),-1)+1 FROM chapters WHERE manga_id=?',[mangaId],(row) => row.getLong(0));
        await db.run('INSERT OR IGNORE INTO chapters(id,manga_id,source_id,remote_id,locator,title,ordinal,active) VALUES(?,?,?,?,?,?,?,1)',[chapterId,mangaId,LOCAL_SOURCE,chapter,'/local/' + chapterId,chapter,ordinal[0]]);
        await db.run('INSERT OR IGNORE INTO downloads(id,chapter_id,source_id,state,desired_state,updated_at) VALUES(?,?,?,\'completed\',\'run\',?)',[taskId,chapterId,LOCAL_SOURCE,now]);
        await db.run('DELETE FROM offline_manifests WHERE chapter_id=?',[chapterId]); await db.run('DELETE FROM download_pages WHERE task_id=?',[taskId]);
        for (let i = 0; i < pages.length; i++) { const page = pages[i]; await db.run('INSERT INTO download_pages(task_id,page_key,ordinal,file_key,bytes,width,height,digest) VALUES(?,?,?,?,?,?,?,?)',[taskId,page.pageKey,page.ordinal,page.fileKey,page.bytes,page.width,page.height,page.digest]); }
        checkCall(ctx);
        await db.run('UPDATE downloads SET rule_key=?,manifest=?,state=\'completed\',desired_state=\'run\',error_code=\'\',total=?,completed=?,updated_at=? WHERE id=?',[ruleKey,manifest,pages.length,pages.length,now,taskId]);
        await db.run('INSERT INTO offline_manifests(chapter_id,task_id,total,updated_at) VALUES(?,?,?,?)',[chapterId,taskId,pages.length,now]);
      });
      committed = true; oldKeys.forEach((key: string) => { if (!FilePins.inUse(this.files.localPath(key))) { try { this.files.remove(key); } catch (_) {} } });
      return mangaId;
    } finally {
      try { if (zipFile) { fs.closeSync(zipFile); } }
      finally { if (!committed) { created.forEach((key: string) => { try { this.files.remove(key); } catch (_) {} }); } }
    }
  }
}
