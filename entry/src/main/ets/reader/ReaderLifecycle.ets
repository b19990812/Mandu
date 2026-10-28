export class ReaderLifecycle {
  private static listeners: Set<(foreground: boolean) => void> = new Set();
  static isForeground: boolean = true;
  static subscribe(change: (foreground: boolean) => void): () => void { ReaderLifecycle.listeners.add(change); return () => { ReaderLifecycle.listeners.delete(change); }; }
  static background(): void { ReaderLifecycle.isForeground = false; ReaderLifecycle.listeners.forEach((change) => change(false)); }
  static foreground(): void { ReaderLifecycle.isForeground = true; ReaderLifecycle.listeners.forEach((change) => change(true)); }
}
