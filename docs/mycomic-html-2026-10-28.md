# MYCOMIC HTML 接入与真机拦截边界

日期：2026-10-28（Asia/Hong_Kong）。

**接入方式采用 HTML 解析，包括静态读取 HTML 属性中的章节 JSON 数组。源码与签名候选包已完成，真实站点完整链路和真机可用性尚未验收。没有发现适合完整接入的独立 JSON API；这不代表站点不存在内部 API。**

## 协议证据

| 功能 | 接入路径 | 证据边界 |
|---|---|---|
| 列表、更新、人气 | `/cn/comics`，`sort=-id/-update/-views` | 网站文本索引/缓存能读到列表及栏目链接，两个公开客户端使用 HTML |
| 搜索与分页 | 同一路径，`q`、`page` | 客户端实现提供参数；第二页的站点文本快照含分页导航，非本机实时原始 HTML 验收 |
| 分类 | `filter[tag/country/audience/year/end]` | 从当前 HTML 的筛选链接读取选项；不将下一页链接误当筛选选项 |
| 详情 | `/cn/comics/{mangaId}` | 网站文本快照包含作品资料，客户端解析资料卡和 meta 字段 |
| 分组目录 | 各 `div[x-data]` 的 `chapters` JSON 数组 | 两个客户端的自身源码佐证；本站原始属性尚未现场取得 |
| 页清单 | `/cn/chapters/{chapterId}` 的 `img[x-ref]`，兼容 `img.page` | 客户端源码佐证，读取 `data-src/src`；未请求该页的真实图片 |

网站第一方页面：[资料库](https://mycomic.com/cn/comics)、[更新](https://mycomic.com/cn/comics?sort=-update)、[人气](https://mycomic.com/cn/comics?sort=-views)、[第二页](https://mycomic.com/cn/comics?page=2)、[详情样本](https://mycomic.com/cn/comics/55355)。检索通道的内容可能来自缓存，不能据此宣称当前设备网络可达。

交叉核对：[Venera MYCOMIC 实现](https://raw.githubusercontent.com/venera-app/venera-configs/main/mycomic.js)、[Keiyoushi MyComic 实现](https://raw.githubusercontent.com/keiyoushi/extensions-source/main/src/zh/mycomic/src/eu/kanade/tachiyomi/extension/zh/mycomic/MyComic.kt)。这些是各客户端实现的第一方代码，**不是 MyComic 官方 API 文档或现场可用性证明**。仅参考协议事实，未执行远程脚本或将上游代码复制进产品。

## 为什么真机仍可能拦截

本轮本机直连及已有代理均收到 Cloudflare `403`，页面明确显示 `Sorry, you have been blocked`。这属于当前访问被拒绝的证据，不能直接推断平板一定失败，也不能承诺平板一定成功。

Cloudflare 官方说明：[WebView/内嵌浏览器支持有限](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/)，[验证 Cookie 与访问者和设备绑定](https://developers.cloudflare.com/cloudflare-challenges/concepts/clearance/)。原生请求和 WebView 是不同的请求环境，浏览器能打开不等于后台请求能读取。保存 Cookie 也不能保证解除明确封禁。

本轮措施：MyComic 的 WebView、元数据请求及图片请求使用相同 User-Agent；仅为该源启用网站 DOM 存储，复用现有独立网站会话。Cookie 仍由既有 `sourceId + origin` 隔离和加密存储机制管理，不向其他图片域名转发站点 Cookie。没有关闭 TLS 校验、设置生产代理或实现自动验证解题。

- 验证页或 `cf-mitigated: challenge`：返回 `AUTH_REQUIRED`，提示在来源网站完成验证并保存会话。
- 明确封禁页：返回 `ACCESS_DENIED`，提示保存会话也可能无法解除。
- 普通 403、429、跳转到其他页面/查询、空或损坏目录：明确失败，不发布不完整目录。

## 模块与行为

- `MyComicSource.ets`：请求、分页、搜索、最新/更新/人气/分类、验证页识别及清单刷新。
- `MyComicFormat.ets`：HTML 元数据、分组目录、静态 JSON 解码、稳定页面键。长数字 ID 不经过浮点转换；不使用 eval。
- `MyComicAccess.ets`：仅共享该源浏览器与请求的 User-Agent。
- 源工厂、站点目录和扩展页注册 `org.hsmihon.mycomic`，默认根网址 `https://mycomic.com/`，内部使用 `/cn/`，适配器版本 1，新源默认停用。
- 图片清单复用现有缓存、下载、文件校验与原子提交链路；不新增数据库或下载实现。

目录按分组处理。编号标题呈单调降序时转为升序；没有足够编号信息或顺序混合时保留网页顺序，不按章节 ID 猜测顺序。这部分仍需要真实多分组元数据复核。

## 已验证与交付

7 组生产解析器/源类定向检查通过：注册与版本、列表与分页隔离、栏目与筛选、分组与长 ID、损坏目录拒绝、页清单与刷新、Cloudflare/HTTP/取消处理。输入为**合成 HTML 和假 Transport**，SDK 由现有 Node loader 替代；不是在线验证。正文图片请求数 0。

Release 无增量构建通过 `CompileArkTS`、`PackageHap`、`SignHap`；构建前后源码摘要一致。构建仍有 SDK/依赖警告。项目当时版本为 **0.9.11 / 29**，本任务未修改版本文件；包包含构建时工作区现有改动，完整源码摘要已归档。

- 候选包：`artifacts/mycomic-html-20261028/hs-mihon-release-default-signed.hap`
- 大小：8,080,789 字节。
- SHA256：`ffa395fadb18bba51dc9a2c34d95e1daf453436fec7c9ad9c699c7848310d08d`
- 永久证据：同目录 `delivery.json`、`checks.json`、`source-snapshot.json`、`build-evidence.json`、`SHA256SUMS`。
- 公开响应、客户端源码快照、临时检查和构建日志：`temp/mycomic-20261028/`，已登记 `temp/list`。其中站点 HTML 是拦截响应，不能作为真实目录/清单样本。

未安装真机；未确认 ArkWeb 能否通过站点验证、会话保存后原生请求是否获准、真实正文图片、下载后重启离线或实际阅读行为。受当前访问拦截和不请求正文图片的边界限制，本轮不能宣称“真机已可用”。没有运行全量测试或搭建测试框架。

本地复核命令（项目根目录）：

```powershell
node temp/mycomic-20261028/check.cjs
powershell -NoProfile -File temp/mycomic-20261028/build.ps1
```

后续设备验收应先确认来源网站可正常打开，再验证会话保存后的搜索、详情和完整目录，之后分别验收阅读、缓存、下载与离线重启。覆盖安装使用 `hdc install -r` 保留用户数据；未通过验证前不要把该源标为已可用。
