export interface SourceVersionKey { version: number; key: string; }
export interface SourceState {
  id: string;
  active: string;
  lastGood: string;
  revision: number;
  enabled: boolean;
  removed: boolean;
  versions: SourceVersionKey[];
}
export interface SourceCatalog { schemaVersion: number; revision: number; entries: SourceState[]; }
export interface SourcePackageStore {
  read(): Promise<SourceCatalog>;
  payload(key: string): Promise<string>;
  commit(catalog: SourceCatalog, expectedRevision: number, payload: string, key: string): Promise<void>;
}
