import { AppError, ErrorCode } from '../model/ErrorTypes';
import { CallContext } from '../model/RequestTypes';
import { TransportResponse } from '../network/Transport';

export function checkCall(ctx: CallContext): void {
  if (ctx.cancel.cancelled) { throw new AppError(ErrorCode.CANCELLED, '操作已取消'); }
  if (Date.now() >= ctx.deadlineMs) { throw new AppError(ErrorCode.TIMEOUT, '操作已超时'); }
}

export function requireHttpSuccess(response: TransportResponse): void {
  const status = response.statusCode;
  if (status >= 200 && status < 300) { return; }
  if (status === 401) { throw new AppError(ErrorCode.AUTH_REQUIRED, '站点要求登录（401）'); }
  if (status === 403) { throw new AppError(ErrorCode.ACCESS_DENIED, '站点拒绝访问（403），请稍后重试或检查网址'); }
  if (status === 404) { throw new AppError(ErrorCode.NOT_FOUND, '章节或资源不存在（404）'); }
  if (status === 429) { throw new AppError(ErrorCode.RATE_LIMITED, '站点限制请求频率（429），请稍后重试'); }
  throw new AppError(ErrorCode.HTTP_SERVER, '站点返回HTTP ' + status.toString());
}

