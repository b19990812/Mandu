import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { ComicArchive, naturalName } from './ComicArchive';
import { AppError, ErrorCode } from '../model/ErrorTypes';
export class FolderImages {
  static async list(uri: string): Promise<string[]> {
    const root = new fileUri.FileUri(uri).path.replace(/\/$/,'');
    if (!root.startsWith('/') || !fs.statSync(root).isDirectory()) { throw new AppError(ErrorCode.CONFIG_INVALID,'请选择可读取的文件夹'); }
    const names = await fs.listFile(root,{ recursion: false });
    if (names.length > 10000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'文件夹条目过多，请拆分章节'); }
    const result: string[] = [];
    names.sort(naturalName).forEach((name: string) => {
      if (!ComicArchive.image(name)) { return; }
      if (name === '..' || name.indexOf('/') >= 0 || name.indexOf('\\') >= 0) { throw new AppError(ErrorCode.POLICY_DENIED,'文件名无效'); }
      const path = root + '/' + name; const stat = fs.lstatSync(path);
      if (stat.isSymbolicLink()) { throw new AppError(ErrorCode.POLICY_DENIED,'不导入符号链接'); }
      if (stat.isFile()) { result.push(fileUri.getUriFromPath(path)); }
    });
    if (!result.length || result.length > 2000) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'文件夹需包含1～2000张图片；只导入当前层'); }
    return result;
  }
}
