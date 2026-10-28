export class FilePins {
  private static counts: Map<string, number> = new Map();
  static pin(path: string): () => void {
    FilePins.counts.set(path, (FilePins.counts.get(path) || 0) + 1); let released = false;
    return () => {
      if (released) { return; } released = true;
      const count = (FilePins.counts.get(path) || 1) - 1; if (count <= 0) { FilePins.counts.delete(path); } else { FilePins.counts.set(path, count); }
    };
  }
  static inUse(path: string): boolean { return (FilePins.counts.get(path) || 0) > 0; }
}
