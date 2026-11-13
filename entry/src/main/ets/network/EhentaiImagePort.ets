export const EHENTAI_PORT_CHUNK: number = 131072;

// One port per image. Each frame starts with its sequence number and waits for
// an acknowledgement after ArkTS has written the payload to the cache file.
export function ehentaiImagePortScript(page: string,address: string,token: string,limit: number,anonymous: boolean): string {
  return `(() => {
    const page = ${JSON.stringify(page)};
    const address = ${JSON.stringify(address)};
    const token = ${JSON.stringify(token)};
    const limit = ${limit};
    const chunkSize = ${EHENTAI_PORT_CHUNK};
    if (location.href !== page) return 'wrong-page';
    const receive = async (event) => {
      if (event.data !== token || event.ports.length !== 1) return;
      window.removeEventListener('message', receive);
      const port = event.ports[0];
      const img = document.querySelector('img#img');
      if (location.href !== page || !img || (img.currentSrc || img.src) !== address) {
        port.postMessage('changed');
        return;
      }
      port.postMessage('ready');
      const controller = new AbortController();
      let response;
      try {
        response = await fetch(address, { mode: 'cors', credentials: '${anonymous ? 'same-origin' : 'include'}', redirect: 'manual', signal: controller.signal });
      } catch (_) {
        const mayBeBlocked = location.href === page && (img.currentSrc || img.src) === address;
        port.postMessage(mayBeBlocked ? 'unreadable' : 'network');
        return;
      }
      if (response.type === 'opaqueredirect') { port.postMessage('redirect'); return; }
      if (response.status !== 200) { port.postMessage('http:' + response.status); return; }
      if (response.url !== address) { port.postMessage('redirect'); return; }
      if (Number(response.headers.get('content-length')) > limit) {
        controller.abort();
        port.postMessage('limit');
        return;
      }
      if (!response.body) { port.postMessage('format'); return; }
      const type = (response.headers.get('content-type') || '').split(';', 1)[0].trim().toLowerCase();
      if (type && !['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'application/octet-stream'].includes(type)) {
        port.postMessage('format');
        return;
      }
      const reader = response.body.getReader();
      let bytes = 0;
      let sequence = 0;
      try {
        while (true) {
          const part = await reader.read();
          if (part.done) break;
          bytes += part.value.byteLength;
          if (bytes > limit) {
            controller.abort();
            port.postMessage('limit');
            return;
          }
          for (let offset = 0; offset < part.value.byteLength; offset += chunkSize) {
            const data = part.value.subarray(offset, offset + chunkSize);
            const frame = new ArrayBuffer(data.byteLength + 4);
            new DataView(frame).setUint32(0, sequence);
            new Uint8Array(frame, 4).set(data);
            try {
              await new Promise((resolve, reject) => {
                port.onmessage = (ack) => ack.data === 'ack:' + sequence ? resolve() : reject();
                port.onmessageerror = reject;
                port.postMessage(frame);
              });
            } catch (_) { port.postMessage('protocol'); return; }
            sequence++;
          }
        }
        port.postMessage('end:' + bytes);
      } catch (_) {
        port.postMessage('network');
      } finally {
        reader.cancel().catch(() => {});
      }
    };
    window.addEventListener('message', receive);
    return token;
  })()`;
}
