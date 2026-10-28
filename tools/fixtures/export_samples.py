"""Export self-owned server responses as deterministic native diagnostic fixtures."""
import json
from pathlib import Path
from types import SimpleNamespace
from server import Handler
from png_image import make_png

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'entry/src/main/resources/rawfile/demo-fixtures'


class ExportHandler(Handler):
    def __init__(self, address, revision=1):
        self.path = address
        self.server = SimpleNamespace(revision=revision)
        self.content = b''
        self.status = 0

    def send(self, status, body=b'', content_type='', headers=None):
        self.status = status
        self.content = body.encode('utf-8') if isinstance(body, str) else body


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    paths = [
        '/api/search?q=&page=1', '/api/search?q=&page=2', '/api/search?q=missing&page=1', '/api/manga/m1',
        '/api/manga/m1/chapters?page=1', '/api/manga/m1/chapters?page=2', '/api/manga/m1/chapters?page=3',
        '/api/chapter/c1/pages?page=1', '/api/chapter/c1/pages?page=2',
        '/search?q=&page=1', '/search?q=&page=2', '/search?q=missing&page=1', '/manga/m1',
        '/manga/m1/chapters?page=1', '/manga/m1/chapters?page=2', '/manga/m1/chapters?page=3',
        '/chapter/c1?page=1', '/chapter/c1?page=2'
    ]
    for book in ('m2',):
        paths += [f'/api/manga/{book}', f'/manga/{book}']
        for page in (1, 2, 3):
            paths += [f'/api/manga/{book}/chapters?page={page}', f'/manga/{book}/chapters?page={page}']
    for chapter in ('c2', 'c3', 'c4', 'c5', 'c6'):
        for page in (1, 2):
            paths += [f'/api/chapter/{chapter}/pages?page={page}', f'/chapter/{chapter}?page={page}']
    for revision in (1, 2):
        output = OUTPUT if revision == 1 else OUTPUT / 'v2'
        output.mkdir(parents=True, exist_ok=True)
        manifest = []
        for index, address in enumerate(paths):
            handler = ExportHandler(address, revision)
            handler.route()
            if handler.status != 200:
                raise RuntimeError('Unexpected fixture status: ' + address)
            filename = 'response_' + str(index) + ('.json' if address.startswith('/api/') else '.html')
            (output / filename).write_bytes(handler.content)
            manifest.append({'path': address, 'file': filename})
        (output / 'index.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for number in (1, 2):
        (OUTPUT / f'page_{number}.png').write_bytes(make_png(640, 1024, number))
    print('Exported', len(paths), 'self-owned diagnostic responses')


if __name__ == '__main__':
    main()
