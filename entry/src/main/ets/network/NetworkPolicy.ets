import { connection } from '@kit.NetworkKit';
export class NetworkPolicy {
  static async allowed(wifiOnly: boolean): Promise<boolean> {
    try {
      if (!await connection.hasDefaultNet()) { return false; }
      if (!wifiOnly) { return true; }
      const capabilities = await connection.getNetCapabilities(await connection.getDefaultNet());
      return capabilities.bearerTypes.indexOf(connection.NetBearType.BEARER_WIFI) >= 0;
    } catch (_) { return false; }
  }
}
