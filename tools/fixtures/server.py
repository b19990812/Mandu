"""Self-owned HTTP fixtures for P0; not a production backend or website proxy."""
import argparse
import hashlib
import html
import json
import re
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from png_image import make_png

ROOT = Path(__file__).resolve().parents[2]
CATALOG = json.loads((Path(__file__).parent / 'data' / 'catalog.json').read_text(encoding='utf-8'))['manga']
IMAGES = {'page-1.png': (320, 480, 0), 'page-2.png': (320, 480, 1),
          'long-1080.png': (1080, 30000, 0), 'long-2160.png': (2160, 60000, 0)}
MATRIX = {'ordinary.png', 'ordinary.jpg', 'ordinary.webp', 'long_1080.png', 'long_1080.jpg', 'long_webp.webp', 'long_2160.png', 'long_2160.jpg'}

def chapter_image(chapter, page):
    if chapter == 'c2': return '/images/matrix/ordinary.' + ('jpg' if page == 1 else 'webp')
    if chapter == 'c3' and page == 2: return '/images/matrix/long_1080.png'
    if chapter == 'c5': return '/images/matrix/' + ('long_1080.jpg' if page == 1 else 'long_webp.webp')
    if chapter == 'c6' and page == 2: return '/images/matrix/long_2160.png'
    return f'/images/page-{page}.png'


def timestamp() -> str:
    try:
        return datetime.now(ZoneInfo('Asia/Hong_Kong')).isoformat(timespec='seconds')
    except ZoneInfoNotFoundError:
        from datetime import timedelta, timezone
        return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec='seconds')


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, log_file, revision):
        super().__init__(address, Handler)
        self.log_file = log_file
        self.revision = revision
        self.log_lock = threading.Lock()
        self.image_lock = threading.Lock()
        self.images = {}
        self.log_file.parent.mkdir(parents=True, exist_ok=True)
        self.update_listing()

    def update_listing(self):
        listing = ROOT / 'temp' / 'list'
        prefix = '- 路径：temp/fixtures/；'
        text = listing.read_text(encoding='utf-8') if listing.exists() else '# temp 内容清单\n'
        lines = [line for line in text.splitlines() if not line.startswith(prefix)]
        lines.append(prefix + '用途：自有服务请求日志；关联任务：T02；创建/更新时间：' + timestamp() + '；是否可删除：可，设备核验后删除。')
        listing.write_text('\n'.join(lines) + '\n', encoding='utf-8')

    def image(self, name):
        # Known names only. HTTP input never becomes a filesystem path.
        with self.image_lock:
            if name not in self.images:
                self.images[name] = make_png(*IMAGES[name])
            return self.images[name]

    def log_request_record(self, record):
        with self.log_lock:
            with self.log_file.open('a', encoding='utf-8') as stream:
                stream.write(json.dumps(record, ensure_ascii=False) + '\n')
            self.update_listing()


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_args):
        pass  # Do not log raw URLs, query strings, Cookie, or Authorization.

    def send(self, status, body=b'', content_type='application/json; charset=utf-8', headers=None):
        if isinstance(body, str):
            body = body.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)
        self.server.log_request_record({
            'time': timestamp(), 'method': self.command,
            'path': urlsplit(self.path).path, 'status': status, 'bytes': len(body),
            'hasReferer': bool(self.headers.get('Referer')), 'hasCookie': bool(self.headers.get('Cookie')),
            'hasRange': bool(self.headers.get('Range'))
        })

    def json(self, data, status=200, headers=None):
        self.send(status, json.dumps(data, ensure_ascii=False), headers=headers)

    @staticmethod
    def number(query, name, default, upper):
        raw = query.get(name, [str(default)])[0]
        if not raw.isdecimal() or not 1 <= int(raw) <= upper:
            raise ValueError(f'invalid {name}')
        return int(raw)

    @staticmethod
    def batch(items, page):
        # One item per batch deliberately exercises all pagination paths.
        return {'data': {'items': items[page - 1:page], 'nextPage': page + 1 if page < len(items) else None}}

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        try:
            self.route()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass  # Expected when a device cancels or times out.
        except ValueError:
            self.json({'error': 'invalid fixture parameter'}, 400)

    def route(self):
        parsed = urlsplit(self.path)
        path, query = parsed.path, parse_qs(parsed.query, keep_blank_values=True)
        page = self.number(query, 'page', 1, 10000)
        if path == '/health':
            return self.json({'ok': True, 'fixtureVersion': 1, 'revision': self.server.revision})
        if path == '/probe-file':
            return self.send(200, 'hs-mihon fixture stream\n', 'text/plain; charset=utf-8')
        if path == '/fault/slow':
            time.sleep(self.number(query, 'ms', 5000, 30000) / 1000)
            return self.json({'ok': True})
        if path == '/fault/rate-limit':
            return self.json({'error': 'retry later'}, 429, {'Retry-After': '2'})
        if path == '/fault/redirect':
            return self.send(302, headers={'Location': '/fault/redirect-final'})
        if path == '/fault/redirect-final':
            return self.send(302, headers={'Location': '/health'})
        if path == '/fault/cross-host':
            return self.send(302, headers={'Location': 'https://example.invalid/denied'})
        if path == '/fault/loop':
            return self.send(302, headers={'Location': '/fault/loop'})
        if path == '/fault/expired-image':
            return self.json({'error': 'fixture_signature_expired'}, 403)
        if path == '/fault/bad-image':
            return self.send(200, '<html><body>Not an image</body></html>', 'text/html; charset=utf-8')
        if path == '/fault/oversize':
            return self.send(200, b'x' * (2 * 1024 * 1024 + 1), 'text/plain')
        if path == '/fault/range-lie':
            return self.send(206, b'x' * 4096, 'application/octet-stream', {'Content-Range': 'bytes 0-1023/1024'})
        if path == '/fault/range-chunked-lie':
            self.send_response(206)
            self.send_header('Content-Range', 'bytes 0-1023/1024')
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            self.wfile.write(b'1000\r\n' + b'x' * 4096 + b'\r\n0\r\n\r\n')
            self.wfile.flush()
            self.close_connection = True
            self.server.log_request_record({'time': timestamp(), 'method': self.command, 'path': path,
                                            'status': 206, 'bytes': 4096,
                                            'hasReferer': bool(self.headers.get('Referer')),
                                            'hasCookie': bool(self.headers.get('Cookie')),
                                            'hasRange': bool(self.headers.get('Range'))})
            return
        if path.startswith('/images/') and path[8:] in IMAGES:
            return self.send_image(path[8:], query)
        if path.startswith('/images/matrix/') and path[15:] in MATRIX:
            filename = path[15:]
            data = (ROOT / 'entry/src/main/resources/rawfile/image-matrix' / filename).read_bytes()
            return self.send(200, data, 'image/jpeg' if filename.endswith('.jpg') else 'image/webp' if filename.endswith('.webp') else 'image/png')
        if path.startswith('/api/'):
            return self.api(path, query, page)
        return self.html_page(path, query, page)

    def api(self, path, query, page):
        if path == '/api/search':
            keyword = query.get('q', [''])[0].casefold()
            items = [{'id': manga['id'], 'title': manga['title'], 'url': '/manga/' + manga['id'],
                      'cover': '/images/page-1.png'} for manga in CATALOG if keyword in manga['title'].casefold()]
            result = self.batch(items, page)
            if self.server.revision == 2:
                result['data']['results'] = result['data'].pop('items')
            return self.json(result)
        match = re.fullmatch(r'/api/manga/(m[12])(/chapters)?', path)
        if match:
            manga = next(item for item in CATALOG if item['id'] == match[1])
            if not match[2]:
                return self.json({'data': {'id': manga['id'], 'title': manga['title'],
                                         'url': '/manga/' + manga['id'], 'description': manga['description']}})
            items = [{'id': chapter, 'title': f'第{index + 1}话', 'url': '/chapter/' + chapter, 'order': index}
                     for index, chapter in enumerate(manga['chapters'])]
            return self.json(self.batch(items, page))
        match = re.fullmatch(r'/api/chapter/(c[1-6])/pages', path)
        if match:
            items = [{'id': f'{match[1]}-p{index}', 'url': chapter_image(match[1], index)} for index in (1, 2)]
            return self.json(self.batch(items, page))
        self.json({'error': 'not found'}, 404)

    @staticmethod
    def next_link(path, page, count, query):
        if page >= count:
            return ''
        params = {key: values[0] for key, values in query.items()}
        params['page'] = str(page + 1)
        return '<a class="next" href="' + html.escape(path + '?' + urlencode(params), quote=True) + '">下一页</a>'

    def html_page(self, path, query, page):
        content = None
        if path == '/search':
            keyword = query.get('q', [''])[0].casefold()
            matches = [manga for manga in CATALOG if keyword in manga['title'].casefold()]
            css_class = 'comic' if self.server.revision == 1 else 'comic-card'
            items = ''.join(f'<a class="{css_class}" data-id="{m["id"]}" href="/manga/{m["id"]}">'
                            f'<span class="title">{html.escape(m["title"])}</span></a>'
                            for m in matches[page - 1:page])
            content = '<div id="search-results">' + (items or '<span class="empty">没有结果</span>') + '</div>'
            content += self.next_link(path, page, len(matches), query)
        match = re.fullmatch(r'/manga/(m[12])(/chapters)?', path)
        if match:
            manga = next(item for item in CATALOG if item['id'] == match[1])
            if not match[2]:
                content = f'<h1 class="title">{html.escape(manga["title"])}</h1><p class="summary">{manga["description"]}</p>'
            else:
                items = ''.join(f'<a class="chapter" data-id="{chapter}" data-order="{index}" '
                                f'href="/chapter/{chapter}">第{index + 1}话</a>'
                                for index, chapter in enumerate(manga['chapters']) if index == page - 1)
                content = '<div id="chapters">' + (items or '<span class="empty">没有章节</span>') + '</div>'
                content += self.next_link(path, page, len(manga['chapters']), query)
        match = re.fullmatch(r'/chapter/(c[1-6])', path)
        if match:
            image = f'<img data-id="{match[1]}-p{page}" data-src="{chapter_image(match[1], page)}">' if page <= 2 else ''
            content = '<div id="reader">' + (image or '<span class="empty">没有图片</span>') + '</div>'
            content += self.next_link(path, page, 2, query)
        if content is None:
            return self.json({'error': 'not found'}, 404)
        self.send(200, '<!doctype html><html><head><meta charset="utf-8"></head><body>' + content + '</body></html>',
                  'text/html; charset=utf-8')

    def send_image(self, name, query):
        data = self.server.image(name)
        headers = {'ETag': '"' + hashlib.sha256(data).hexdigest() + '"'}
        enabled = query.get('range', ['on'])[0] != 'off'
        if enabled:
            headers['Accept-Ranges'] = 'bytes'
        requested = self.headers.get('Range')
        if requested and enabled:
            match = re.fullmatch(r'bytes=(\d+)-(\d*)', requested)
            if not match or int(match[1]) >= len(data):
                return self.send(416, headers={'Content-Range': f'bytes */{len(data)}'})
            start = int(match[1])
            end = min(int(match[2]) if match[2] else len(data) - 1, len(data) - 1)
            if end < start:
                return self.send(416, headers={'Content-Range': f'bytes */{len(data)}'})
            headers['Content-Range'] = f'bytes {start}-{end}/{len(data)}'
            return self.send(206, data[start:end + 1], 'image/png', headers)
        self.send(200, data, 'image/png', headers)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1', help='Use 0.0.0.0 explicitly for a phone on the LAN')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--revision', type=int, choices=(1, 2), default=1)
    args = parser.parse_args()
    logs = ROOT / 'temp' / 'fixtures'
    logs.mkdir(parents=True, exist_ok=True)
    log_file = logs / 'requests.jsonl'
    server = FixtureServer((args.host, args.port), log_file, args.revision)
    print(f'Fixture v{args.revision} ready: http://{args.host}:{args.port}/health', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
