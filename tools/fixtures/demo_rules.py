"""Publish self-owned data-only packages for the versioned rule protocol."""
import copy
import json
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[2] / 'entry/src/main/resources/rawfile/demo-rules'

def field(location, fmt, *, attr=None, required=True, transforms=()):
    item = {'from' if fmt == 'json' else 'selector': location, 'required': required}
    if fmt == 'html': item.update({'attr': attr} if attr else {'text': True})
    if transforms: item['transforms'] = list(transforms)
    return item

def package(fmt, version):
    def f(location, **kwargs): return field(location, fmt, **kwargs)
    paths = ['/api/search', '/api/manga/{{mangaId}}', '/api/manga/{{mangaId}}/chapters', '/api/chapter/{{chapterId}}/pages'] if fmt == 'json' else ['/search', '/manga/{{mangaId}}', '/manga/{{mangaId}}/chapters', '/chapter/{{chapterId}}']
    fields = [
        {'remoteId': f('id', transforms=['string']), 'title': f('title', transforms=['trim']), 'locator': f('url', transforms=['urlAbsolute']), 'cover': f('cover', required=False, transforms=['urlAbsolute'])},
        {'remoteId': f('id', transforms=['string']), 'title': f('title'), 'locator': f('url', transforms=['urlAbsolute']), 'description': f('description', required=False)},
        {'remoteId': f('id', transforms=['string']), 'title': f('title'), 'locator': f('url', transforms=['urlAbsolute']), 'ordinal': f('order', transforms=['integer'])},
        {'pageKey': f('id', transforms=['string']), 'imageUrl': f('url', transforms=['urlAbsolute'])},
    ]
    if fmt == 'html':
        fields = [
            {'remoteId': f('self', attr='data-id'), 'title': f('.title', transforms=['trim']), 'locator': f('self', attr='href', transforms=['urlAbsolute'])},
            {'title': f('h1.title', transforms=['trim']), 'description': f('.summary')},
            {'remoteId': f('self', attr='data-id'), 'title': f('self'), 'locator': f('self', attr='href', transforms=['urlAbsolute']), 'ordinal': f('self', attr='data-order', transforms=['integer'])},
            {'pageKey': f('self', attr='data-id'), 'imageUrl': f('self', attr='data-src', transforms=['urlAbsolute'])},
        ]
    operations = {}
    for i, name in enumerate(('search', 'details', 'chapters', 'pages')):
        request = {'method': 'GET', 'path': paths[i]}
        if name != 'details': request['query'] = ({'q': '{{query}}', 'page': '{{page}}'} if name == 'search' else {'page': '{{page}}'})
        extract = {'format': fmt, 'fields': fields[i]}
        if fmt == 'json': extract['object' if name == 'details' else 'items'] = '$.data' if name == 'details' else ('$.data.results' if name == 'search' and version == 2 else '$.data.items')
        else:
            extract['object' if name == 'details' else 'items'] = [('a.comic-card' if version == 2 else 'a.comic'), 'body', '#chapters a.chapter', '#reader img'][i]
            extract['requiredMarker'] = ['#search-results', 'h1.title', '#chapters', '#reader'][i]
            if name != 'details': extract['emptyMarker'] = ['#search-results .empty', '', '#chapters .empty', '#reader .empty'][i]
        pagination = {'mode': 'none'} if name == 'details' else ({'mode': 'page', 'start': 1, 'nextPath': '$.data.nextPage'} if fmt == 'json' else {'mode': 'url', 'start': 1, 'nextSelector': 'a.next', 'nextAttr': 'href'})
        operations[name] = {'request': request, 'extract': extract, 'pagination': pagination}
    return {'id': 'org.example.demo.' + fmt, 'name': fmt.upper() + '演示源', 'sourceVersion': version,
            'ruleFormatVersion': 1, 'engineMin': 1, 'engineMax': 1, 'baseUrl': 'https://fixture.invalid/',
            'allowedHosts': ['fixture.invalid'], 'capabilities': ['search', 'details', 'chapters', 'pages'], 'operations': operations}

def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for fmt in ('json', 'html'):
        for version in (1, 2):
            (OUTPUT / f'{fmt}-v{version}.json').write_text(json.dumps(package(fmt, version), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    invalid = copy.deepcopy(package('html', 2)); invalid['sourceVersion'] = 3; invalid['script'] = 'unsupported'
    (OUTPUT / 'invalid-v3.json').write_text(json.dumps(invalid, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Exported 4 valid packages and 1 intentionally invalid package')

if __name__ == '__main__': main()
