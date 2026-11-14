import { SourceSiteDefinition } from '../model/SourceSiteTypes';
import { EHENTAI_BASE, EHENTAI_ID } from '../network/EhentaiAccess';

// Identity is independent of hostnames. Native adapters still depend on the site's availability.
export function sourceSiteDefinitions(): SourceSiteDefinition[] {
  return [
    {
      sourceId: 'org.hsmihon.baozi', name: '包子漫画',
      defaultBaseUrl: 'https://www.twmanga.com/'
    },
    {
      sourceId: 'org.hsmihon.copy', name: 'COPY 漫画',
      defaultBaseUrl: 'https://www.mangacopy.com/'
    },
    { sourceId: 'org.hsmihon.baoziplus',name: '包子漫画 Plus',defaultBaseUrl: 'https://www.webmota.com/' },
    { sourceId: 'org.hsmihon.hipmh',name: 'HIP 漫画',defaultBaseUrl: 'https://m.hipmh.com/' },
    { sourceId: 'org.hsmihon.manhuagui',name: '漫画柜',defaultBaseUrl: 'https://www.manhuagui.com/' },
    { sourceId: 'org.hsmihon.manhuaku',name: '漫画库',defaultBaseUrl: 'https://www.manhuaku.com.cn/' },
    { sourceId: 'org.hsmihon.mycomic',name: 'MYCOMIC 我的漫画',defaultBaseUrl: 'https://mycomic.com/' },
    { sourceId: 'org.hsmihon.joyacg',name: 'JoyACG 漫画',defaultBaseUrl: 'https://joyacg.cc/' },
    { sourceId: EHENTAI_ID,name: 'E-Hentai（18+）',defaultBaseUrl: EHENTAI_BASE }
  ];
}
