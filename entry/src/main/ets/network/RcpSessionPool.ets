import { rcp } from '@kit.RemoteCommunicationKit';

interface SessionEntry {
  session: rcp.Session;
  active: number;
  idleTimer: number;
}

export interface RcpSessionLease {
  session: rcp.Session;
  release: () => void;
}

export class RcpSessionPool {
  private static readonly CAPACITY: number = 16;
  private static readonly IDLE_MS: number = 30000;
  private static readonly entries: Map<string, SessionEntry> = new Map();

  static acquire(key: string): RcpSessionLease {
    let entry = RcpSessionPool.entries.get(key);
    if (!entry) {
      if (RcpSessionPool.entries.size >= RcpSessionPool.CAPACITY) {
        for (const candidate of RcpSessionPool.entries) {
          if (candidate[1].active === 0) {
            RcpSessionPool.remove(candidate[0], candidate[1]);
            break;
          }
        }
      }
      const session = rcp.createSession();
      if (RcpSessionPool.entries.size >= RcpSessionPool.CAPACITY) {
        const temporary: RcpSessionLease = { session: session, release: () => RcpSessionPool.close(session) };
        return temporary;
      }
      entry = { session: session, active: 0, idleTimer: -1 };
    }
    const leased = entry;
    clearTimeout(leased.idleTimer);
    leased.idleTimer = -1;
    leased.active++;
    RcpSessionPool.entries.delete(key);
    RcpSessionPool.entries.set(key, leased);
    const lease: RcpSessionLease = {
      session: leased.session,
      release: () => {
        leased.active--;
        if (leased.active === 0) {
          leased.idleTimer = setTimeout(() => RcpSessionPool.remove(key, leased), RcpSessionPool.IDLE_MS);
        }
      }
    };
    return lease;
  }

  private static remove(key: string, entry: SessionEntry): void {
    if (entry.active !== 0 || RcpSessionPool.entries.get(key) !== entry) { return; }
    RcpSessionPool.entries.delete(key);
    clearTimeout(entry.idleTimer);
    RcpSessionPool.close(entry.session);
  }

  private static close(session: rcp.Session): void {
    try { session.close(); } catch (_) { /* The idle connection may already be closed by the SDK. */ }
  }
}
