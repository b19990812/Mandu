# COPY API 接入：0.9.2

日期：2026-10-28（Asia/Hong_Kong）。实现依据：[1.4.85 协议分析](copymanga-1.4.85-analysis-2026-10-28.md)。本文记录本轮新增实现和实时元数据证据，不改写原静态分析的历史范围。

## 使用方式与交付物

进入「更多 → 自定义网站 → COPY → 修改网址」，选择「API（匿名浏览与阅读）」或「网页」。API 与网站地址分别保存。API 输入只填写 HTTPS 根网址，例如 `https://api.copy4000.com/`；代码自动拼接 `/api/v3`。

没有保存过接入方式的旧设置默认使用 API，默认线路为 `https://api.copy4000.com/`。内置六个 COPY 候选地址，也可手动输入符合现有公网 HTTPS 规则的根网址。候选地址源自已分析的 APK；本轮只验证默认线路，其他线路未验证。失败时不自动切换线路或协议。

- [0.9.2 Release signed HAP](../artifacts/0.9.2/hs-mihon-release-default-signed.hap)，versionCode 20，7,965,784 字节。
- SHA-256：`a368f37d03e1c46dcc9ffe796b6b555d713ba400ca695bb452070313a7bc9a59`，见 [SHA256SUMS](../artifacts/0.9.2/SHA256SUMS)。
- 本轮未安装到设备。如需覆盖安装并保留数据：

```powershell
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r .\artifacts\0.9.2\hs-mihon-release-default-signed.hap
```

## 已接入的功能

| 功能 | API 路径与规则 |
|---|---|
| 搜索 | `/search/comic`，每页 21 项，关键词编码，`q_type` 为空，`_update=true` |
| 推荐 | `/recs?pos=3200102`，解析每项 `comic` |
| 新上架 | `/update/newest`，解析每项 `comic` |
| 热门、更新、分类 | `/comics`，支持题材、地区/完结分区、免费/付费、排序 |
| 完结 | `/comics?top=finish`；不是网页协议的 `status=1` |
| 排行榜 | `/ranks?type=1`，周期与男/女频筛选，解析每项 `comic` |
| 题材 | `/theme/comic/count?limit=100`，从真实返回清单生成可选项 |
| 详情 | `/comic2/<path_word>`，作品身份、作者、标签、简介、状态和封面 |
| 目录 | `/comic/<path_word>/group/<group>/chapters`，逐组每批 100 项 |
| 图片清单 | `/comic/<path_word>/chapter2/<uuid>`，解析 `results.chapter.contents + words` |

目录按服务端分组次序逐组拼接；组内按数值 `index` 升序，以匹配本项目按 ordinal 前进的下一章行为。非 default 分组在标题前保留组名，不按标题数字猜章序。现有目录模型仍是平面列表，没有增加数据库分组字段。

目录最多 100 批、10000 章。校验分组 count、每页 total、offset、章节所属作品/分组、UUID 与序号重复、空批次和最终总量；失败时不返回部分目录供持久化。

图片先把 `contents[i]` 与 `words[i]` 配对，再按权重升序排序。权重缺省、null 或空数组时保留内容顺序；拒绝数量不匹配、重复/非法权重、重复页面身份或不在正文白名单中的 URL。清单最多 2000 页。

**本轮真实协议发现：章节 `count` 是该分组的章节数，`size` 才是该章页数。** 新样本中 `count=6`、`size=43`、contents/words 均 43 项；不能拿 count 校验页数。实现按存在的 size 校验，不把 count 当页数。

## 模块与网络边界

- `source/adapters/CopyApiSource.ets`：搜索、详情、完整目录、章节清单和图片刷新。`CopyApiClient.ets` 负责有界 JSON GET、状态/结构/分页校验；`CopyApiFormat.ets` 负责身份和数据映射。
- `source/discovery/CopyApiDiscovery.ets`：七个首页栏目与 API 筛选。旧 `CopySource` / `CopyDiscovery` 继续承载网页协议，由工厂按设置选择，不在解析失败后静默回退。
- `source/CopyAccess.ets`：接入方式、API 候选地址、适配器版本和快照描述。API 版本为 2，网页版本为 1；不修改其他内置源的旧快照内容。
- `SourceSiteService` / 设置仓库 / `SourceSitesVM` / `SourcesPage`：在现有设置结构中增加可选 COPY 字段，保持旧 schemaVersion 1 可读取。一次保存同时提交网站、API、接入方式并增加 revision，使用原有冲突和取消通知机制。
- `network/CopyApiPolicy.ets` / `RcpTransport`：只有内置 COPY 注册表安装的精确 API origin + `/api/v3/` 路径使用固定 API 头；普通适配器仍只能声明原来的四类头。`Origin`、`Version`、`platform` 等不透传给 CDN 或其他源，不开放任意 Authorization。

COPY API Transport 使用 anonymous 模式，不读取网页 Cookie，不携带 Authorization。当前实现没有登录、token 获取或源站书柜功能；认证/访问拒绝会明确报错，不尝试越权内容。WebView 网站设置与保存 Cookie 的旧网页流程独立保留。

API 元数据请求按本轮分析保留最短 100ms 启动间隔；图片仍使用原调度、流式下载与缓存通路。TLS 继续使用系统证书校验；API 拒绝跨 origin 或离开 `/api/v3/` 的重定向。HTTP 210、401/业务 401、HTML、错误 JSON、错误分页均不视为清单成功。

在原精确正文主机清单基础上，**仅为 API 增加 `sy.mangafunb.fun`**：这是本轮真实 `chapter2` 元数据返回的图片主机；没有请求其图片字节，没有启用通配符。

## 身份、缓存与旧数据

稳定源 ID 仍是 `org.hsmihon.copy`。作品 remoteId 保持 path_word，章节 remoteId 保持 `<path_word>/<uuid>`，locator 保持原网页路径 `/comic/.../chapter/...`；只有发 API 请求时使用 `chapter2`。不会创建重复源或删除书架、阅读进度、离线文件。

快照包含适配器版本、网页地址、API 地址、接入协议、`resolution=source` 与会话类型。线路/协议改变会生成新快照并取消旧请求；旧快照下载任务不能直接继续，需要取消后按当前源重新入队。已有完整离线快照仍可由现有离线阅读通路读取。

不强制改写分辨率 URL，保留源站 URL、query 及 pathname 页身份。清单刷新仍按 pageKey 查找原页；找不到时返回 CONTENT_CHANGED，不能以相同下标替代。

实际身份对照：已保存的网页样本 `naoodngxueshenghui` 共两个分组、233 章，本轮 API 也返回 233 章，旧 233 个 id 全部与 API uuid 匹配；章节 `50fea5ac-c587-11ec-8361-024352452ce0` 的 17 个页面 pathname 及顺序与旧网页解码清单一致。这仅证明该样本，不宣称所有作品已完成身份对照。

## 验证记录与剩余边界

- 默认 API 通过 Node 标准 HTTPS/TLS 获取 17 个公开元数据响应，全部 HTTP 200 / JSON：推荐、搜索、热门、更新、完结、新上架、榜单、题材、两个详情、两个章清单及目录分页。响应在 `temp/copy-api-20261028/live-*.json`，探测摘要为 `probe-result.json` / `probe-extended-result.json`。最初 PowerShell 请求遇到 SSL 错误；Node 成功不代表 HarmonyOS RCP 或设备 TLS 已验收。
- 15 组最小定向主机检查通过：生产 ArkTS 解析真实 JSON，覆盖排序、完整目录、身份、刷新、异常、设置、快照和 RCP 请求头隔离。结果为 `temp/copy-api-20261028/checks.json`。复用已有 Node loader；RCP 调用由替代适配器检查，不属于真机网络证据。
- 最终 Release：`CompileArkTS`、`SignHap`、`BUILD SUCCESSFUL`。构建日志 `temp/logs/Build-release-20261028-083200.log` 与任务目录控制台日志。SDK 能力/异常处理警告仍存在，未把警告当作运行验收。
- 未运行全量测试；本次按核心目录与网络边界改动执行上述定向检查和 Release 构建。没有图片请求、账号操作、设备安装或 UI/整章下载/重启恢复验收。

复核命令：

```powershell
node .\temp\copy-api-20261028\check.cjs
.\tools\dev.ps1 -Action Build -Mode release
```

后续设备确认重点：默认 API 搜索 → 详情 → 正文首图与全章页序 → 换章 → 下载/重启离线；确认原书架作品的继续阅读位置，并确认网页/API手动切换设置。登录或新的 CDN 域名应另行接入并保留精确 origin 与账号缓存隔离，不能通过放宽现有白名单完成。
