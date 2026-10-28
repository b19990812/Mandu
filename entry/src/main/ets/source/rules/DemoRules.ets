import { RuleDefinition, RuleField } from './RuleTypes';

function jsonField(name: string, from: string, transforms: string[] = [], required: boolean = true): RuleField {
  return { name: name, from: from, transforms: transforms, required: required };
}
function htmlField(name: string, selector: string, attribute: string = '', transforms: string[] = []): RuleField {
  return { name: name, selector: selector, attribute: attribute || undefined, transforms: transforms, required: true };
}

export function jsonDemoRule(): RuleDefinition {
  return { id: 'org.example.demo.json', version: 1, format: 'json', operations: [
    { name: 'search', path: '/api/search', query: [{ name: 'q', value: '{{query}}' }, { name: 'page', value: '{{page}}' }],
      items: '$.data.items', nextPath: '$.data.nextPage', fields: [
        jsonField('remoteId', 'id', ['string']), jsonField('title', 'title', ['trim']),
        jsonField('locator', 'url', ['urlAbsolute']), jsonField('cover', 'cover', ['urlAbsolute'], false)] },
    { name: 'details', path: '/api/manga/{{mangaId}}', root: '$.data', fields: [
      jsonField('remoteId', 'id', ['string']), jsonField('title', 'title'),
      jsonField('locator', 'url', ['urlAbsolute']), jsonField('description', 'description', [], false)] },
    { name: 'chapters', path: '/api/manga/{{mangaId}}/chapters', query: [{ name: 'page', value: '{{page}}' }],
      items: '$.data.items', nextPath: '$.data.nextPage', fields: [
        jsonField('remoteId', 'id', ['string']), jsonField('title', 'title'),
        jsonField('locator', 'url', ['urlAbsolute']), jsonField('ordinal', 'order', ['integer'])] },
    { name: 'pages', path: '/api/chapter/{{chapterId}}/pages', query: [{ name: 'page', value: '{{page}}' }],
      items: '$.data.items', nextPath: '$.data.nextPage', fields: [
        jsonField('pageKey', 'id', ['string']), jsonField('imageUrl', 'url', ['urlAbsolute'])] }
  ] };
}

export function htmlDemoRule(): RuleDefinition {
  return { id: 'org.example.demo.html', version: 1, format: 'html', operations: [
    { name: 'search', path: '/search', query: [{ name: 'q', value: '{{query}}' }, { name: 'page', value: '{{page}}' }],
      items: 'a.comic', requiredMarker: '#search-results', emptyMarker: '#search-results .empty', nextSelector: 'a.next', fields: [
        htmlField('remoteId', 'self', 'data-id'), htmlField('title', '.title', '', ['trim']),
        htmlField('locator', 'self', 'href', ['urlAbsolute'])] },
    { name: 'details', path: '/manga/{{mangaId}}', root: 'body', requiredMarker: 'h1.title', fields: [
      htmlField('title', 'h1.title', '', ['trim']), htmlField('description', '.summary')] },
    { name: 'chapters', path: '/manga/{{mangaId}}/chapters', query: [{ name: 'page', value: '{{page}}' }],
      items: '#chapters a.chapter', requiredMarker: '#chapters', emptyMarker: '#chapters .empty', nextSelector: 'a.next', fields: [
        htmlField('remoteId', 'self', 'data-id'), htmlField('title', 'self'),
        htmlField('locator', 'self', 'href', ['urlAbsolute']), htmlField('ordinal', 'self', 'data-order', ['integer'])] },
    { name: 'pages', path: '/chapter/{{chapterId}}', query: [{ name: 'page', value: '{{page}}' }],
      items: '#reader img', requiredMarker: '#reader', emptyMarker: '#reader .empty', nextSelector: 'a.next', fields: [
        htmlField('pageKey', 'self', 'data-id'), htmlField('imageUrl', 'self', 'data-src', ['urlAbsolute'])] }
  ] };
}
