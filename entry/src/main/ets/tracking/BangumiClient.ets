import { rcp } from '@kit.RemoteCommunicationKit';
import { util } from '@kit.ArkTS';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { JsonExtractor, JsonNode } from '../parsing/JsonExtractor';
export class BangumiClient {
  async request(path: string,token: string,body: string = ''): Promise<JsonNode> {
    if (!/^\/v0\/(me|subjects\/[1-9][0-9]*|users\/-\/collections\/[1-9][0-9]*)$/.test(path) || /[\r\n]/.test(token)) { throw new AppError(ErrorCode.POLICY_DENIED,'Tracking 请求参数无效'); }
    const session = rcp.createSession();
    const headers: rcp.RequestHeaders = { 'User-Agent': 'HS-Mihon/0.8 (HarmonyOS native reader)','Accept': 'application/json','Content-Type': 'application/json' };
    if (token) { headers['Authorization'] = 'Bearer ' + token; }
    const request = new rcp.Request('https://api.bgm.tv' + path,body ? 'POST' : 'GET',headers,body || undefined);
    const chunks: Uint8Array[] = []; let size = 0; let exceeded = false;
    request.configuration = { security: { remoteValidation: 'system' },transfer: { autoRedirect: false,timeout: { connectMs: 10000,transferMs: 20000 } },tracing: { httpEventsHandler: {
      onDataReceive: (data: ArrayBuffer): void => { size += data.byteLength; if (size > 1048576) { exceeded = true; session.cancel(request); return; } chunks.push(new Uint8Array(data)); }
    } } };
    try {
      const response = await session.fetch(request);
      if (exceeded) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'Tracking 响应过大'); }
      if (response.statusCode === 401 || response.statusCode === 403) { throw new AppError(ErrorCode.AUTH_REQUIRED,'Bangumi 授权无效或缺少收藏写权限'); }
      if (response.statusCode < 200 || response.statusCode >= 300) { throw new AppError(ErrorCode.HTTP_SERVER,'Bangumi HTTP ' + response.statusCode.toString() + '，待同步内容保留'); }
      if (!size) { return new JsonNode('object'); }
      const bytes = new Uint8Array(size); let offset = 0; chunks.forEach((chunk: Uint8Array) => { bytes.set(chunk,offset); offset += chunk.length; });
      return new JsonExtractor().parse(util.TextDecoder.create('utf-8',{ fatal: true }).decodeToString(bytes));
    } catch (error) { if (error instanceof AppError) { throw error; } throw new AppError(ErrorCode.NETWORK_ERROR,'Bangumi 连接失败，待同步内容保留'); }
    finally { session.close(); }
  }
}
