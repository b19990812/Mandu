import { ChapterPageSource, PageRef, SourceRef } from '../model/SourceTypes';
import { CallContext } from '../model/RequestTypes';
import { Transport } from '../network/Transport';
import { FileStore } from '../storage/FileStore';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { checkCall, requireHttpSuccess } from '../source/SourceHttp';
import { FileVerifier, VerifiedImage } from './FileVerifier';

export async function transferAsset(files: FileStore,key: string,source: ChapterPageSource,chapter: SourceRef,page: PageRef,transport: Transport,ctx: CallContext,maxBytes: number,attempts: number = 3): Promise<VerifiedImage> {
  let refresh = false;
  for (let attempt = 0; attempt < Math.max(1,Math.min(3,attempts)); attempt++) {
    checkCall(ctx); let verified: VerifiedImage | undefined = undefined;
    try {
      const image = await source.resolveImage(chapter,page,refresh,ctx);
      if (image.encoding) { throw new AppError(ErrorCode.POLICY_DENIED,'不支持此图片编码'); }
      await files.writeStream(key,async (sink) => {
        const response = await transport.streamToFile({ sourceId: source.id,url: image.url,headers: image.headers,maxBytes: maxBytes,responseKind: 'image' },ctx,sink); requireHttpSuccess(response);
      },async (part: string) => { verified = await new FileVerifier().verify(part,ctx); });
      checkCall(ctx); return verified!;
    } catch (error) {
      checkCall(ctx);
      if (!(error instanceof AppError) || attempt + 1 >= attempts) { throw error as Error; }
      if ([ErrorCode.ACCESS_DENIED,ErrorCode.AUTH_REQUIRED,ErrorCode.IMAGE_EXPIRED].indexOf(error.code) >= 0 && !refresh) { refresh = true; continue; }
      if ([ErrorCode.NETWORK_ERROR,ErrorCode.TIMEOUT,ErrorCode.RATE_LIMITED,ErrorCode.HTTP_SERVER].indexOf(error.code) < 0) { throw error; }
    }
  }
  throw new AppError(ErrorCode.NETWORK_ERROR,'图像重试预算已耗尽');
}
