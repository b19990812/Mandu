# 漫画源正文取图双通道实施方案

## 开发目标

将 E‑Hentai 的 ArkWeb 二进制取图推广为可按源选择的正文取图通道。原生 HTTP 与 ArkWeb 共用章节页身份、文件校验、缓存和 ArkUI 阅读器。来源可选择默认方式、仅原生、HTTP 优先或 ArkWeb 优先。自动回退只在已验证的来源和错误条件下启用。

首轮范围为**前台在线阅读的正文图片**。列表、详情、章节清单、封面、离线下载、已下载章节及本地导入沿用当前入口。E‑Hentai 的目录仍需要原生元数据请求，目录不可达时，正文开关无法让用户进入章节。MyComic 的目录已使用专门的 ArkWeb 通道，其开关与本方案的正文开关独立。

### 当前入口

| 位置 | 现状及复用点 |
|---|---|
| `source/NativeSourceRegistry.ets`、`source/SourceRegistry.ets` | 分别打开内置源和导入规则源。`SourceHandle.transport` 经 `RegistryTransport` 守卫，绑定源状态和规则版本 |
| `business/ReaderService.ets`、`business/ChapterReaderService.ets` | 普通阅读与网址试读分别构造 `ReaderAssetCache`。试读最后也进入 `ReaderPage` |
| `image/ReaderAssetCache.ets` → `image/AssetTransfer.ets` | 先查缓存并合并同页请求，然后解析取图地址、写临时文件、校验并提交。这是选择通道和回退的接入点 |
| `storage/FileStore.ets`、`image/FileVerifier.ets`、`image/TileDecoder.ets` | 原子提交 JPEG、PNG、WebP 文件，使用 Image Kit 分块解码并管理 PixelMap |
| `network/EhentaiBrowserSession.ets`、`network/EhentaiImagePort.ets`、`ui/EhentaiBrowserHost.ets` | 已有二进制端口、序号和写入确认、空白页导航屏障、取消与浏览器下载回退 |
| `network/MyComicBrowserTransport.ets`、`ui/MyComicBrowserHost.ets` | 目录请求使用持久 ArkWeb，图片流当前仍交给原生传输 |

以上源码路径均相对 `entry/src/main/ets/`。项目当前最低兼容 API 24，目标 API 26。E‑Hentai 的端口、缓存和原生渲染已在 API 26 模拟器用自有样图验证，真实站点与 API 24 的验收单独记录。

## 开关与默认值

| 持久值 | 界面文案 | 新的未缓存正文页如何取图 |
|---|---|---|
| `default` | 跟随来源默认 | 普通源和规则源使用原生 HTTP。E‑Hentai 维持已接入的 ArkWeb 正文路径。MyComic 目录仍走原通道 |
| `native` | 仅原生 HTTP | 只允许原生正文取图。该源的原生正文路径尚未验收时，禁用此选项 |
| `auto` | HTTP 优先，ArkWeb 备用 | 先使用 HTTP。满足回退表且当前源具备 ArkWeb 能力时，尝试一次 ArkWeb |
| `arkweb` | ArkWeb 优先 | 先使用 ArkWeb。仅当该页具备等价且已验收的原生路径时，允许一次原生回退 |

- 首版只做按源选择。入口放在 `ReaderPage` 的阅读设置，显示当前源和生效方式。保存后重新打开阅读器生效，当前章节与已经预备的下一章使用原来的设置快照。
- 持久化复用 `storage/ReaderPreferencesRepository.ets` 的 `reader_settings` 键值表，键用 `reader.image.mode:<sourceId>`，SQL 参数绑定。新增 `readImageMode(sourceId)` 和 `saveImageMode(sourceId, mode)`。旧安装无记录，读出未知值按 `default` 处理。网址回滚、COPY 的 API/Web 选择和下载任务快照各自独立。
- ArkWeb 选项可见性由来源能力决定，不能用“开关打开了”代替来源支持。尚未验收的来源显示“ArkWeb 正文暂不可用”。用户曾保存 ArkWeb 选项但更换到未经核对的域名时，显示有效方式和原因，并以来源默认运行。
- 缓存命中直接返回。切换通道后，用未缓存页或明确的强制重新取图验证，避免将缓存命中误判为新通道成功。

## 代码契约

### 一处选择通道

1. 在 `model/ReaderImageTypes.ets` 集中定义 `ReaderImageMode`、`ReaderImageBackend` 和 `ArkWebImageTarget`。后者只允许两种目标。普通源的 `resolved-url` 由原有 `resolveImage` 提供精确图片 URL，并由审核过的来源配置提供网页上下文。E‑Hentai 的 `ehentai-page` 只接受既有校验通过的正文页，图片由固定的 `img#img` 选择器读取。
2. 给 `SourceHandle` 增加可选的 `readerImages` 能力，记录经过守卫包装的 ArkWeb `Transport`、可信来源配置和已验收的后端。原来的 `transport` 保持给原生正文、元数据、封面及离线入口使用。给 `RequestPlan` 增加可选的内部 ArkWeb 目标和宿主归属，仅在调用 ArkWeb 正文传输时填写。ArkWeb 入口拒绝没有目标、非 GET、非正文或超过原有预算的请求。两条通道都保留 `RegistryTransport` 对源状态、地址及版本的检查。
3. 在 `model/SourceTypes.ets` 增加可选的 `ChapterPageSource.resolveArkWebImage`，由 `RegisteredSource` 守卫转发，首个用途为 E‑Hentai 的正文页目标。它可以直接从当前页身份生成目标，所以 ArkWeb 优先时无需先用原生网络获取这张图的正文 HTML。其他源优先复用 `resolveImage`，每个源只提供必要的上下文和兼容性配置。
4. `ReaderService` 和 `ChapterReaderService` 读取设置快照，把可选的正文取图配置交给 `ReaderAssetCache`，再传入 `transferAsset`。没有正文配置的调用继续走原分支。`AssetTransfer` 是唯一选择主、备通道的地方。`ReaderPage` 挂载宿主和显示设置，`ReaderVM` 传递快照与生命周期；两者都无需判断 HTTP 403、CORS 或重试分支。
5. 每次尝试单独调用一次 `FileStore.writeStream`，让该次尝试拥有独立的 `.part` 生命周期。主通道失败须等写入结束并清理临时文件，再启动备用通道。任何成功结果都通过原 `FileVerifier` 后才提交。禁止在同一 `ByteSink` 内从 HTTP 切到 ArkWeb，否则可能把上一条通道的半张图拼接进去。

交给小模型时，可先按下面的字段约束写类型。这里只约定数据形状。

```typescript
type ReaderImageMode = 'default' | 'native' | 'auto' | 'arkweb'
type ReaderImageBackend = 'native' | 'arkweb'

interface ArkWebImageTarget {
  kind: 'resolved-url' | 'ehentai-page'
  documentUrl: string
}

interface ArkWebReaderRequest {
  ownerId: string
  target: ArkWebImageTarget
}
```

- `RequestPlan.readerImage` 是可选的 `ArkWebReaderRequest`。直链模式下 `RequestPlan.url` 为精确图片地址；E‑Hentai 网页模式下为经校验的正文页地址，和 `documentUrl` 一致。类型中不放脚本、Cookie 或通用 CSS 选择器。
- `RegisteredSource` 只有在代理实现了 `resolveArkWebImage` 时才暴露这个可选方法。调用前后走和 `resolveImage` 同样的守卫。两种请求共享 `pageKey` 和 `ordinal`，回退不重新编号。
- `SourceHandle.readerImages` 只在普通 `open` 提供。固定快照的 `openPinned` 不提供。E‑Hentai 迁移开关时，将原 `EhentaiBrowserTransport` 从通用 `handle.transport` 中移到正文能力。默认仍由网页解析图片，`EhentaiSource.resolveImage` 的原生候选通过原正文 HTML 解析器取得图片。原生路径实测完成前，E‑Hentai 只开放默认或 ArkWeb 优先，避免把正文页 HTML 当图片交给原生读取。
- 存储值表示用户选择，`ReaderAssetCache` 只接收打开阅读器时解析好的有效方式和能力快照。新增能力前不改解析和缓存的公共接口。已有调用在不传正文能力时继续按原行为运行。

### ArkWeb 宿主

- 将 E‑Hentai 的端口协议和会话生命周期提取为共用实现，保留 E‑Hentai 的网页识图、域名、配额与下载处理为来源配置。可以先让现有 `EhentaiBrowserTransport` 调用共用实现以保持行为，再替换原入口。共用文件建议用 `network/ArkWebImageSession.ets`、`network/ArkWebImageTransport.ets`、`network/ArkWebImagePort.ets` 和 `ui/ArkWebImageHost.ets`。提取完成后只维护一份端口协议。
- 宿主按阅读页实例 ID、源 ID、规则或地址版本和上下文 origin 匹配，不能选择最后创建的 WebView。在线且所选方式可使用 ArkWeb 时，阅读器至多挂载一个隐藏宿主；仅原生、离线和本地阅读无需挂载。阅读页实例 ID 由普通阅读入口传入，试读由 `ReaderSession` 带入。将同一 ID 传给当前页和同源手动切章的取图请求，避免切章先加载首图时等待一个尚未挂载的新宿主。若来源配置版本已变，提示重新打开阅读器。
- 保留已验证的 `about:blank` 就绪屏障，等初始空白页或清理导航结束再启动新任务。第一版只复用 WebView 实例。待基础验收后，可单独优化同源、同会话、同网页上下文的普通源复用文档；E‑Hentai 每页按实际正文页导航。
- 维持 `createWebMessagePorts()`、`onMessageEvent`、明确目标 origin 的 `postMessage`、128 KiB 二进制分块、序号和落盘确认。校验握手、累计字节、终止帧和任务归属，过期消息直接丢弃。退出、退后台或切章取消后关闭端口、终止网页读取并释放临时文件。继续关闭隐藏网页自动加载图片。
- 每个宿主同时处理一张图，前台可见请求优先。沿用 `RequestScheduler` 的并发和冷却，每次实际尝试只获取一个网络许可，等待宿主的任务不额外占用许可。首版不对后台预加载触发跨通道回退，ArkWeb 优先的近邻预取最多两张。能使用 ArkWeb 的阅读会话先关闭 `ChapterAhead` 的正文预取，手动切章仍可按现有流程使用同源宿主。

### 回退表

| 首次失败 | 下一步 |
|---|---|
| 网络错误、请求超时、5xx | 在用户选择备用模式、备用已验收且总截止时间还有余量时切换一次。备用与主通道共用 `CancelScope` 和总截止时间 |
| 图片地址明确过期 `IMAGE_EXPIRED` | 先在当前通道用原有 `forceRefresh` 刷新同一页地址一次。页身份不一致时停止 |
| 401、403、验证页或账号权限拒绝 | 提示登录、验证或站点拒绝，等待用户操作。自动回退不以这些状态为触发条件 |
| ArkWeb 脚本无法读图或端口失败 | 只有配置明确声明该页可由原生 HTTP 合法获取时才回退。CORS 与网络失败无法区分时保留“脚本无法读取”的描述 |
| 超过原安全预算、内容校验失败、TLS 错误、本地存储错误、取消、源禁用或版本变化 | 停止并报告具体错误 |
| 429 或站点配额限制 | 沿用冷却并停止当前页，不换通道继续请求 |

使用新模式时，每页最多三次正文尝试，备用最多一次，不从备用跳回主通道。相同 `pageKey` 内刷新次数最多一次。通道切换只处理正文取图失败。若解析图片地址本身失败，只有备用拥有独立解析入口时才有意义。原生独用分支保留现有重试行为。两条路径都失败时，保留各通道的错误码，界面优先呈现用户可以处理的原因。

### 浏览器安全与缓存

- 网页上下文和图片主机分别校验，允许项由应用维护，校验最终地址和每次导航。`UrlPolicy` 当前只做 HTTPS 等基础校验，构造参数里的声明主机没有作为严格白名单使用，所以不能直接作为 ArkWeb 授权。E‑Hentai 的图片节点与端口特例留在它的配置内。对换域、未核对的 CDN 或需跨站跳转的图片，先保留原生路径。
- 浏览器按实际页面发送 Cookie 和 Referer。跨源 `fetch` 依赖站点 CORS 响应，受限头和登录会话由浏览器控制。严禁把源规则里的 Cookie、Referer、User-Agent 或授权头直接注入 JS 请求；确需特定 UA 的源先核对浏览器实例配置。公共来源首批可使用匿名上下文，依赖登录的来源复用获准的浏览器会话。不要按源调用全局 Cookie 清理，也不要把独立 WebView 当成独立 Cookie 存储。
- 正常浏览器下载回退首版仅保留 E‑Hentai 已有实现，通用 ArkWeb 路径只做网页允许的二进制读取。其他源要开放浏览器下载，须单独确认网站授权、最终 URL、文件大小、取消和路径校验。CORS 失败不得引入网页归档提取、Canvas 截取或关闭 TLS 校验。
- 对公开且内容等价的页面，原生和 ArkWeb 使用同一缓存键。通道开关不进入缓存身份，也不修改 `nativeSnapshot`、`SourceChanges` 或书架历史。已登录来源的正文需先处理保留策略，再开放。当前 `BrowserCache.identity` 使用固定 `anonymous`，且 `ReaderAssetCache` 会建立磁盘索引。将私有或保留策略未知的图像写入当前阅读会话的应用私有文件供解码，禁止写入可跨账号命中的索引。退出或登出后，文件等现有 `FilePins` 租约释放再回收。遇到 `no-store` 只留渲染所需的短期文件。浏览器端只传必要的保留策略字段，不传凭据。
- E‑Hentai 现有行为用于卡片 1 的等价验证。新开通的登录源不得照搬其现有的匿名缓存键。
- 保持现有的 32 MiB 安全预算和像素校验，不恢复额外的 2 MB 拒绝规则。实际流量由站点返回的分辨率决定。画质作为后续独立设置；若两个通道能取得不同图质，再在缓存键加入明确的画质标识。不要用通道名代替画质标识。

## 各来源的接入清单

表中所有候选均需按实际网络环境验收后才开放 ArkWeb 选项。

| 来源 | 正文上下文或检查点 | 开发任务 |
|---|---|---|
| 包子漫画、包子漫画 Plus | 共用 `BaoziChapterSource`，原生 Referer 为章节页 | 作为首个普通源试点。单独核对两站的根网址与 CDN，分别发布能力 |
| COPY 漫画 | `CopySource` 与 `CopyApiSource` 的协议由既有配置决定 | 先核对 Web 协议，再核对 API 模式 CDN。保留完整图片路径和签名查询串，取图回退不能切换目录协议 |
| HIP 漫画 | 原生正文 Referer 为 `https://reader.hipmh.top/` | 单独验证合法网页上下文及跨站 Referer 策略，不能直接用漫画源主页替代 |
| Vomic | 图片来源和原生 Referer 来自现有适配器；网站页已有特定 DOM Storage 配置 | 核对正文图片域、Cookie 需求及跨源读取。保留原登录流程 |
| 漫画柜 | 原生正文含 Referer 和指定 User-Agent，当前静态解析保持 | 验证 CDN 的请求头与 CORS，网页只执行站点正常脚本 |
| 漫画库 | 原生解析按选中的线路返回并校验 WebP；目录有专用请求 | 复用精确图片 URL 和当前线路，核对 WebP 与多 CDN 路径 |
| JoyACG | 复用 `resolveImage` 校验的地址及来源站点上下文 | 查清图片域与会话依赖，先验收单张和翻页 |
| E‑Hentai | 复用 `img#img`、配额、动态节点校验及既有 ArkWeb 默认 | 先做通用实现的等价迁移。原生可选分支复用 `EhentaiFormat.ehImageAddress` 解析正文 HTML，实测通过后才开放 |
| MyComic | 持久 ArkWeb 当前服务目录，正文仍原生 HTTP | 独立一期。优先复用现有验证控制器并让目录与正文串行使用；可见验证页拥有优先权。确认退出、重开及账号切换的缓存边界后开放 |
| 导入的 JSON/HTML 规则源 | `RuleSource` 能给出直链，规则声明的主机未经过浏览器授权核对 | 设置入口覆盖该类源。只有应用审查过的规则版本、网页 origin 和 CDN 配置才能启用。规则更新后重新核对，不接收规则注入的脚本 |

## 执行任务卡

按顺序做。每张任务卡单独交付文件清单、验收记录和阻塞原因；上一张通过后再改下一张。命中站点封禁或 CORS 时，将该来源标记为暂不可用，继续完成其余已授权工作。

| 卡片 | 允许修改的主要文件 | 完成条件 |
|---|---|---|
| 1. 提取通用 ArkWeb 会话 | E‑Hentai 会话、端口、宿主和新通用对应文件 | E‑Hentai 通过通用代码运行，默认路径和错误提示一致。API 26 自有 JPEG、PNG、WebP 样图可翻页，旧冷启动 28 秒问题未复现。纯编译不足以完成本卡 |
| 2. 接入开关与原子回退 | 正文取图类型、`ReaderPreferencesRepository`、两类源注册模块、E‑Hentai 适配器和传输包装、`AssetTransfer`、`ReaderAssetCache`、两项阅读打开入口、`ReaderVM`、`ReaderPage` | 默认仍走原路径，开关持久化。使用受控样图把主通道写了一半后中断，确认备用读取成功且结果与样图摘要一致。原生独用时不创建 ArkWeb。切换开关不影响下载固定快照 |
| 3. 普通源试点 | 只改包子漫画对应来源配置；需要时改共用 `BaoziChapterSource` 的上下文生成 | 在真实源验收原生正文和 ArkWeb 正文。章节序号相同，回退仅一次。包子 Plus 单独验收后开启 |
| 4. 扩展其余普通源 | 按上表每次只改一个来源配置或适配器 | 至少验证真实首图、连续翻三页、源配置变更后旧任务取消。每个源独立启用，保留失败原因 |
| 5. 完成登录源及导入规则 | MyComic 会话、来源配置与私有缓存处理；规则源由审核清单启用 | 核对两账号或登录/退出的缓存隔离。MyComic 目录、手动验证和正文互不打断。规则源不能通过配置让 ArkWeb 访问未经审核的 origin |

现有模拟器记录中，包子漫画的目录请求经重定向后返回 403。若复测仍受限，先保留该源默认方式，选择表中当前可访问的普通源完成卡片 3，再回测包子。受控样图可验收通用能力，真实来源验收仍按源记录。

### 最小验收

- 使用已有 `temp/ehentai-image-port-emulator-20261106/` 的 API 26 模拟器样图思路，新增临时记录统一放 `temp/` 并更新 `temp/list`。生产构建使用当前签名的 arm64 Release，模拟器 ABI 使用隔离的 x86_64 lab 副本。
- 卡片 1 更换宿主类后，将隔离 lab 副本的样图请求拦截接到对应宿主，生产实现仍只访问经验证的站点。
- 验证公开图 HTTP 成功、ArkWeb 二进制成功、主通道半文件后备用成功、CORS 受限、401/403/429 无自动回退、切章取消后旧数据未提交、再次打开命中缓存。普通源抽查一次封面与已有离线任务，保护原入口。
- Release 构建用 `.\tools\dev.ps1 -Action Build -Mode release`。模拟器验证完成后，按用户授权在 API 26、API 24 真机覆盖安装，不卸载应用或清除数据。报告中分别列出编译、样图与真实源结果，成功证据记录所选通道、失败码、字节数和页序，隐藏 URL 查询串、Cookie、Token 和标题。
- 单元测试与回归套件按项目约束执行。任务卡中列的是与通道、缓存、取消和安全直接相关的定向验证，禁止因某个源故障而扩大成全量回归。

>

## 接口依据

二进制通道以本项目安装的 SDK 声明为准，使用基础消息协议。浏览器 Fetch 的 CORS、凭据和重定向限制适用于全部来源。[华为 WebMessagePort 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webmessageport/) · [WHATWG Fetch 标准](https://fetch.spec.whatwg.org/)
