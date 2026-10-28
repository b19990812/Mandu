import { ReaderDisplay } from './ReaderDisplay';
export const PREFETCH_PAGE_CHOICES: number[] = [2,4,6,10,20];
export const DEFAULT_PREFETCH_PAGES: number = 20;
export interface ReaderPreferences extends ReaderDisplay { mode: string; direction: string; prefetch: boolean; prefetchPages: number; wifiOnly: boolean; cacheMiB: number; autoNext: boolean; preloadNext: boolean; skipRead: boolean; prefetchWifi: boolean; incognito: boolean; }
export function defaultReaderPreferences(): ReaderPreferences { return { mode: 'paged', direction: 'ltr', prefetch: true, prefetchPages: DEFAULT_PREFETCH_PAGES, wifiOnly: false, cacheMiB: 512, autoNext: true,preloadNext: true,skipRead: false,prefetchWifi: false,background: 'dark',scale: 'auto',tapZones: 'sides',invertTap: false,incognito: false }; }
