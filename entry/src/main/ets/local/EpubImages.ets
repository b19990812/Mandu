import { util } from '@kit.ArkTS';
import { ArchiveInput, ComicArchive, ComicEntry } from './ComicArchive';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { checkCall } from '../source/SourceHttp';
// Image-only EPUB: resolve OPF spine and XHTML image references, never execute content.
export class EpubImages {
  private readonly archive: ComicArchive = new ComicArchive();
  private attributes(tag: string): Map<string,string> {
    const result: Map<string,string> = new Map(); const expression = /([\w:-]+)\s*=\s*(["'])(.*?)\2/g; let match: RegExpExecArray | null;
    while ((match = expression.exec(tag)) !== null) { result.set(match[1],match[3].replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&apos;/g,"'")); } return result;
  }
  private path(base: string,href: string): string {
    let value = ''; try { value = decodeURIComponent(href.split('#')[0]); } catch (_) { throw new AppError(ErrorCode.CORRUPT_FILE,'EPUB 引用编码无效'); }
    if (!value || /^[a-z][a-z0-9+.-]*:/i.test(value) || value.startsWith('/') || /[\\\u0000-\u001f?]/.test(value)) { throw new AppError(ErrorCode.POLICY_DENIED,'EPUB 不允许外部资源或绝对路径'); }
    const parts = base.split('/'); parts.pop();
    value.split('/').forEach((part: string) => { if (part === '..') { if (!parts.length) { throw new AppError(ErrorCode.POLICY_DENIED,'EPUB 引用越界'); } parts.pop(); } else if (part && part !== '.') { parts.push(part); } });
    return parts.join('/');
  }
  private async text(input: ArchiveInput,entry: ComicEntry | undefined): Promise<string> {
    if (!entry || entry.bytes > 2097152) { throw new AppError(ErrorCode.CORRUPT_FILE,'EPUB 描述文件缺失或过大'); }
    const text = util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(new Uint8Array(await this.archive.image(input,entry)));
    if (/<!DOCTYPE|<!ENTITY/i.test(text)) { throw new AppError(ErrorCode.UNSUPPORTED,'EPUB 外部实体或 DTD 不受支持'); } return text;
  }
  async entries(input: ArchiveInput,ctx: CallContext): Promise<ComicEntry[]> {
    const entries = this.archive.entries(input,true); const byName: Map<string,ComicEntry> = new Map(); entries.forEach((entry: ComicEntry) => byName.set(entry.name,entry));
    const container = await this.text(input,byName.get('META-INF/container.xml'));
    const root = /<(?:[\w-]+:)?rootfile\b[^>]*>/i.exec(container);
    const opfPath = root ? this.attributes(root[0]).get('full-path') || '' : '';
    if (!opfPath || opfPath.split('/').some((part: string) => part === '..')) { throw new AppError(ErrorCode.CORRUPT_FILE,'EPUB 根目录无效'); }
    const opf = await this.text(input,byName.get(opfPath)); const items: Map<string,string> = new Map();
    const tags = opf.match(/<(?:[\w-]+:)?item\b[^>]*>/gi) || [];
    tags.forEach((tag: string) => { const attrs = this.attributes(tag); const id = attrs.get('id') || ''; const href = attrs.get('href') || ''; if (!id || items.has(id)) { throw new AppError(ErrorCode.CORRUPT_FILE,'EPUB 资源身份重复或缺失'); } items.set(id,this.path(opfPath,href)); });
    const spine = opf.match(/<(?:[\w-]+:)?itemref\b[^>]*>/gi) || [];
    if (!spine.length || spine.length > 2000) { throw new AppError(ErrorCode.UNSUPPORTED,'EPUB 阅读顺序缺失或过大'); }
    const result: ComicEntry[] = []; const seen: Set<string> = new Set();
    for (let i = 0; i < spine.length; i++) {
      checkCall(ctx); const path = items.get(this.attributes(spine[i]).get('idref') || '') || '';
      const document = await this.text(input,byName.get(path));
      const images = document.match(/<(?:[\w-]+:)?(?:img|image)\b[^>]*>/gi) || [];
      if (!images.length) { throw new AppError(ErrorCode.UNSUPPORTED,'仅支持漫画图片型 EPUB；文字章节无法转换成漫画页'); }
      images.forEach((tag: string) => {
        const attrs = this.attributes(tag); const name = this.path(path,attrs.get('src') || attrs.get('xlink:href') || attrs.get('href') || '');
        const entry = byName.get(name); if (!entry || !ComicArchive.image(name)) { throw new AppError(ErrorCode.UNSUPPORTED,'EPUB 图片缺失或格式不支持'); }
        if (!seen.has(name)) { seen.add(name); result.push(entry); }
      });
    }
    return result;
  }
}
