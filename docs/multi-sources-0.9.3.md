# 漫蛙、Vomic、JoyACG 接入：0.9.3

> 后续更新：[域名策略](source-domain-policy-2026-10-28.md) 已取消网站、CDN 及封面代理的精确域名限制。本页的精确主机检查和交付证据保留为 0.9.3 历史记录。

日期：2026-10-28（Asia/Hong_Kong）。接续 [COPY API 接入](copy-api-integration-2026-10-28.md)。本轮按各网站当前公开 HTML/JSON/客户端脚本实现，不把相同品牌或旧扩展中的地址当作当前协议。

## 使用与交付

进入「更多 → 源规则」，找到并启用「漫蛙漫画」「Vomic 漫画」「JoyACG 漫画」，返回「浏览」后打开对应源。新源沿用项目默认停用策略，不覆盖用户之前的启用/停用状态。

漫蛙也可通过指定扩展仓库目录关联并启用；JoyACG 可直接通过「扩展仓库 → 新增网站适配状态 → 启用本项目适配器」启用，无需虚构 APK 仓库身份。各网站根地址仍可在「自定义网站」修改。

- [0.9.3 Release signed HAP](../artifacts/0.9.3/hs-mihon-release-default-signed.hap)，versionCode 21，8,003,851 字节。
- SHA-256：`b0009cf0ccf8e43f8a87c9e27456d48074729a5a21982d7f3bc2634bde305e2f`，见 [SHA256SUMS](../artifacts/0.9.3/SHA256SUMS)。
- API24 最低兼容、API26 目标/编译、phone/tablet 配置保持原值。本轮未安装到设备。

如需保留数据覆盖安装：

```powershell
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r .\artifacts\0.9.3\hs-mihon-release-default-signed.hap
```

## 漫蛙

稳定源 ID 为 `org.hsmihon.manwa`，默认根网址 `https://www.manwali.cc/`。当前网站使用 `/comic/<id>`，与之前保存的旧扩展 `/book/...` 参考协议不同，因此新增适配器以实时站点协议为准，没有执行上游脚本或 APK。

| 功能 | 当前实现 |
|---|---|
| 搜索 | `GET /api/search?type=mh&keyword=...&page=...&pageSize=20`，校验 total、批次长度、身份与查询绑定 token |
| 首页/热门/分类栏目 | `/api/home`，读取 comicList / gufengList / xuanhuanList / xiaoyuanList；只接漫画类型，不引入视频/小说条目 |
| 详情 | `/comic/<id>` HTML 的标题、作者、标签、简介、状态与封面 |
| 目录 | `/api/comic/<id>/chapters`，与详情 HTML 的全部 `.chapter-item` 数量和 ID 集合交叉核对，拒绝部分/重复目录 |
| 阅读身份 | `/api/comic/chapter/info/<chapterId>`，校验 current.id / current.comicId |
| 页清单 | `/api/comic/image/<chapterId>?page=N&page_size=50&image_source=...`，完整读取所有批次，校验分页、总量、作品/章节路径与重复页 |

目录以 sortId 升序阅读。真实样本中两章合法共用 sortId=26；同号时使用已验证的完整网页目录次序，避免误拒特别篇或按标题猜顺序。

正文仅接入站点公开列出的标准 HTTPS DNS 线路 `mwtuwu.cc`；封面主机为 `ce.mwzu.cc`。站点源列表中的 IP:8088 和 VIP 专用空地址不在本轮支持范围，不放宽 UrlPolicy，也不自动扩展任意 CDN。

网站客户端会将普通图片直接显示；对其他容器使用前 16 字节 IV、AES-256-CBC/PKCS7 解码。新增 `ManwaImageSink` 以分段方式执行该格式，保留 32MiB 输入/输出限额、取消与截止时间。它在原 `AssetTransfer` 文件流内工作，随后仍经过 `FileVerifier` 的容器、解码、尺寸和 SHA256 校验，最后原子提交 `.part`。其他源不能选择这一解码标记，任意请求头/Authorization 权限没有扩大。

目前只支持源站匿名可返回的内容；没有新增账户、VIP 或付款功能。服务端拒绝时明确失败。

## JoyACG

稳定源 ID 为 `org.hsmihon.joyacg`，默认根网址 `https://joyacg.cc/`。这是 WordPress 定制站点，当前漫画条目页面自身就是整本画廊。

- 搜索 `/search/<编码关键词>/`，最新列表 `/comic/` 及 `/comic/page/N/`，热门漫画来自首页 `#hotc`；分页仅承认同源的精确下一页链接。
- 只提取同源数字作品路径，且封面必须为明确的 `supercdn.site/galleries/...` 画廊。外部广告、动画封面和新闻不会混入漫画列表。
- 详情检查 `og:url` 作品身份及漫画分类；读取标题、封面和标签。原站未提供独立章节目录，表示成一个明确的“整本”章节，remoteId 为 `<作品ID>/book`。
- 页清单只读取 `#content img`，与页面声明的“頁數：Np”一致；验证页号 1..N、画廊 ID、唯一 pathname 和精确正文主机 `supercdn.site`。最多 2000 页。
- 封面仅允许 `i0.wp.com` 下指向 `supercdn.site/galleries/` 的路径以及正文主机自身的画廊路径；不会因为允许 wp.com 封面而允许它代理任意正文主机。
- 签名地址刷新按稳定 pageKey 匹配，找不到原页时返回 CONTENT_CHANGED。

漫画、动画及其他文章共用 WordPress 数字文章路径，因此不能把所有同源文章都当漫画。当前实现明确校验漫画分类和画廊内容，没有增加动画下载功能。

## Vomic

保留稳定 ID `org.hsmihon.vomic`、既有搜索/详情/完整目录/SSR 页清单实现和版本 1。本轮增加：

- 最近更新：公开 `/pics/c/getUpdateBook`，每页 12 项。
- 分类：`getCatList` 返回题材选项，`getCartoonList` 通过 cat_id 筛选，支持分页。
- 完结：`getCartoonList` 使用 `process=已完结`，并校验实际条目的 process，防止服务端忽略筛选。

未将未经证实的 sort 参数作为热门功能：本轮相应探测返回 HTTP 500，所以不把它暴露为可用栏目。

网站阅读仍可能要求真实登录，沿用现有独立 WebView/会话机制；未登录返回 AUTH_REQUIRED，没有伪造 isLogin、自动登录或扩大跨域凭据传递。本轮没有有效账户验证，也没有声称网站 localStorage token 与 API 账户会话已打通。

## 模块与现有功能

新增文件：

- `source/adapters/ManwaSource.ets`
- `source/adapters/JoyAcgSource.ets`
- `source/adapters/SiteJsonClient.ets`：两新源共用的有界 GET/响应校验；各自保留协议与 CDN 判断。
- `image/ManwaImageSink.ets`

修改原生工厂、网站目录、扩展显式关联和 JoyACG 启用入口；`ImageRequest` 增加可选 encoding，旧源继续默认原文图片。复用既有 RegisteredSource、取消/修订机制、清单汇总、缓存、下载、离线和文件校验，没有数据库迁移或另一套下载器。COPY 0.9.2 API/网页接入保持原样，扩展目录中它的旧故障文案已同步更新。

## 验证、网络来源与未验收项

证据集中在 `temp/multi-sources-20261028/`，已登记 `temp/list`。

| 层次 | 本轮结果 |
|---|---|
| 实时公开协议 | 漫蛙搜索两页 20+16 项、目录 30 章、当前章 50+10 页；JoyACG 两页列表、热门 5 项及整本 190 页；Vomic 分类、更新和完结返回真实 JSON |
| 15 组协议定向检查 | 生产 ArkTS 解析真实样本，覆盖身份、完整目录、重复/缺项/页序、刷新、主机白名单、栏目及仓库关联；PASS，见 checks.json |
| 7 组生产下载链路检查 | 本地合成 PNG 加密后经流式解码、容器/摘要验证和原子提交；截断保留旧文件、403 仅刷新一次、取消无提交、非漫蛙拒绝解码；PASS，见 transfer-check.json |
| Release | 最终 CompileArkTS、PackageHap、SignHap、BUILD SUCCESSFUL；日志见任务目录 build-release-console.log 及 temp/logs 对应日志 |
| 验证替代边界 | 主机检查通过已有 Node loader 执行，CryptoFramework 与文件系统使用 Node 替代，ImageKit 解码使用替代接口；不能当作原生 SDK 或设备图像验收 |

普通 Node 直连漫蛙/JoyACG 在本机出现 ECONNRESET；浏览器可读取公开首页。最终协议文本通过**已经运行的本机代理**和标准 TLS 证书校验取得，没有修改系统代理、证书或应用的生产网络路径，也没有在 App 中加入主机代理配置。此证据不证明平板当前网络能访问同样的源或 CDN。

没有发出真实漫画图片下载请求，没有设备安装、UI 截图或登录/付费/账号操作。未执行全量测试，按本次核心解析、图片流和公共可选字段的影响，仅执行上述定向检查及 Release 构建。

复核命令：

```powershell
node .\temp\multi-sources-20261028\check.cjs
node .\temp\multi-sources-20261028\transfer-check.cjs
.\tools\dev.ps1 -Action Build -Mode release
```

剩余需设备确认：新源启用与列表、真实正文图片与漫蛙原生 CryptoFramework 解码、整章顺序/换章、下载后重启离线、Vomic 真实登录与会话保存。其他镜像、VIP 内容、额外图片主机、动画和 E-Hentai 不在本轮实现范围。

协议材料为网站本身的公开文本：`https://www.manwali.cc/static/assets/js/search.js?v=86`、`static/assets/js/index.js?v=168`、`static/mh/js/chapter.js?v=0910`、`static/assets/js/base.js?v=71`，以及上述公开 JSON/HTML；只读取规则与字段，没有执行下载脚本、广告代码或 APK。浏览器协议检查使用 [computer-use 技能](C:/Users/Administrator/.codex/plugins/cache/openai-bundled/computer-use/26.1021.31345/skills/computer-use/SKILL.md)，控制接口异常后改用元数据读取。
