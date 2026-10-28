export class CancelScope {
  private stopped: boolean = false;
  private listeners: (() => void)[] = [];

  get cancelled(): boolean { return this.stopped; }

  subscribe(listener: () => void): () => void {
    if (this.stopped) {
      listener();
      return () => {};
    }
    this.listeners.push(listener);
    return () => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) { this.listeners.splice(index, 1); }
    };
  }

  cancel(): void {
    if (this.stopped) { return; }
    this.stopped = true;
    const pending = this.listeners.slice();
    this.listeners = [];
    pending.forEach((listener: () => void) => { try { listener(); } catch (_) { /* Notify every consumer even if one native cancellation fails. */ } });
  }
}
