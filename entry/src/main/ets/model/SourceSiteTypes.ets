export interface SourceSiteDefinition {
  sourceId: string;
  name: string;
  defaultBaseUrl: string;
}

export interface SourceSiteSetting {
  sourceId: string;
  baseUrl: string;
  previousBaseUrl: string;
  revision: number;
  updatedAt: number;
  copyProtocol?: string;
  copyApiBaseUrl?: string;
}

export interface SourceSiteSnapshot {
  schemaVersion: number;
  revision: number;
  sites: SourceSiteSetting[];
}

export interface SourceSiteView {
  sourceId: string;
  name: string;
  baseUrl: string;
  defaultBaseUrl: string;
  previousBaseUrl: string;
  revision: number;
  copyProtocol?: string;
  copyApiBaseUrl?: string;
}

export interface SourceSiteAccess {
  sourceId: string;
  baseUrl: string;
  allowedHosts: string[];
  revision: number;
  copyProtocol?: string;
  copyApiBaseUrl?: string;
}

export interface SourceSiteSettingsStore {
  read(): Promise<SourceSiteSnapshot>;
  commit(next: SourceSiteSnapshot, expectedRevision: number): Promise<void>;
}
