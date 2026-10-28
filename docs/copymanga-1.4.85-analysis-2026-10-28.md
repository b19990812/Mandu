# 拷贝漫画 1.4.85 与 HS_mihon 网页实现技术对照

日期：2026-10-28（Asia/Hong_Kong）。范围：协议及静态代码分析；本轮不修改业务实现、不运行测试、不请求正文图片、不进行 UI 截图。

## 证据状态

已从指定仓库下载 **1.4.85 APK 本体**，使用 JADX 1.5.6 静态反编译，并与当前 ArkTS 源码对照。结论是：**上游普通阅读使用独立 `/api/v3` JSON 接口；当前项目使用 `/api/kb/web` 加网页 AES 清单，两套协议并不等价。** 上游的 `/chapter2/` 路径、Token 会话和 `contents + words` 页序都没有被当前网页实现复用。

本轮没有执行 APK，没有发出源站 API、登录或正文图片请求，没有设备/UI 验收。本文证明的是 APK 的客户端规则，不证明所有列出的域名当前可达、服务器必需全部请求头或所有作品可匿名访问。历史空 `contentKey` 现象不作为本轮复现证据。

| 样本与工具 | 记录 |
|---|---|
| APK 来源 | [指定 repo 分支 APK](https://github.com/LittleSurvival/copymanga-copy20/blob/repo/apk/tachiyomi-zh.copymanga-v1.4.85.apk) |
| APK 大小 | 455373 字节 |
| APK SHA-256 | `0a208f10b4f8fa3f3f0fae7704935e1a487c6ee342722c7e7818a02ad8c8dd6a` |
| Git blob SHA-1 | `00c962a2bce49b10eb0c9cea29e8154dcf400df8`；下载字节按 Git blob 算法计算后与仓库记录一致 |
| 固定版本引用 | [201b5bf1 下的同一 APK](https://github.com/LittleSurvival/copymanga-copy20/blob/201b5bf1e11f89befb0388953e86536c4808239e/apk/tachiyomi-zh.copymanga-v1.4.85.apk) |
| 反编译 | JADX 1.5.6，来源为 [官方 Release](https://github.com/skylot/jadx/releases/tag/v1.5.6)，工具 ZIP 的 SHA-256 已与官方资产 digest 核对 |
| 本地证据根目录 | `temp/copy-1485-analysis-20261028/`；`decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/` 以下简称 U |

JADX 对 platform/resolution 两个枚举的高层恢复有警告，因此额外导出了 fallback 低层指令，复核默认值分别为 `1`、`1500`。这属于静态证据复核，不是运行时测试。反编译 Java 是分析资料，不应直接当作原始 Kotlin 源码或产品代码复制。

## 1.4.85 APK 的实际客户端规则

### 1. API 域名与网页域名分开

`ApiDomainOption` 的 COPY 内置选项为：

| API 主机 | APK 中的说明 |
|---|---|
| `api.mangacopy.com` | 国际服 |
| `mapi.copy20.com` | 大陆专线 1 |
| `mapi.copy2000.site` | 大陆专线 2 |
| `api.2026copy.com` | 大陆专线 3 |
| `api.copy3000.com` | 大陆新站 |
| **`api.copy4000.com`** | **大陆新站 2，未保存设置时的默认值** |

它还列出热辣线路 `mapi.hotmangasd.com`、`api.manga2025.com`、`mapi.hotmangasf.com`、`mapi.hotmangasg.com`、`mapi.elfgjfghkk.club`、`mapi.fgjfghkk.club`、`mapi.fgjfghkkcenter.club`，以及自定义域名。热辣选项使用另一组头和章节路径，不能把它当作 COPY 的透明 CDN 镜像。

`ApiRepo.getApiUrl()` 把选定 API 地址拼上 `/api/v3`；内置 hostname 默认补 HTTPS。以上是 APK 内置候选，不是本轮可达性清单。证据：U/ApiDomainOption.java:18–31、82、184–193；[ApiDomainOption.java](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/ApiDomainOption.java:18)、[ApiRepo.java](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/api/ApiRepo.java:55)。

三个地址概念必须区分：索引 `sources[].baseUrl` 是 `https://www.mangacopy.com`；APK 的 `PluginMetaData.BASE_URL` 是 `https://www.copy3000.com`；实际 API 默认是 `https://api.copy4000.com/api/v3`。此外，WebView 地址有独立偏好设置，未保存设置时为 `www.copy4000.com`，作品/章节浏览链接另由它构造。不能仅把索引 baseUrl 换成 API hostname 就认为迁移完成。证据：[指定索引](https://raw.githubusercontent.com/LittleSurvival/copymanga-copy20/repo/index.min.json)、U/PluginMetaData.java:10、WebViewDomainOption.java:16–23、68、CopyManga.java:842–849。

### 2. 普通阅读的请求链

以下均相对选定 API 根 `/api/v3`；尖括号是占位参数，不是实际作品。

| 用途 | 1.4.85 构造的请求 |
|---|---|
| 搜索 | `GET /search/comic?limit=21&offset=(page-1)*21&q=<关键词>&q_type=<搜索类型>&_update=true`；由 HttpUrl 编码 query |
| 推荐 | `GET /recs?pos=3200102&limit=21&offset=(page-1)*21` |
| 最新上架 | `GET /update/newest?limit=21&offset=(page-1)*21` |
| 最近更新 | `GET /comics?limit=21&offset=(page-1)*21&ordering=-datetime_updated` |
| 筛选列表 | `GET /comics?limit=21&offset=...`，再附区域/主题/免费类型/ordering 等选项及 `_update=true` |
| 排行榜 | `GET /ranks?type=1&limit=21&offset=...`，附 date_type/audience_type 等选项 |
| 作品详情及分组 | `GET /comic2/<path_word>` |
| 某分组的目录 | `GET /comic/<path_word>/group/<group_path_word>/chapters?limit=100&offset=<0,100,...>&_update=true` |
| COPY 正文章节元数据 | `GET /comic/<path_word>/chapter2/<uuid>` |
| 源站收藏列表 | `GET /member/collect/comics?limit=21&offset=...&ordering=-datetime_modifier`，涉及登录状态 |

证据：U/api/ApiRepo.java:81–132、169–170；U/CopyManga.java:361–363、432、636–733；[ApiRepo.java](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/api/ApiRepo.java:81)。这是客户端 URL 构造规则；没有本轮服务器响应样本，不能据此宣称接口目前成功。

### 3. 请求头：哪些是已观察实现，哪些尚不能称为服务器必需

COPY 常量头如下。`HeadersInterceptor` 根据请求 URL 选择 COPY/热辣头，并通过 `addHeader` 添加；这不是服务器的正式接口规范。

| 请求头 | COPY 值或规则 |
|---|---|
| `Accept` | `application/json` |
| `Accept-Language` | `en-US,en;q=0.9,zh-TW;q=0.8,zh;q=0.7` |
| `Origin` | `https://2025copy.com`；并非随 API hostname 改写 |
| `Version` | `2026.08.21` |
| `Region` | `0` |
| `Webp` | `0` |
| `platform` | 默认 `1`；选项支持不发送、空白、`1`–`5` |
| `User-Agent` | 缺省为 `Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/114.0` |
| `sec-fetch-dest / mode / site / user` | `document / navigate / same-origin / ?1` |
| `upgrade-insecure-requests` | `1` |
| `Authorization` | 仅满足下节条件时添加 `Token <token>` |

头拦截器另删除 `Cache-Control`。UA 可选保留宿主值、删除、用户自定义、桌面列表随机、移动列表随机；默认的完整 Firefox UA 会落入 CUSTOM 分支使用原字符串。桌面/移动随机列表来自 Keiyoushi 的 user-agents.json，不是固定 UA。热辣头的主要差异为 `Origin=https://m.relamanhua.org`、`Version=2025.11.21`、`Webp=1`，没有 COPY 的 Region 常量。本地网页搜索的 `platform=2` 位于 query；此处默认 `platform: 1` 位于请求头，两者不能直接混为同一个配置位置。

证据：U/api/ApiRepo.java:23–24；[HeadersInterceptor.java](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/interceptor/HeadersInterceptor.java:26)；U/PluginMetaData.java:14、PreferencesKt.java:679–702、UserAgentType.java:42–56、interceptor/UserAgentInterceptor.java:130–151、168–194；`platform-fallback.java` 中 ONE 和 DEFAULT 的赋值。

上述头通过同一个 OkHttpClient 的拦截器处理，不能推断它们只附在元数据请求上。普通阅读调用链中未见额外的动态请求签名、AES 响应解密或图片像素重排；API JSON 直接交给序列化解析器。这不等于服务器永远不改变协议，也不构成当前可用性结论。

### 4. 会话与登录

- HTTP 客户端显式设置 `CookieJar.NO_COOKIES`，30 秒 call timeout、允许连接失败重试。因此它不靠 OkHttp CookieJar 自动承接网页 Cookie。[CopyManga.java:174](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/CopyManga.java:174)。
- `enableLogin` 默认 false。只有启用登录且本地 token 非空、不是 error:/expired: 状态标记时，才加 **`Authorization: Token <token>`，不是 Bearer**。拷贝与热辣各存一份 token。401 会把当前有效记录标成过期，没有看到普通请求自动重新登录或自动刷新 token 的流程。证据：[AuthorizationInterceptor.java:26](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/interceptor/AuthorizationInterceptor.java:26)、U/special/TokenProvider.java:199–201。
- 拦截器按所选 API 偏好字符串是否包含于请求 URL 判断是否参与认证；自定义值 `custom` 并不自动等价于 custom URL 的 host。移植时应使用显式精确 origin 绑定，不复制这个 substring 判断。
- V2 登录在 WebView `/h5` 页面取得 token：观察 `/system/config/2020/1` 请求的 `Authorization: Token ...`，或读取名为 `token` 的 Cookie；代码也提供 Native.sendToken 回调。**这是提取 token 后用于 API，不是把整个 Cookie 字符串随意跨域转发。** 证据：U/special/TokenProvider.java:556–587、630–675、678–711。
- 同一 APK 还保留 V1 账号密码登录：向 `https://<domain>/api/v3/login` POST 表单，字段包括 username/password/salt/source/version/platform；COPY 的 source 为 `freeSite`，这里表单 version 是 `2025.05.09`，与上面的 `Version` 请求头不同。它把 `password-四位随机salt` 作 Base64，读取 `results.token`。这里只记录静态契约，本轮未接触账号或执行登录。证据：U/special/TokenProvider.java:464–507。

客户端默认不发送 token，说明它支持尝试匿名浏览；**不能从这个默认值推断任何章节都不需要登录**。源站书柜属于账号功能；真实访问权限仍由当前服务器响应决定。

### 5. 章节身份与目录排序

作品定位使用 `path_word`；详情返回 `groups`，各组用自己的 `path_word` 请求章节列表。组内 `results.list[]` 的关键字段是 `uuid`、`comic_path_word`、`group_path_word`、`name`、`index`、`datetime_created`。上游生成的 SChapter.url 是 `<comic_path_word>/chapter/<uuid>`；发出普通 COPY 页清单请求前，`fixChapterId()` 去掉可能的 `/comic/` 前缀，再把 `/chapter/` 换为 `/chapter2/`。热辣保留 `/chapter/`。证据：U/api/ApiRepo.java:71–84、124–132；[ChapterInfo.java:271](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterInfo.java:271)。

目录实现先取全部分组，逐组以 `offset += 100` 请求，直到已累积条数达到该接口返回的 total。**每组按 `ChapterInfo.index` 降序排序**，再按用户设置过滤同名默认章节，转成 SChapter 后拼接各组；没有对分组再作显式数值排序。非 default 分组可在展示标题前加组名。可选漫画评论会另外作为伪章节追加，应与正文章节区分。

证据：[CopyManga.java:201](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/CopyManga.java:201) 至 280。上游循环没有本项目已有的批次数/无前进保护；移植时应保留本项目的有界分页校验，不能照搬服务异常时可能无法终止的循环。

**index 降序是该插件向 Mihon 输出目录的规则，不能直接当作 HS_mihon 的下一章契约。** 本地用插入顺序生成 ordinal，协议适配需要先明确升序阅读顺序，并保留分组边界，不用标题数字猜章序。API 的 uuid 与网页目录 id 名称不同；即便都呈 UUID，仍需实际元数据证明同一作品/章节的一一对应后才能认定迁移身份一致。

本轮已进一步核实：`CatalogRepository` 以传入数组下标重写 ordinal，并按 ordinal 升序读回；`ReaderService` 把当前位置之后的第一项设为 nextId。因此，直接照抄上游降序数组会让下一章朝较小 index 前进。详情页的 reverse 仅影响列表显示，不能修正阅读器方向。证据：[CatalogRepository.ets:62](E:/AI_coding/HS_mihon/entry/src/main/ets/storage/CatalogRepository.ets:62)、[ReaderService.ets:68](E:/AI_coding/HS_mihon/entry/src/main/ets/business/ReaderService.ets:68)、[DetailVM.ets:73](E:/AI_coding/HS_mihon/entry/src/main/ets/vm/DetailVM.ets:73)。

### 6. 图片清单与排序

正文章节响应按 `ApiResponse<ContentResult>` 解析，普通页清单来自 **`results.chapter.contents[].url`**；另有 **`results.chapter.words[]`** 提供整数排序权重。`ChapterDetail` 同时定义 count/ordered/uuid 等字段，但 `toPageList()` 的排序分支实际看的是 words。

上游的算法是：

1. 若第一项 url 为空则没有可用页清单；空 contents 会在取首项时失败。
2. words 为 null/空数组：按 contents 原顺序输出。
3. words 非空：**先把 contents[i] 与 words[i] 配对，再按 words 值升序排序**，最后重新编号为 0..N-1。
4. 输出 URL 按分辨率偏好改写。仅替换 URL 尾部匹配 `数字x.jpg` / `数字x.webp` 的数字，支持 800/1200/1500，默认 1500；不是另发一个清晰度接口。

纯符号示例：contents 为 `[C,A,B]`、words 为 `[2,0,1]` 时，阅读顺序是 `[A,B,C]`。words 是对应项的排序权重，**不是让实现拿它去访问 contents[word] 的下标表**；APK 没有要求权重必须从零连续。不要按 URL 文件名、章节 index 或 `ordered` 布尔值代替这一过程。

证据：[ChapterDetail.java:413](E:/AI_coding/HS_mihon/temp/copy-1485-analysis-20261028/decompiled/sources/eu/kanade/tachiyomi/extension/zh/copymanga/api/dto/ChapterDetail.java:413) 至 458；U/CopyManga.java:432–443；U/ResolutionOption.java:26–31、77、102–105，`resolution-fallback.java` 复核默认值。

上游 Kotlin zip 在两数组长度不同时只配对较短部分；上游这段没有先检查长度一致。因此移植时应该显式拒绝长度不匹配、非法权重或无效 URL，避免把缺页静默记为下载完成。重复权重如何对待也需要明确；不能把“上游排序后能输出”当成目录完整性证明。上游 Page 主要使用连续页下标及 URL，没有本项目 pageKey 的稳定刷新契约。

分辨率改写会改变 pathname；当前本地 pageKey 恰好使用 pathname。如果未来加入清晰度选项，应先设计稳定页面身份及缓存变体，避免清晰度切换被误判为换页或混用旧缓存。API JSON URL 的真实 CDN 主机仍需元数据核对，本轮没有取得实际 API 清单，不能据枚举自行扩大 CDN 白名单。

### 7. 错误与请求节奏

上游额外识别文本 error、返回 HTML、HTTP 210、401、404、503，分别给出参数/平台、错误跳转、业务拒绝、认证、域名或站点异常线索。210 虽属于 2xx，不能仅由通用 HTTP 成功判断认定已得到正确清单。内置 API 域名共用节流间隔 100 ms；这只是插件客户端行为，不是服务器公布的额度。证据：U/interceptor/ResponseErrorInterceptor.java:23–56、AuthorizationInterceptor.java:51–59、RateLimitInterceptor.java:20–43。

这些错误文案不证明本地空 contentKey 的原因。当前网页失败停在清单提取阶段，仍不能直接归因 CDN、AES 或缓存。

## 当前网页实现基线

### 1. 身份、域名与网络边界

本项目的稳定源 ID 是 `org.hsmihon.copy`，适配器 `version = 1`；默认根网址是 `https://www.mangacopy.com/`。源 ID 不随域名改变，也不能直接替换为上游 Mihon 的 64 位源 ID。[CopySource.ets:19](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:19)、[SourceSiteCatalog.ets:11](E:/AI_coding/HS_mihon/entry/src/main/ets/source/SourceSiteCatalog.ets:11)。

`SourceSiteService.access()` 仅把当前根网址的精确 hostname 放入 `site.allowedHosts`。`CopySource` 和 `CopyDiscovery` 的网页/API 请求均以这个根网址解析地址，没有独立的“移动 API 根地址”或“线路选择”配置。用户修改根网址时，网址 revision 增加，并通知已在执行的任务取消。[SourceSiteService.ets:47](E:/AI_coding/HS_mihon/entry/src/main/ets/source/SourceSiteService.ets:47)、[SourceSiteService.ets:56](E:/AI_coding/HS_mihon/entry/src/main/ets/source/SourceSiteService.ets:56)、[CopySource.ets:25](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:25)、[DiscoveryBase.ets:20](E:/AI_coding/HS_mihon/entry/src/main/ets/source/discovery/DiscoveryBase.ets:20)。

正文图片主机为固定精确清单：`sn.mangafunb.fun`、`sc.mangafunb.fun`、`sz.mangafunb.fun`、`sj.mangafunb.fun`、`sd.mangafunb.fun`、`sl.mangafunb.fun`。封面另有 `COPY_COVER_HOSTS`，两份清单与站点主机共同进入底层 Transport 的总白名单；图片清单仍由正文图片的更窄白名单单独校验。没有任意子域通配符。[CopySource.ets:16](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:16)、[CopyDiscovery.ets:12](E:/AI_coding/HS_mihon/entry/src/main/ets/source/discovery/CopyDiscovery.ets:12)、[NativeSourceFactory.ets:12](E:/AI_coding/HS_mihon/entry/src/main/ets/source/NativeSourceFactory.ets:12)。

`UrlPolicy` 要求公网 DNS 名称、HTTPS、空端口或 443，拒绝凭据、片段、IP、localhost、未列入清单的域名。[UrlPolicy.ets:13](E:/AI_coding/HS_mihon/entry/src/main/ets/network/UrlPolicy.ets:13)。因此，即便 APK 允许自由配置域名，移植时也需要单独整理并审核精确 API/CDN 主机。

### 2. 请求头、方法和会话

| 层次 | 当前行为 | 源码证据 |
|---|---|---|
| CopySource 元数据 | `Accept: text/html`；搜索和目录改为 `application/json`；`Referer: site.baseUrl`；响应上限 2 MiB | [CopySource.ets:26](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:26) |
| CopyDiscovery 元数据 | 同样显式 `Accept`、根网址 Referer；标记 `responseKind: metadata`；2 MiB | [DiscoveryBase.ets:23](E:/AI_coding/HS_mihon/entry/src/main/ets/source/discovery/DiscoveryBase.ets:23) |
| 图片请求 | `resolveImage()` 只返回根网址 Referer，URL 经正文主机清单校验 | [CopySource.ets:101](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:101) |
| 通用允许头 | 只允许 `Accept`、`Accept-Language`、`Referer`、`User-Agent`；拒绝值中的换行 | [RcpTransport.ets:40](E:/AI_coding/HS_mihon/entry/src/main/ets/network/RcpTransport.ets:40) |
| 默认补齐 | 缺省 UA 为 `HS-Mihon/0.3 (HarmonyOS; anonymous-reader)`；语言为 `zh-CN,zh;q=0.9,en;q=0.5` | [RcpTransport.ets:57](E:/AI_coding/HS_mihon/entry/src/main/ets/network/RcpTransport.ets:57) |
| HTTP 方法 | `RequestPlan` 没有 method/body 字段；RCP 实际构造 `GET` | [Transport.ets:5](E:/AI_coding/HS_mihon/entry/src/main/ets/network/Transport.ets:5)、[RcpTransport.ets:101](E:/AI_coding/HS_mihon/entry/src/main/ets/network/RcpTransport.ets:101) |
| Cookie | 原生源 Transport 默认 `anonymous=false`，由网络层读取已保存的站点 Cookie 并注入；适配器不能用头清单直接设置 Cookie | [NativeSourceRegistry.ets:49](E:/AI_coding/HS_mihon/entry/src/main/ets/source/NativeSourceRegistry.ets:49)、[RcpTransport.ets:69](E:/AI_coding/HS_mihon/entry/src/main/ets/network/RcpTransport.ets:69) |

当前 COPY 没有 token 获取、账号密码提交、Authorization 生成、移动 API 设备头或签名头实现。若 1.4.85 需要这些能力，现有“只读 GET + 四类业务请求头”契约不能直接承载，不能简单把请求字符串抄入 `CopySource`。

站点 Cookie 通过 `SecretStore` 保存，键为 `site-cookie:<sourceId>:<origin>`，有效期在保存时固定为 24 小时；过期或格式含换行则不提供 Cookie。它按精确 origin 隔离，不能因为网页和 API 属于同一品牌就自动跨 origin 搬运凭据。[SiteSession.ets:8](E:/AI_coding/HS_mihon/entry/src/main/ets/network/SiteSession.ets:8)。

`SourceWebPage` 提供独立临时 WebView：进入/离开时清空临时 WebView Cookie；用户手动点击“保存当前站点会话”后，才把当前网址 Cookie 写入上述存储。COPY 的 DOM storage 关闭（仅 Vomic 开启），没有保存或传递 localStorage token 的逻辑。WebView 只能访问允许主机，SSL 错误直接取消。[SourceWebPage.ets:17](E:/AI_coding/HS_mihon/entry/src/main/ets/pages/SourceWebPage.ets:17)、[SourceWebPage.ets:31](E:/AI_coding/HS_mihon/entry/src/main/ets/pages/SourceWebPage.ets:31)、[SourceWebPage.ets:53](E:/AI_coding/HS_mihon/entry/src/main/ets/pages/SourceWebPage.ets:53)。

RCP 重定向时每一跳重新校验 URL、重新按目标 origin 读取 Cookie，最多五次跳转，拒绝 HTTPS 降级。该逻辑并不证明服务器接受当前 UA 或已保存 Cookie；本轮没有发出站点请求。[RcpTransport.ets:60](E:/AI_coding/HS_mihon/entry/src/main/ets/network/RcpTransport.ets:60)。

### 3. 搜索、详情与发现

| 能力 | 当前入口和解析 |
|---|---|
| 搜索 | 同根域 `/api/kb/web/searchcl/comics?offset=(page-1)*12&platform=2&limit=12&q=<URL编码关键词>&q_type=`；校验 `code=200`，读取 `results.list` 与 `results.total`，作品标识取 `path_word` |
| 详情 | `/comic/<path_word>` HTML；标题 `.comicParticulars-title-right h6`，作者 `/author/` 链接，标签 `.comicParticulars-tag a`；同时读取 `var ccz='...'` 供目录解码 |
| 分类/热门/更新/完结 | `/comics` HTML 中 `.exemptComic-box` 的 `total/list` 属性；每页 50，`ordering` 分别为用户选项、`-popular`、`-datetime_updated`；完结固定 `status=1` |
| 新上架 | `/newest?offset=(page-1)*60&limit=60`，只在 HTML 含精确下一页链接时提供下一页 |
| 推荐/榜单 | `/` 的“漫畫推薦”区，或 `/rank?type=...&table=...`；推荐和榜单没有额外分页 |

证据：[CopySource.ets:45](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:45)、[CopySource.ets:62](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:62)、[CopyDiscovery.ets:25](E:/AI_coding/HS_mihon/entry/src/main/ets/source/discovery/CopyDiscovery.ets:25)。搜索分页 token 绑定源 ID、适配器版本、网址 revision 和原查询，不能混用于另一个查询。[CopySource.ets:47](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:47)。

### 4. 章节标识、目录完整性与次序

作品标识允许 `[a-zA-Z0-9_-]{1,200}`，存为 `remoteId=<path_word>`、`locator=/comic/<path_word>`。章节 ID 必须是小写十六进制 UUID；章节远程身份为 `<path_word>/<UUID>`，页面定位为 `/comic/<path_word>/chapter/<UUID>`。输入 SourceRef 必须属于 `org.hsmihon.copy`，且 remoteId 推导出的路径与 locator 完全一致。[CopySource.ets:32](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:32)。

目录流程为：必要时先取详情得到 `ccz` → GET `/comic/<path_word>/chapters` → 要求 `code=200` → 用 `ccz` 解码字符串 `results` → 读取解码对象 `groups` → 逐组读取 `chapters`。每组 `count` 必须等于该组数组长度；目录总量不得超过 10000 章，也不能为空；不接受额外分页 token。[CopySource.ets:72](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:72)。

每章只读取 `id`、`name`；UUID 重复时保留第一次出现。**当前排序是 `groups` 在解析器 Map 中的遍历顺序，再接各组 `chapters` 的原数组顺序**，`ordinal` 直接取插入后的下标；没有按章节数值、`type`、标题或另一排序字段重新排序。现有 `ChapterRef` 也没有分组/卷号字段。[CopySource.ets:78](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:78)、[JsonExtractor.ets:7](E:/AI_coding/HS_mihon/entry/src/main/ets/parsing/JsonExtractor.ets:7)、[JsonExtractor.ets:74](E:/AI_coding/HS_mihon/entry/src/main/ets/parsing/JsonExtractor.ets:74)、[SourceTypes.ets:11](E:/AI_coding/HS_mihon/entry/src/main/ets/model/SourceTypes.ets:11)。

### 5. 图片清单、解码与排序

`pages()` GET 章节网页，并从 HTML 中提取 `var contentKey='...'` 与 `var cct='...'`。`contentKey` 必须匹配“前 16 个字母数字字符 + 十六进制密文”，`cct`/`ccz` 必须为 16 字符字面量，格式不符即抛 `PARSE_ERROR`，不会执行网页脚本，也不会把空清单当成功。[CopySource.ets:92](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:92)、[CopyFormat.ets:9](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopyFormat.ets:9)。

`CopyFormat.decode()` 按 AES-128-CBC/PKCS7 解码：key 是 `cct`（目录则为 `ccz`）的 UTF-8 字节；IV 是 `raw` 前 16 字符的 UTF-8 字节；剩余十六进制串转密文字节，解密输出须为有效 UTF-8 JSON。密文字节必须为 16 的整数倍，字符串总长最多 2 MiB。[CopyFormat.ets:16](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopyFormat.ets:16)。

解码后须为 1–2000 项数组。每项只读取 `url`，按**返回数组原顺序**输出，`ordinal=index`，没有 `contents` 与独立 `words`/index 映射、没有按 URL 文件名排序，也没有拼图或像素变换逻辑。`imageUrl` 保留完整地址，`pageKey` 与 `locator` 只取 `URL.pathname`，因此 CDN 主机和签名 query 不参与页面身份。[CopySource.ets:94](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:94)。

### 6. 刷新、缓存与下载契约

`resolveImage(refresh=true)` 重新取章节清单，并用原 `pageKey` 寻找同一张图；找不到时报 `CONTENT_CHANGED`，不会以同一下标静默替代。返回地址的 pathname 必须仍等于 pageKey；`contentRevision` 为 `<adapterVersion>:<siteRevision>`。[CopySource.ets:101](E:/AI_coding/HS_mihon/entry/src/main/ets/source/adapters/CopySource.ets:101)、[RefreshPage.ets:6](E:/AI_coding/HS_mihon/entry/src/main/ets/source/RefreshPage.ets:6)。

通用清单汇总保留源返回次序，重新连续编号；同 pageKey 且同 imageUrl 的重复项折叠，同 pageKey 不同 URL 则拒绝；最多 100 批、2000 张，没有前进或分页重复则拒绝。COPY 本身不分页。[ChapterManifest.ets:8](E:/AI_coding/HS_mihon/entry/src/main/ets/business/ChapterManifest.ets:8)。因此，改用另一套 API 后必须先在源适配层恢复正确次序，后面的阅读/下载层不会替源推断页序。

在线图片缓存身份为 `[sourceId,'anonymous',chapter.remoteId,pageKey,revision]` 的摘要；正式阅读传入的 revision 是 `handle.snapshotKey`，原生快照目前由 schema、源 ID、固定版本 1 和 baseUrl 生成。`ImageRequest.contentRevision` 没有在 `AssetTransfer` 中直接参与缓存键；不能误把它当作已经生效的独立失效机制。[BrowserCache.ets:24](E:/AI_coding/HS_mihon/entry/src/main/ets/image/BrowserCache.ets:24)、[ReaderAssetCache.ets:84](E:/AI_coding/HS_mihon/entry/src/main/ets/image/ReaderAssetCache.ets:84)、[ReaderService.ets:49](E:/AI_coding/HS_mihon/entry/src/main/ets/business/ReaderService.ets:49)、[NativeSourceRegistry.ets:33](E:/AI_coding/HS_mihon/entry/src/main/ets/source/NativeSourceRegistry.ets:33)。

`AssetTransfer` 在 `ACCESS_DENIED`、`AUTH_REQUIRED`、`IMAGE_EXPIRED` 时允许一次清单刷新，网络/超时/限流/服务端错误走有限重试；图像用流式下载和文件校验后提交。它不会在 `contentKey` 提取失败时自行切换另一 API。[AssetTransfer.ets:9](E:/AI_coding/HS_mihon/entry/src/main/ets/image/AssetTransfer.ets:9)。

`RegistryTransport` 与 `RegisteredSource` 在请求前后都检查源状态，网址变更会取消请求；原生固定快照已改变时旧下载任务拒绝继续。上述身份及快照约束应在协议移植时保留。[SourceRegistry.ets:71](E:/AI_coding/HS_mihon/entry/src/main/ets/source/SourceRegistry.ets:71)、[SourceRegistry.ets:96](E:/AI_coding/HS_mihon/entry/src/main/ets/source/SourceRegistry.ets:96)、[NativeSourceRegistry.ets:45](E:/AI_coding/HS_mihon/entry/src/main/ets/source/NativeSourceRegistry.ets:45)。

## 逐项对照与接入影响

| 对照项 | 现有网页实现 | 1.4.85 APK |
|---|---|---|
| API 域名与站点域名 | 全部元数据共用当前 site.baseUrl，无独立 API 根配置 | API 与 WebView 分开；默认 api.copy4000.com/api/v3 |
| 请求头 | Accept/Referer + 网络层 UA/语言；可选已保存 Cookie | Origin/Version/Region/Webp/platform + UA 等；COPY API 常量与网页值不同 |
| 登录/会话 | 手动 WebView 保存的精确 origin Cookie，固定 24h；无 token 登录 API | NO_COOKIES；可选 Authorization: Token，分 COPY/热辣 token，401 标过期 |
| 作品/章节 ID | path_word + UUID；网页目录字段 id，locator 为 /comic/.../chapter/... | API 目录字段 uuid；SChapter 中仍保存 /chapter/，请求 COPY 时转换 /chapter2/ |
| 目录与分组 | 加密网页目录，一次全量，保持分组及组内数组原序 | comic2 详情→逐组100项分页→组内按 index 降序；适配时需转成本地阅读顺序 |
| 页清单 | HTML contentKey+cct，AES-128-CBC/PKCS7，url 数组 | 直接解析 JSON results.chapter.contents；普通链路不读 contentKey/cct |
| 图片排序 | 只保留解码数组原序，无单独索引映射 | contents 与 words 同位置配对，按 words 升序；缺省 words 才保留原序 |
| 清晰度 | 不改写源站返回 URL | 改写结尾的 800x/1200x/1500x.jpg/webp，默认1500 |
| 稳定页面身份 | URL.pathname；刷新按 pageKey 匹配，签名 query 不进身份 | 上游主要用 Page 下标及 URL；没有可直接替代本地 pageKey 的契约 |

从当前边界看，真正接入 1.4.85 协议需要以下有限改动设计；本轮仅分析，没有实施：

1. 在 COPY 源范围内区分 WebView 地址、API 地址与协议 revision。继续使用 `org.hsmihon.copy`，先验证旧网页 id 与 API uuid 的对应关系；不通过换域名创建重复书架源。
2. 让 COPY 专用请求层承载经审核的头与精确 API origin；如果只做匿名 GET 核心阅读，不必先扩大为任意 POST/自定义头。账号登录是另一个明确的扩展点；不把 Authorization 全局透传给其他源、CDN 或重定向目标。
3. 元数据读取改为 comic2/分组目录/chapter2；为组分页增加条数上限、无前进、重复、total 漂移检查；页清单严格校验身份、数量、URL 和排序数组，空结果明确失败。
4. 在源适配层完成按 index 的本地目录次序和按 words 的图片页序。阅读器、缓存、下载队列继续依赖同一个明确的清单契约，不各自修正顺序。
5. 复用现有缓存/下载通路之前，审核快照是否含 API 线路、协议、清晰度与必要的会话身份；当前硬编码 anonymous 的缓存身份不等于已支持按账号隔离。签名 query 的刷新仍按稳定 pageKey 匹配，不能只按页下标替换。

**当前可以下的结论**：与上游对齐是一项 COPY 协议适配工作，不是索引导入、域名替换或放宽 contentKey 正则即可完成。API 链路不依赖网页 contentKey，因而是独立于现有网页故障的候选技术路线；没有实时 API 元数据证据前，不宣称已经修复或已能正常阅读。

后续若进入协议验证，先只取搜索/详情/目录和页清单 JSON，记录状态、响应类型、字段数量、作品/章节对应与页序，不下载图片。这样可核实当前服务端契约与旧身份映射；正文下载及设备验收另行界定。本轮没有运行单元、集成、全量回归或构建，因为未改业务代码；保留的 APK、hash、反编译和 fallback 指令属于本次静态分析证据。
