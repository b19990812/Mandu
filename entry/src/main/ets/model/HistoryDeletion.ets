import { AppError, ErrorCode } from './ErrorTypes';

export interface HistoryDeleteRange { id: string; label: string; durationMs: number; }
export interface HistoryDeleteTarget { mangaId: string; readAt: number; }
export interface HistoryDeletePlan { range: string; from: number; before: number; targets: HistoryDeleteTarget[]; }
export const HISTORY_DELETE_RANGES: HistoryDeleteRange[] = [
  { id: 'minute',label: '最近1分钟',durationMs: 60000 },
  { id: 'hour',label: '最近1小时',durationMs: 3600000 },
  { id: 'day',label: '最近1天',durationMs: 86400000 },
  { id: 'week',label: '最近7天',durationMs: 604800000 },
  { id: 'month',label: '最近1个月（30天）',durationMs: 2592000000 },
  { id: 'all',label: '全部历史',durationMs: 0 }
];
export function historyDeleteFrom(range: string,before: number): number {
  const choice = HISTORY_DELETE_RANGES.find((item: HistoryDeleteRange) => item.id === range);
  if (!choice || !Number.isSafeInteger(before) || before < 1) { throw new AppError(ErrorCode.CONFIG_INVALID,'历史删除时间范围无效'); }
  return choice.durationMs ? Math.max(1,before - choice.durationMs) : 1;
}
