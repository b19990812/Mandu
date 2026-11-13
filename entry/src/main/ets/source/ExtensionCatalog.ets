import { url } from '@kit.ArkTS';
import { JsonExtractor, JsonNode } from '../parsing/JsonExtractor';
import { AppError, ErrorCode } from '../model/ErrorTypes';
import { UrlPolicy } from '../network/UrlPolicy';
import { EHENTAI_BASE, EHENTAI_ID } from '../network/EhentaiAccess';

export const COPY20_REPOSITORY = 'https://raw.githubusercontent.com/LittleSurvival/copymanga-copy20/repo/index.min.json';
export interface ExtensionEntry { pkg: string; externalId: string; name: string; version: string; code: number; lang: string; baseUrl: string; nsfw: boolean; nativeId: string; status: string; }
export interface AdditionalSource { name: string; address: string; status: string; nativeId?: string; }
export function additionalSources(): AdditionalSource[] {
  return [
    { name: 'MYCOMIC 我的漫画',address: 'https://mycomic.com/cn/comics',status: '网页 HTML 与内嵌目录接入；Cloudflare 会话及设备阅读待确认',nativeId: 'org.hsmihon.mycomic' },
    { name: '漫画库',address: 'https://www.manhuaku.com.cn/',status: '目录与线路 API、原生页面数据混合接入；设备阅读待确认',nativeId: 'org.hsmihon.manhuaku' },
    { name: '漫画柜',address: 'https://www.manhuagui.com/',status: '网页 HTML 接入；设备阅读待确认',nativeId: 'org.hsmihon.manhuagui' },
    { name: 'JoyACG',address: 'https://joyacg.cc/',status: '已接入漫画列表、整本目录与页清单；设备阅读待确认',nativeId: 'org.hsmihon.joyacg' },
    { name: 'E-Hentai',address: EHENTAI_BASE,status: '18+ · 官方详情 API、网页搜索与在线阅读',nativeId: EHENTAI_ID }
  ];
}
export function repositoryAddress(raw: string): string {
  let address: url.URL; try { address = new url.URL(raw.trim()); } catch (_) { throw new AppError(ErrorCode.CONFIG_INVALID,'仓库地址格式无效'); }
  new UrlPolicy([address.hostname]).validate(address.toString());
  if (address.search || !/\/index(?:\.min)?\.json$/.test(address.pathname)) { throw new AppError(ErrorCode.CONFIG_INVALID,'请填写以 index.json 或 index.min.json 结尾的 HTTPS 目录地址'); }
  return address.toString();
}
export class ExtensionCatalog {
  private field(node: JsonNode,key: string,max: number): string {
    const value = node.members.get(key); if (!value || value.kind !== 'string' || !value.scalar || value.scalar.length > max) { throw new AppError(ErrorCode.PARSE_ERROR,'扩展目录字段无效：' + key); } return value.scalar;
  }
  parse(raw: string,repository: string): ExtensionEntry[] {
    if (raw.length > 524288) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'扩展目录超过512KiB'); }
    const root = new JsonExtractor().parse(raw); if (root.kind !== 'array' || root.items.length < 1 || root.items.length > 512) { throw new AppError(ErrorCode.UNSUPPORTED,'不支持的扩展目录格式'); }
    const output: ExtensionEntry[] = []; const packages: Set<string> = new Set(); const identities: Set<string> = new Set();
    root.items.forEach((item: JsonNode) => {
      const pkg = this.field(item,'pkg',200); if (!/^[a-zA-Z0-9_.]+$/.test(pkg) || packages.has(pkg)) { throw new AppError(ErrorCode.PARSE_ERROR,'扩展包名重复或无效'); } packages.add(pkg);
      const codeNode = item.members.get('code'); const code = Number(codeNode?.scalar); const nsfwNode = item.members.get('nsfw');
      if (codeNode?.kind !== 'number' || !Number.isSafeInteger(code) || code < 1 || nsfwNode?.kind !== 'number' || ['0','1'].indexOf(nsfwNode.scalar) < 0) { throw new AppError(ErrorCode.PARSE_ERROR,'扩展版本或内容标记无效'); }
      const version = this.field(item,'version',64); const sources = item.members.get('sources'); if (!sources || sources.kind !== 'array' || sources.items.length < 1 || sources.items.length > 32) { throw new AppError(ErrorCode.PARSE_ERROR,'扩展源列表无效'); }
      sources.items.forEach((source: JsonNode) => {
        const id = source.members.get('id'); if (!id || ['string','number'].indexOf(id.kind) < 0 || !/^[0-9]{1,20}$/.test(id.scalar)) { throw new AppError(ErrorCode.PARSE_ERROR,'扩展源ID必须为十进制字符串或整数'); }
        const identity = pkg + ':' + id.scalar; if (identities.has(identity)) { throw new AppError(ErrorCode.PARSE_ERROR,'扩展源身份重复'); } identities.add(identity);
        const baseUrl = this.field(source,'baseUrl',2048); let host: string; try { host = new url.URL(baseUrl).hostname; } catch (_) { throw new AppError(ErrorCode.PARSE_ERROR,'扩展网站地址无效'); } new UrlPolicy([host]).validate(baseUrl);
        const entry: ExtensionEntry = { pkg: pkg,externalId: id.scalar,name: this.field(source,'name',100),version: version,code: code,lang: this.field(source,'lang',20),baseUrl: baseUrl,nsfw: nsfwNode.scalar === '1',nativeId: '',status: '尚无本项目适配器' };
        if (repository === COPY20_REPOSITORY) {
          if (pkg === 'eu.kanade.tachiyomi.extension.zh.copymanga' && id.scalar === '6696312508930833206') { entry.nativeId = 'org.hsmihon.copy'; entry.status = '已接入独立COPY API与网页模式；设备阅读待确认'; }
          if (pkg === 'eu.kanade.tachiyomi.extension.zh.baozimanhuaplus' && id.scalar === '4654438345013653772') { entry.nativeId = 'org.hsmihon.baoziplus'; entry.status = '原生适配器已接入，待站点运行确认'; }
          if (pkg === 'eu.kanade.tachiyomi.extension.zh.hipmh' && id.scalar === '10879178251255350') { entry.nativeId = 'org.hsmihon.hipmh'; entry.status = '图片清单协议已验证；未验证图片下载与展示'; }
          if (pkg === 'eu.kanade.tachiyomi.extension.zh.vomicmh' && id.scalar === '3001986353') { entry.nativeId = 'org.hsmihon.vomic'; entry.status = '已接入公开目录与登录清单解析；真实登录及下载待确认'; }
        }
        if (pkg !== 'eu.kanade.tachiyomi.extension.zh.manwayuplus') { output.push(entry); }
        if (output.length > 1024) { throw new AppError(ErrorCode.RESPONSE_TOO_LARGE,'源目录超过1024项'); }
      });
    }); return output;
  }
}
