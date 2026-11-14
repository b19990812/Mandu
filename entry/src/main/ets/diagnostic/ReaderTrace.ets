import { util } from '@kit.ArkTS';
import { FileStore } from '../storage/FileStore';
import { ReaderTraceContext } from '../model/RequestTypes';

// Trace fields are limited to safe identifiers, fixed stage names, and numeric timing data.
export interface ReaderTraceEntry {
  sequence: number;
  timestamp: number;
  sessionId: string;
  operationId: string;
  sourceId: string;
  pageIndex: number;
  role: string;
  partIndex: number;
  stage: string;
  durationMs: number;
  outcome: string;
  cacheTier: string;
  count: number;
  bytes: number;
  metrics: number[];
}

// A bounded in-memory trace avoids file I/O on the measured reader path. The
// snapshot is persisted when the reader closes and can be searched in the lab.
export class ReaderTrace {
  private static readonly LIMIT: number = 1500;
  private static readonly CONTEXT_LIMIT: number = 4096;
  private static entries: ReaderTraceEntry[] = [];
  private static entryCount: number = 0;
  private static nextIndex: number = 0;
  private static contexts: Map<string,ReaderTraceContext> = new Map();
  private static contextKeys: string[] = [];
  private static files?: FileStore;
  private static filesDir: string = '';
  private static persistedLoaded: boolean = false;
  private static sequence: number = 0;
  private static pendingWrite: Promise<void> = Promise.resolve();

  static initialize(filesDir: string): void {
    if (!ReaderTrace.filesDir && filesDir) { ReaderTrace.filesDir = filesDir; }
  }

  private static ensureFiles(): FileStore | undefined {
    if (ReaderTrace.files) { return ReaderTrace.files; }
    if (!ReaderTrace.filesDir) { return undefined; }
    try { ReaderTrace.files = new FileStore(ReaderTrace.filesDir,'reader_trace'); }
    catch (_) { /* Diagnostics must never prevent the reader from opening. */ }
    return ReaderTrace.files;
  }

  static loadPersisted(): void {
    if (ReaderTrace.persistedLoaded) { return; }
    ReaderTrace.persistedLoaded = true;
    const files = ReaderTrace.ensureFiles(); if (!files) { return; }
    try {
      const stored = files.readText('events',2097152); if (!stored) { return; }
      const parsed = JSON.parse(stored) as ReaderTraceEntry[]; if (!Array.isArray(parsed)) { return; }
      const merged: ReaderTraceEntry[] = [];
      parsed.forEach((entry: ReaderTraceEntry) => {
        if (entry && typeof entry.sequence === 'number' && typeof entry.timestamp === 'number' &&
          typeof entry.stage === 'string' && typeof entry.durationMs === 'number' &&
          typeof entry.sessionId === 'string' && typeof entry.operationId === 'string') {
          if (!Array.isArray(entry.metrics)) { entry.metrics = []; }
          merged.push(entry); ReaderTrace.sequence = Math.max(ReaderTrace.sequence,entry.sequence);
        }
      });
      const current = ReaderTrace.ordered();
      current.forEach((entry: ReaderTraceEntry) => { entry.sequence = ++ReaderTrace.sequence; merged.push(entry); });
      ReaderTrace.entries = merged.slice(-ReaderTrace.LIMIT);
      ReaderTrace.entryCount = ReaderTrace.entries.length;
      ReaderTrace.nextIndex = ReaderTrace.entryCount >= ReaderTrace.LIMIT ? 0 : ReaderTrace.entryCount;
    } catch (_) { /* Diagnostics must never prevent the reader from opening. */ }
  }

  static newSessionId(): string { return util.generateRandomUUID().replace(/-/g, '').substring(0, 16); }

  static context(sessionId: string, sourceId: string, pageIndex: number, role: string): ReaderTraceContext {
    const context: ReaderTraceContext = { sessionId: sessionId, operationId: util.generateRandomUUID().replace(/-/g, '').substring(0, 16),
      sourceId: sourceId, pageIndex: pageIndex, role: role, partIndex: 0, startedAt: Date.now() };
    ReaderTrace.registerContext(context);
    return context;
  }

  static registerContext(context: ReaderTraceContext): void {
    if (!ReaderTrace.contexts.has(context.operationId)) {
      ReaderTrace.contextKeys.push(context.operationId);
      while (ReaderTrace.contextKeys.length > ReaderTrace.CONTEXT_LIMIT) {
        const oldest = ReaderTrace.contextKeys.shift(); if (oldest) { ReaderTrace.contexts.delete(oldest); }
      }
    }
    ReaderTrace.contexts.set(context.operationId,context);
  }

  static resolve(operationId: string): ReaderTraceContext | undefined { return ReaderTrace.contexts.get(operationId); }

  static withSource(context: ReaderTraceContext | undefined, sourceId: string): ReaderTraceContext | undefined {
    if (!context) { return undefined; }
    return { sessionId: context.sessionId, operationId: context.operationId, sourceId: sourceId,
      pageIndex: context.pageIndex, role: context.role, partIndex: context.partIndex, startedAt: context.startedAt };
  }

  static withPart(context: ReaderTraceContext | undefined, partIndex: number, role?: string): ReaderTraceContext | undefined {
    if (!context) { return undefined; }
    const selectedRole = role || context.role;
    return { sessionId: context.sessionId, operationId: context.operationId + '-p' + partIndex.toString() + '-' + selectedRole,
      sourceId: context.sourceId, pageIndex: context.pageIndex, role: selectedRole, partIndex: partIndex, startedAt: context.startedAt };
  }

  static record(context: ReaderTraceContext | undefined, stage: string, durationMs: number, outcome: string = 'ok',
    cacheTier: string = '', count: number = 0, bytes: number = 0, metrics: number[] = []): void {
    if (!context) { return; }
    try {
      const entry: ReaderTraceEntry = {
        sequence: ++ReaderTrace.sequence, timestamp: Date.now(), sessionId: context.sessionId.substring(0, 32),
        operationId: context.operationId.substring(0, 64), sourceId: context.sourceId.substring(0, 80),
        pageIndex: Math.max(0, Math.floor(context.pageIndex)), role: context.role.substring(0, 24),
        partIndex: Math.max(0, Math.floor(context.partIndex)), stage: stage.substring(0, 48),
        durationMs: Math.max(0, Math.round(Number.isFinite(durationMs) ? durationMs : 0)),
        outcome: outcome.substring(0, 40), cacheTier: cacheTier.substring(0, 24),
        count: Math.max(0, Math.floor(Number.isFinite(count) ? count : 0)),
        bytes: Math.max(0, Math.floor(Number.isFinite(bytes) ? bytes : 0)),
        metrics: metrics.map((value: number) => Number.isFinite(value) ? Math.round(value) : -1)
      };
      if (ReaderTrace.entryCount < ReaderTrace.LIMIT) {
        ReaderTrace.entries.push(entry); ReaderTrace.entryCount++; ReaderTrace.nextIndex = ReaderTrace.entryCount % ReaderTrace.LIMIT;
      } else {
        ReaderTrace.entries[ReaderTrace.nextIndex] = entry; ReaderTrace.nextIndex = (ReaderTrace.nextIndex + 1) % ReaderTrace.LIMIT;
      }
    } catch (_) { /* Instrumentation must never interrupt the measured operation. */ }
  }

  private static ordered(): ReaderTraceEntry[] {
    if (ReaderTrace.entryCount < ReaderTrace.LIMIT || ReaderTrace.nextIndex === 0) { return ReaderTrace.entries.slice(); }
    return ReaderTrace.entries.slice(ReaderTrace.nextIndex).concat(ReaderTrace.entries.slice(0,ReaderTrace.nextIndex));
  }

  static query(keyword: string = '', limit: number = 200): ReaderTraceEntry[] {
    const query = keyword.trim().toLowerCase();
    const maximum = Math.max(1, Math.min(500, Math.floor(limit)));
    const result: ReaderTraceEntry[] = [];
    const ordered = ReaderTrace.ordered();
    for (let index = ordered.length - 1; index >= 0 && result.length < maximum; index--) {
      const entry = ordered[index];
      const searchable = [entry.sessionId, entry.operationId, entry.sourceId, entry.pageIndex.toString(),
        entry.role, entry.partIndex.toString(), entry.stage, entry.outcome, entry.cacheTier, entry.durationMs.toString(),
        entry.count.toString(), entry.bytes.toString()].concat(entry.metrics.map((value: number) => value.toString())).join(' ').toLowerCase();
      if (!query || searchable.indexOf(query) >= 0) { result.push(entry); }
    }
    return result;
  }

  static total(): number { return ReaderTrace.entryCount; }

  static async clear(): Promise<void> {
    ReaderTrace.persistedLoaded = true;
    ReaderTrace.entries = [];
    ReaderTrace.entryCount = 0;
    ReaderTrace.nextIndex = 0;
    ReaderTrace.sequence = 0;
    ReaderTrace.contexts.clear(); ReaderTrace.contextKeys = [];
    try { await ReaderTrace.pendingWrite; } catch (_) { /* Ignore a failed earlier snapshot. */ }
    try { ReaderTrace.ensureFiles()?.remove('events'); } catch (_) { /* Clearing diagnostics is best effort. */ }
  }

  static async flush(): Promise<void> {
    ReaderTrace.loadPersisted();
    const files = ReaderTrace.ensureFiles();
    if (!files) { return; }
    const snapshot = JSON.stringify(ReaderTrace.ordered());
    const write = ReaderTrace.pendingWrite.then(async () => { await files.writeText('events',snapshot); });
    ReaderTrace.pendingWrite = write.catch(() => {});
    try { await write; } catch (_) { /* A full or unavailable diagnostics store must not affect reading. */ }
  }
}
