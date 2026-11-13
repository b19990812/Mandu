# 漫画源解析链路与加载性能优化方案

日期：2026-11-05（Asia/Hong_Kong）。范围：当前工作区的源首页、详情目录、章节图片加载。本文是只读代码审查和实施建议；未修改业务代码，未运行构建、自动测试或真机网络测量。工作区已有未提交的源接入和阅读器修改，以下结论针对当前文件，不代表已安装 HAP 的实际版本。

## 1. 结论与证据边界

源码可以确认：重复获取同一作品元数据、首页缺少结果缓存、完整清单阻塞起读、前后台共享名额且优先级不完整、图片缓存维护位于返回图片之前。建议先优化这些可消除的请求和等待，再依据设备计时调整连接与并发。

这些是确定存在的实现行为，但其各自占实际加载时间的比例尚未测量。源站 TTFB、DNS/TLS、代理链路、磁盘和解码均可能贡献延迟，不能把所有缓慢都归因于 HTML 解析或某一个网络参数。

## 2. 当前解析方法

一般链路为：页面 VM → 业务 Service → RegisteredSource → 原生适配器或规则引擎 → RegistryTransport → RequestScheduler → RcpTransport → HTML/JSON/静态数据解析。MyComic 元数据走保留的 ArkWeb 上下文；其图片仍由 RCP 下载。

| 源 | 首页/搜索 | 详情和目录 | 章节图片清单 |
|---|---|---|---|
| 包子、包子 Plus | HTML + htmlparser2 + 选择器 | 同一作品 HTML 提取详情、章节链接；两个方法分别请求 | HTML 中的 amp-img；可能有多段网页分页 |
| COPY API 模式 | JSON API | comic2 返回详情/分组；每组章节按 100 条分页获取 | chapter2 JSON 提取图片地址 |
| COPY 网页模式 | 首页 HTML，搜索 JSON | 作品 HTML 读取元数据及 ccz，再获取加密目录并本地解密 | 章节 HTML 中 contentKey/cct，本地解密 |
| HIP | 首页 HTML，搜索 JSON API | 作品 HTML 提供目录配置；章节 API 按 50 条分页 | v2/chapter JSON，加本地清单解码 |
| Vomic | 首页 HTML，搜索及其他栏目 API | getCartoonInfoV1 同时含详情、目录；两个方法分别请求 | 章节页静态阅读数据及图片列表解码 |
| 漫画柜 | HTML | 同一作品 HTML；两个方法分别请求 | 阅读页静态 P.A.C.K.E.R/LZ-String 数据解包，不执行远程脚本 |
| 漫画库 | HTML | 作品 HTML + 无请求体 POST /comic/<id> 的 JSON 目录 | JSON 目录 → 章节 HTML → source-lines JSON → 图片地址 |
| MyComic | ArkWeb 同源 fetch 获取 HTML | 作品 HTML 和 x-data 中的静态章节数据；两个方法分别请求 | 章节 HTML 的图片属性 |
| JoyACG | HTML | 同一整本页面包含详情、单一“整本”章节和全部图片；多次独立读取 | 再次获取同一页面提取 galleries 图片 |
| 导入规则 | 有限 HTML/JSON 规则 | 按规则配置执行 | 按规则配置执行 |

适配器入口见 [NativeSourceFactory](../entry/src/main/ets/source/NativeSourceFactory.ets)。HTML 解析器见 [HtmlExtractor](../entry/src/main/ets/source/rules/HtmlExtractor.ets)，选择器见 [SelectorSubset](../entry/src/main/ets/source/rules/SelectorSubset.ets)。当前 HTML 会整页建树，多次选择器调用递归扫描；仅从这种结构不能断言 CPU 解析是主因。

## 3. 首页进入慢

### 3.1 源首页没有栏目结果缓存

[SourceHomeVM](../entry/src/main/ets/vm/SourceHomeVM.ets#L32) 初始化后直接 load；load(false) 清空已有列表，再等待远程 browse 返回。SourceDiscoveryService 只转发请求，没有栏目结果缓存。用户重新进入页面、切换栏目或刷新时容易再次经历空白等待。

建议：

- 增加共享的首页结果缓存，键包含 sourceId、snapshotKey、站点地址版本、会话版本、栏目、规范化筛选和分页。
- 已有结果先显示；过期时显示刷新状态并在后台更新，失败时保留旧结果。全新筛选不能误展示其他筛选的缓存。
- 初始参数可取首页新鲜期 5 分钟、分类字典 24 小时，作为业务缓存策略候选；不得覆盖 HTTP 的 no-store 等指令或跨会话复用数据。
- 同一键的并发请求合并；取消一个消费者不应中止其他消费者仍需的请求。
- 当前 Grid 已使用 LazyForEach 和 cachedCount(1)，继续保留；封面应按可见区域开始请求。

### 3.2 每个封面重复打开源

[MangaCover](../entry/src/main/ets/ui/MangaCover.ets#L32) 为每张封面新建 AppContainer、registry.open 和 ReaderAssetCache。NativeSourceRegistry.descriptor 又涉及站点设置、数据库状态、摘要和版本快照；图片缓存命中前仍有这些开销。

建议共享有界的封面服务及当前源句柄，复用正在加载的相同封面。句柄按源/地址/启停/会话版本失效，保留旧结果隔离。封面属于独立的低优先级任务，离屏时取消或降级；源站明确提供缩略图时使用其缩略图，不臆造图片压缩参数。

应用默认“书架首页”的条目数据来自本地数据库，并非必须等待漫画站请求；其封面同样走 MangaCover。若慢的是应用初始打开，应把本地列表显示、封面显示、MyComic 浏览器宿主准备分开计时，不能直接沿用源首页诊断。

## 4. 目录加载慢

### 4.1 详情和目录重复获取同一份数据

[CatalogService.refresh](../entry/src/main/ets/business/CatalogService.ets#L24) 先 await details，再 await chapters，并在全部目录完成后保存和通知页面。

下表为一次冷目录刷新的正常逻辑请求数，不含封面、重试、重定向、浏览器初次导航，也不代表实际网络实测：

| 源 | 当前 | 去重后的目标 |
|---|---|---|
| 包子/Plus、漫画柜、MyComic | 同一作品 HTML 2 次 | 1 次 |
| Vomic | 同一 info API 2 次 | 1 次 |
| JoyACG | 详情、目录、进入整本阅读共 3 次相同页面 | 短期有效期内共享 1 次结果 |
| 漫画库 | 作品 HTML 2 次 + 目录 POST 1 次 | HTML 1 次 + POST 1 次 |
| COPY API | comic2 2 次 + 目录各分页 | comic2 1 次 + 目录各分页 |
| HIP | 作品 HTML 2 次 + 目录各分页 | HTML 1 次 + 目录各分页 |

建议在每个适配器内部实现有界的作品元数据加载器：一次下载和解析，同时产出详情、目录配置或完整目录，供 details/chapters 共享。先沿用现有 Source 接口，避免为去重立刻修改所有源。只有当前适配器实例的缓存能覆盖单次 refresh，跨页面复用则还需共享的、带版本键的缓存服务。

共享键必须包含方法、完整 URL、源快照及会话身份；漫画库 POST 仅在明确的只读目录操作中做结果复用，不泛化为所有 POST 缓存。刷新、网址/规则/会话变化、内容身份校验失败时失效。

### 4.2 分页和保存均在可见目录之前

COPY API 的分组与分页、HIP 的目录分页目前逐个等待。能从已验证的首包确定独立分页范围的源，可尝试小窗口并发（初值 2），汇总后检查总数、顺序、重复、身份及快照一致性。只有下一页游标返回后才能确定请求的规则源继续顺序读取。

[CatalogRepository.saveDetail](../entry/src/main/ets/storage/CatalogRepository.ets#L53) 还会逐章计算摘要，在单事务中逐章 INSERT/UPDATE；旧 ID 使用数组查找。ReaderDatabase 把所有读写排在共享队列中。千章目录可能有明显本地开销。

建议先测 saveDetail/数据库排队，使用 Set 查找、分批准备和平台支持的批量写入，保持原有稳定 ID、进度关联和完整快照事务。简单把现有数据库读取改成 Promise.all 不会绕过其内部串行队列。

已有目录目前能直接本地显示，见 [DetailVM.initialize](../entry/src/main/ets/vm/DetailVM.ets#L31)。保留此行为。新增目录“先显示一部分”属于更大的接口/UI 改动：预览批次应与正式目录隔离，不能因分页尚未结束就 active=0、删旧章或标记更新完成。

## 5. 漫画首图和翻页加载慢

### 5.1 起读等待整章清单

[ReaderService.open](../entry/src/main/ets/business/ReaderService.ets#L37) 在线模式先完整调用 [collectChapterManifest](../entry/src/main/ets/business/ChapterManifest.ets#L8)，之后才构建图片缓存并交给 ReaderVM 开始取图。因此即使之前缓存过图片，重新打开在线章节仍先读取清单；包子多段章节尤其容易累计多次网页等待。

建议按风险分两步：

1. 先做短期有效的章节清单缓存，键绑定源快照、会话版本、章节身份；保留稳定 pageKey。命中后优先准备当前阅读位置，远程签名失效时再合并刷新。
2. 后续才考虑增量起读：首批清单验证后显示首图，后台追加其余批次。必须新增“清单未完成”状态，完成前禁止误判章末、自动换章、已读完成或完整下载；恢复位置位于后续批次时需继续收集至目标页。不能直接删除完整性校验。

漫画库每次 pages 的三个串行请求见 [ManhuakuSource](../entry/src/main/ets/source/adapters/ManhuakuSource.ets#L50)。优先复用目录 JSON、按 source-line ID 缓存线路配置；只在真实依赖满足时并发请求，不猜测章节或线路数据。

### 5.2 共享并发名额，且背景请求可能被当作前台

[RequestScheduler](../entry/src/main/ets/network/RequestScheduler.ets#L16) 当前限制为全局 4、每源 2、每域名 2。优先级通过 callId 前缀识别：download 为 2，reader-prefetch 为 1，其他全部为 0。

因此 cover、reader-prerender-asset、strip-* 都可能与用户当前请求同级。预取已经开始占满同源两名额时，新前台请求只能等待；排序只影响排队项，不能腾出已运行请求。ReaderAssetCache 的同页共享请求也没有把排队中的预取提升为当前页请求的机制。

建议：

- 用显式用途/优先级替代字符串前缀，区分当前可见页、用户目录/首页操作、临近预取、可见封面、远期预取、下载；队列设置等待老化，避免低优先级永久饥饿。
- 先保持总上限，限制后台任务占满同源容量。当前单页保留至少 1 个可用前台名额；双页按两张可见图整体安排。
- 当前页命中已有预取任务时，共享并提升该任务优先级；不重复下载。只能在可安全恢复时取消远期预取来让出名额。
- 20 张是预取窗口，不是 20 并发；当前 ReaderPreloader 自身最多 2 并发。保留用户的窗口设置，对实际启动量按前台需求、失败率和网络质量自适应。
- 完成基线测量后，才分源评估全局 4→6、每源/域名 2→3或4；它们只是候选实验参数。出现 429、失败率或内存增加则退回。

### 5.3 缓存维护也会延迟“图片已下载”后的返回

[BrowserCache](../entry/src/main/ets/image/BrowserCache.ets#L38) 命中后立即写 usedAt；put 每次写索引后调用 trim，扫描全部缓存索引。FileStore.writeText 包含 fsyncSync；目录枚举、读取、stat 和删除也使用同步接口。

[ReaderAssetCache.download](../entry/src/main/ets/image/ReaderAssetCache.ets#L84) 在返回图片前 await disk.put。因此缓存越大，逐图扫描和全局锁越值得单独测量。

建议把命中时间合并写回，维护可重建的内存索引/大小计数，清理改为阈值触发和有界分批；避免每张图都扫描全目录。保留正在阅读的文件引用保护和原子提交。浏览缓存属于可重建数据，其耐久性策略可单独评估，不顺带放宽离线下载、书架或进度的保存要求。

### 5.4 失败时的重复清单刷新

[AssetTransfer](../entry/src/main/ets/image/AssetTransfer.ets#L9) 对图片有限重试，遇 401/403/过期会调用 resolveImage(refresh=true)。[refreshPage](../entry/src/main/ets/source/RefreshPage.ets) 从章节第一批重新查找图片。多图同时失效可能重复拉取同一章节清单。

建议按章节合并一次清单刷新、设置短暂刷新冷却；优先识别明确的验证页/权限拒绝。网络错误使用有界退避并共享页面操作截止时间，保留 Retry-After。当前元数据 send 最多 3 次，图片 streamToFile 自身不走 send 的三次循环，图片重试在 AssetTransfer；不能简单算成所有请求固定 3×3。

## 6. RCP 与 MyComic 专项

### RCP

[RcpTransport.once](../entry/src/main/ets/network/RcpTransport.ets#L112) 每次创建 Session、完成后 close；未开启 collectTimeInfo，也未配置 ResponseCache。

建议引入有界 Session 复用，按源版本、隐私/会话、代理及安全配置隔离；只 cancel 对应 Request，连接池退出时才 close。它是待验证的优化候选，新 Session 并不等于已证实的新 TCP/TLS。

官方能力：connectionReusePolicy 自 API23，默认 naive，可评估 balanced；ResponseCache 自 API20；collectTimeInfo 可用于阶段计时。API24 可使用这些能力，但 httpVersionSelectCallback 要 API26，不宜无条件启用。见 [华为 RCP 官方 API](https://developer.huawei.com/consumer/en/doc/harmonyos-references/remote-communication-rcp)。

公共 GET 可评估 HTTP 缓存和 ETag/Last-Modified 条件请求；源响应允许时复用，处理 304 后再交解析层。当前请求头白名单和 requireHttpSuccess 不直接支持完整的条件缓存链路，需要连同缓存读取一起设计。不要把 304 空 body 当 HTML/JSON。缓存语义见 [RFC 9111](https://www.rfc-editor.org/rfc/rfc9111.html)。

当前连接上限 30 秒、操作通常 60 秒；加大超时只能提高慢链路等待成功的机会，不能提速。项目 [历史设备记录](device-image-0.8.3.md) 曾出现约 15.7 秒握手后成功，也有 30 秒超时；这不是今天的网络测量。旧的两层 500 毫秒固定等待已移除，见 [0.8.1 记录](network-pacing-0.8.1.md)，不应再次作为待实施方案。

### MyComic

当前元数据通过 [MyComicBrowserSession](../entry/src/main/ets/network/MyComicBrowserSession.ets) 的串行 ArkWeb 通道读取，fetch 为 no-store，100 毫秒轮询完成状态，再每 8192 字符一次跨 Web 边界搬运正文。prepare 在 origin 不匹配时先 loadUrl，随后还会 fetch 目标页，初次访问可能包含额外导航。浏览器 busy 等待发生在获取全局网络名额之后。

优先去重详情/目录、缓存允许缓存的解析结果、避免浏览器 busy 等待占用全局网络名额。后续可评估复用已完成导航的正文、按验证后的桥接容量调大分块或提取最小静态载荷；继续验证完整性、大小和同源条件。100 毫秒轮询是单次发现完成的等待粒度，不能误称每个 8192 字符块都固定等 100 毫秒。

需要验证时应明确提示用户完成站点验证，网络调优不能保证解除 Cloudflare 拦截。

## 7. 实施顺序与模块边界

| 阶段 | 工作 | 主要模块 | 风险和验收点 |
|---|---|---|---|
| P0 | 最小阶段计时，记录基线 | RcpTransport、Scheduler、页面业务边界 | 不采集正文、Cookie、签名 URL；定位真实耗时占比 |
| P1 | 详情/目录共享加载；漫画库目录与线路复用 | 各源适配器及小型共享缓存 | 对应重复请求消失；源版本切换仍拒绝旧结果 |
| P1 | 首页先显示缓存并刷新；封面共享和可见区域调度 | SourceDiscoveryService、SourceHomeVM、封面服务 | 相同栏目可恢复，手动刷新与会话失效正常 |
| P1 | 显式优先级、前台保留容量、预取任务提升 | RequestTypes、Scheduler、ReaderAssetCache | 并发/公共上下文改动，需直接相关的最小验证 |
| P2 | 有界 RCP Session、条件缓存、缓存维护优化 | 传输层、BrowserCache | 核对阶段耗时、命中率和取消隔离 |
| P2 | 已知范围目录分页小窗口并发、批量目录保存 | 各源、CatalogRepository | 保留完整目录提交、顺序、身份、进度关联 |
| P3 | 增量目录/章节起读 | Source/Reader 会话与 UI | 改动较大；明确未完成态、恢复位置和章末语义 |

缓存服务负责键、有效期、并发合并和失效；适配器负责站点解析与身份校验；调度器负责名额和优先级；VM 负责展示状态。避免将站点 JSON/HTML 解析搬到页面，避免新增全局大对象统一管理所有业务。

## 8. 最小测量与验收计划（尚未执行）

分别记录：点击→列表可交互、点击作品→目录可交互、点击章节→首张可见、翻页→下一张可见。各阶段记录队列等待、DNS、TCP、TLS、TTFB、传输、解析、数据库排队/写入、缓存维护、解码和首次显示。网络字段若为累计值，应按官方定义求差，缺失时不伪造。

只选择实际使用的最慢源和一个对照源，覆盖冷缓存/热缓存、单独前台/伴随预取或下载；保持设备、站点地址、章节、代理路径一致。先做少量定向测量，发现波动后再扩充样本，样本不足时报告中位数/范围，不包装为稳定 P95。速度变化同时报告成功率、429/403、重试和流量。

优先用结构目标验收：同一次刷新不重复获取作品元数据；缓存首页能在远程完成前显示；当前页不再被新发起的远期预取挤满名额；缓存写入不再每图扫描全目录。真实网络提速比例必须在实施后测量，不预先承诺。

本次仅产出方案，未运行单元、集成、端到端或全量回归，也未安装/启动设备应用。后续实施完成时可先运行项目构建命令 `./tools/dev.ps1 -Action Build -Mode release`；构建只验证编译/打包，不替代上述真实源阶段计时。没有为本方案新建临时脚本、响应或日志，因此无需新增 temp/list 条目。
