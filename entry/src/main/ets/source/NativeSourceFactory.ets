import { Source } from '../model/SourceTypes';
import { SourceSiteAccess } from '../model/SourceSiteTypes';
import { Transport } from '../network/Transport';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { BaoziSource, BAOZI_COVER_HOSTS } from './adapters/BaoziSource';
import { baoziPageHosts, BAOZI_IMAGE_HOSTS } from './adapters/BaoziChapterSource';
import { CopySource, COPY_IMAGE_HOSTS } from './adapters/CopySource';
import { COPY_COVER_HOSTS } from './discovery/CopyDiscovery';
import { HipSource, HIP_HOSTS } from './adapters/HipSource';
import { VomicSource, VOMIC_HOSTS } from './adapters/VomicSource';
import { url } from '@kit.ArkTS';
import { CopyApiSource } from './adapters/CopyApiSource';
import { usesCopyApi, copyApiBase } from './CopyAccess';
import { COPY_API_IMAGE_HOSTS } from './adapters/CopyApiFormat';
import { ManhuaguiSource } from './adapters/ManhuaguiSource';
import { MANHUAGUI_ASSET_HOSTS } from './adapters/ManhuaguiReaderData';
import { ManhuakuSource } from './adapters/ManhuakuSource';
import { MANHUAKU_ASSET_HOSTS } from './adapters/ManhuakuFormat';
import { MyComicSource } from './adapters/MyComicSource';
import { MYCOMIC_ASSET_HOSTS } from './adapters/MyComicFormat';
import { JoyAcgSource, JOY_IMAGE_HOSTS, JOY_COVER_HOSTS } from './adapters/JoyAcgSource';
import { EHENTAI_ID } from '../network/EhentaiAccess';
import { EhentaiSource } from './adapters/EhentaiSource';

export function nativeHosts(site: SourceSiteAccess): string[] {
  let hosts: string[];
  switch (site.sourceId) {
    case 'org.hsmihon.baozi': case 'org.hsmihon.baoziplus': hosts = baoziPageHosts(site).concat(BAOZI_IMAGE_HOSTS,BAOZI_COVER_HOSTS); break;
    case 'org.hsmihon.copy': hosts = site.allowedHosts.concat(usesCopyApi(site) ? COPY_API_IMAGE_HOSTS : COPY_IMAGE_HOSTS,COPY_COVER_HOSTS,usesCopyApi(site) ? [new url.URL(copyApiBase(site.copyApiBaseUrl)).hostname] : []); break;
    case 'org.hsmihon.hipmh': hosts = site.allowedHosts.concat(HIP_HOSTS); break;
    case 'org.hsmihon.vomic': hosts = site.allowedHosts.concat(VOMIC_HOSTS); break;
    case 'org.hsmihon.manhuagui': hosts = site.allowedHosts.concat(MANHUAGUI_ASSET_HOSTS); break;
    case 'org.hsmihon.manhuaku': hosts = site.allowedHosts.concat(MANHUAKU_ASSET_HOSTS); break;
    case 'org.hsmihon.mycomic': hosts = site.allowedHosts.concat(MYCOMIC_ASSET_HOSTS); break;
    case 'org.hsmihon.joyacg': hosts = site.allowedHosts.concat(JOY_IMAGE_HOSTS,JOY_COVER_HOSTS); break;
    case EHENTAI_ID: hosts = site.allowedHosts.concat('api.e-hentai.org','ehgt.org','hath.network'); break;
    default: throw new AppError(ErrorCode.UNSUPPORTED,'此源尚无本项目适配器');
  }
  return hosts.filter((host: string,index: number,all: string[]) => all.indexOf(host) === index);
}
export function createNativeSource(site: SourceSiteAccess,transport: Transport): Source {
  switch (site.sourceId) {
    case 'org.hsmihon.baozi': case 'org.hsmihon.baoziplus': return new BaoziSource(site,transport);
    case 'org.hsmihon.copy': return usesCopyApi(site) ? new CopyApiSource(site,transport) : new CopySource(site,transport);
    case 'org.hsmihon.hipmh': return new HipSource(site,transport);
    case 'org.hsmihon.vomic': return new VomicSource(site,transport);
    case 'org.hsmihon.manhuagui': return new ManhuaguiSource(site,transport);
    case 'org.hsmihon.manhuaku': return new ManhuakuSource(site,transport);
    case 'org.hsmihon.mycomic': return new MyComicSource(site,transport);
    case 'org.hsmihon.joyacg': return new JoyAcgSource(site,transport);
    case EHENTAI_ID: return new EhentaiSource(site,transport);
    default: throw new AppError(ErrorCode.UNSUPPORTED,'此源尚无本项目适配器');
  }
}
