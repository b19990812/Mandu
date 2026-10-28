import { SourceState } from '../model/SourcePackageTypes';

// In-process notifications only; durable truth always comes from the repository.
export class SourceChanges {
  private static listeners: Map<string, ((state: SourceState) => void)[]> = new Map();
  private static all: ((state: SourceState) => void)[] = [];
  private static invalidations: Map<string,(() => void)[]> = new Map();
  static watchAddress(id: string,listener: () => void): () => void {
    const items = SourceChanges.invalidations.get(id) || []; items.push(listener); SourceChanges.invalidations.set(id,items);
    return () => { const index = items.indexOf(listener); if (index >= 0) { items.splice(index,1); } if (items.length === 0) { SourceChanges.invalidations.delete(id); } };
  }
  static addressChanged(id: string): void { (SourceChanges.invalidations.get(id) || []).slice().forEach((listener) => { try { listener(); } catch (_) {} }); }
  static subscribeAll(listener: (state: SourceState) => void): () => void {
    SourceChanges.all.push(listener); return () => { const i = SourceChanges.all.indexOf(listener); if (i >= 0) { SourceChanges.all.splice(i, 1); } };
  }
  static subscribe(id: string, listener: (state: SourceState) => void): () => void {
    const list = SourceChanges.listeners.get(id) || []; list.push(listener); SourceChanges.listeners.set(id, list);
    return () => { const i = list.indexOf(listener); if (i >= 0) { list.splice(i, 1); } if (list.length === 0) { SourceChanges.listeners.delete(id); } };
  }
  static publish(state: SourceState): void {
    (SourceChanges.listeners.get(state.id) || []).slice().forEach((listener) => { try { listener(state); } catch (_) { /* A subscriber cannot undo an already committed update. */ } });
    SourceChanges.all.slice().forEach((listener) => { try { listener(state); } catch (_) { /* Durable state remains authoritative. */ } });
  }
}
