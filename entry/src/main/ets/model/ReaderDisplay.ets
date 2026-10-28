export const READER_MODES: string[] = ['paged','vertical','webtoon','continuous','spread','tap','curl'];
export interface ReaderDisplay { background: string; scale: string; tapZones: string; invertTap: boolean; }
export function defaultReaderDisplay(): ReaderDisplay { return { background: 'dark',scale: 'auto',tapZones: 'sides',invertTap: false }; }
export function stripMode(mode: string): boolean { return mode === 'webtoon' || mode === 'continuous'; }
export function validDisplay(value: ReaderDisplay): boolean { return ['dark','gray','light'].indexOf(value.background) >= 0 && ['auto','width','height'].indexOf(value.scale) >= 0 && ['sides','thirds','menu'].indexOf(value.tapZones) >= 0 && typeof value.invertTap === 'boolean'; }
export function readerBackground(value: string): string { return value === 'light' ? '#F5F3EF' : value === 'gray' ? '#555555' : '#101515'; }
// Logical previous/next remains independent of manga direction; inversion is an explicit preference.
export function tapAction(fraction: number, zones: string, inverted: boolean): number {
  const edge = zones === 'thirds' ? 1 / 3 : zones === 'sides' ? 0.3 : 0;
  const turn: number = fraction < edge ? -1 : fraction > 1 - edge ? 1 : 0; return inverted && turn !== 0 ? -turn : turn;
}
