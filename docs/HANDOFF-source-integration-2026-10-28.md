# 漫画源接入与 COPY 故障交接

更新时间：2026-10-28，Asia/Hong_Kong。工作目录：`E:\AI_coding\HS_mihon`。

> 后续增量见 [0.9.1 源适配进展](source-adaptation-2026-10-28.md)：已新增 Vomic 原生实现、补齐 HIP 搜索 API 分页并完成合成下载链路定向检查；签名候选包已生成，真实登录和设备下载仍待验收。本文以下保留原交接时点状态。

**交接结论：任务尚未全部完成。当前已有仓库目录管理、HIP 原生适配器、包子 Plus 独立身份接入；Vomic、漫蛙、JoyACG、E-Hentai 尚未完成适配，COPY 正文故障尚未修复。0.9.0 签名构建成功不等于全部源可用。**

## 1. 用户目标与当前优先级

1. 实现类似 Mihon 的源仓库导入，并接入下列传统索引中的源：
   `https://raw.githubusercontent.com/LittleSurvival/copymanga-copy20/repo/index.min.json`。
2. 用户随后调整优先级：**首先适配新源**，并增加 `https://joyacg.cc/`、`https://e-hentai.org/`。
3. 原有 COPY 故障仍需处理：首页、分类、热门及漫画名称正常，进入章节后正文加载失败；用户反馈“任何一个都不行”。不能因优先级调整而遗漏此问题。
4. 用户最新要求本轮整理 handoff，供下一会话继续，因此本轮收束开发，不再扩展适配。

### 必须继承的限制

- **不要查看漫画内容或截图，仅从底层解析缓存和下载机制。** 后续不打开正文、不截图、不展示真实漫画图片。可检查代码、协议字段、状态码、分页、地址结构、缓存键和合成数据。
- 上述限制提出前曾进行 COPY 平板复现及一次历史样本图片字节请求；不要复用这些脚本做新的正文请求。限制提出后，新增定向检查均未请求正文图片。
- JoyACG：用户确认“该网站通过浏览器访问还是可以”。本机 Node 的连接重置只是访问通道差异，**不是网站不可用的结论**。
- 最小必要验证：不跑全量回归、不新建测试框架；本次解析、网络边界属于核心链路，允许相应定向检查。
- 临时脚本、响应、日志一律放 `temp/`，每次变更同步 `temp/list`；长期交付文档放 `docs/`。
- 不清除应用数据、不卸载旧版；若安装用 `hdc install -r`。不得输出根构建配置中的签名凭据。
- 未获用户要求，不启动子 Agent，不写入个人记忆。

## 2. 当前代码与构建状态

| 项目 | 已核实状态 |
|---|---|
| 应用源码版本 | `AppScope/app.json5`：0.9.0 / versionCode 18 |
| SDK | 继续 API26 编译/目标，min API24；本轮未改变 |
| 阅读数据库 | 未新增表/迁移；仓库目录使用已有 `reader_settings` |
| 最新 Release | CompileArkTS、PackageHap、SignHap、assembleHap 均成功 |
| HAP | `artifacts/0.9.0/hs-mihon-release-default-signed.hap`，7,908,283 字节 |
| SHA256 | `0ba310bb25f68a82bb5b9e8e8a187fee9aa4ce692c7ec841582237bf2fb51205` |
| 摘要文件 | `artifacts/0.9.0/SHA256SUMS` |
| 构建日志 | `temp/source-integration-20261027/release-build-console.log`；另有 `temp/logs/Build-release-20261028-*.log` |
| 设备安装 | **0.9.0 未安装、未做 UI 验收。** 本会话最后一次实际安装的是带临时 COPY 日志的 0.8.6 诊断版本 |
| 诊断代码 | 当前源码已移除 `[DEBUG-copy-format]`、`[DEBUG-copy-path]`；0.9.0 不包含这些日志 |
| README | 版本介绍仍为此前 0.8.6，未宣称 0.9.0 已完成发布验收 |
| Git | 当前项目根未发现 `.git`；无本轮 commit/PR，不要假定能通过 git diff 恢复现场 |

**注意设备与文件并不同步：** 后续重建覆盖了 `temp/.../diagnostic-signed.hap`，该文件名不能用于推断平板当前安装内容。继续时应选择上述 0.9.0 正式路径，或重新构建新的候选包；不要把诊断包当交付包。

## 3. 各源状态

| 源 | 当前落地 | 已有证据 | 待完成 |
|---|---|---|---|
| COPY | 保留现有原生适配器；仓库可关联 | 平板失败点定位到空 `contentKey`；历史样本解析正常 | 实际章节空清单原因、修复与元数据链路验证 |
| 包子漫画 Plus | 新稳定 ID `org.hsmihon.baoziplus`，网址 `https://www.webmota.com/`，复用包子协议实现，默认停用 | 公开页面结构与原包子同族；独立身份、工厂、构建完成 | 尚未完成此域名的真实目录→清单闭环；需要元数据校验，不能按已可读验收 |
| HIP | 新 `org.hsmihon.hipmh` 原生适配器，默认停用 | 当前协议元数据样本：47 个首页条目、完整 69 章、清单解码后 7 个页面地址；未请求图片 | 搜索分页、更多栏目、更多清单边界及设备底层链路；缓存/下载合成数据验证 |
| Vomic | 只有目录记录与调查资料，**无原生适配器** | 公开详情与目录可获取；章节未登录响应 `isLogin:false`，空 `chapterData`；公开客户端使用 `_token` | 接入认证后的 SSR/API 清单，安全复用站点会话；不要求用户提供密码给 Agent |
| 漫蛙2+ | 只有目录记录与上游实现参考，**无原生适配器** | 上游包含 HTML 选择器及部分图片解码；指定域名请求重置 | 获取可靠协议元数据、核实图片编码及流式下载处理位置 |
| JoyACG | 扩展页中列为新增待适配网址，**无执行源** | 用户浏览器可访问；本机直接请求失败，协议未确定 | 查明访问通道/会话差异，获取不含正文的结构信息，再设计适配器 |
| E-Hentai | 扩展页中列为新增待适配网址，**无执行源** | 检索通道访问返回 451；只调查到公开客户端项目，尚未取得足够协议证据 | 画廊到单章节映射、分页、图片页二次解析、动态图片域名、限额与缓存策略 |

原有包子 `org.hsmihon.baozi`、COPY `org.hsmihon.copy` 的 ID 和默认启用行为保留。包子 Plus **没有合并到旧包子 ID，也没有改写旧书架来源**。

## 4. 已新增和修改的模块

以下路径均相对 `E:\AI_coding\HS_mihon`。

### 4.1 仓库目录管理

- `entry/src/main/ets/source/ExtensionCatalog.ets`
  - 解析传统扩展数组，校验包名、版本 code、NSFW、源列表、HTTPS 网站地址及重复身份。
  - 使用 `JsonExtractor` 保留长整数 ID 的原始十进制文本，不经过 JS Number 转换。
  - 只对指定仓库及已知 `pkg + externalId + host` 关联本项目实现；其他仓库不会因同名而自动关联。
  - COPY、包子 Plus、HIP 有原生关联；其余显示明确的待适配状态。
  - JoyACG/E-Hentai 目前仅为状态条目，不能宣称已经安装源。
- `source/ExtensionRepositoryService.ets`
  - HTTPS `index.json`/`index.min.json`，最大 512KiB，最多 8 个保存仓库。
  - `reader_settings` 的 `extension.repository.<SHA256(address)>` 保存 `[address, rawIndex, timestamp]`，避免属性混淆破坏持久化协议。
  - 预览之后才保存；事务内检查前一记录，拒绝并发覆盖；拒绝已存在条目的版本 code 倒退。
  - 删除目录不删除源、书架或下载。
- `vm/ExtensionManagerVM.ets`、`pages/ExtensionManagerPage.ets`
  - 地址输入→读取预览→确认保存→关联/启用原生实现；查看本地目录、检查更新、移除目录。
  - 无图像卡片，使用文字显示版本、网址、18+ 标记与适配状态。
- `app/AppContainer.ets` 新增 `extensionRepositories`。
- `ui/BrowsePanel.ets` 新增“扩展仓库”入口。
- 页面已加入 `entry/build-profile.json5` 的 **default 和 lab**，以及 `entry/src/main/resources/base/profile/main_pages.json`。

当前实现是第一阶段目录管理，不包括 APK 运行环境、规则包远程安装、完整兼容版本映射、签名信任链、安装状态模型、所有计划中的更新差异预览。原详细方案仍在 `docs/source-repository-import-plan-2026-10-27.md`，**不能把方案里的功能当成已实现**。

### 4.2 原生源扩展边界

- `source/NativeSourceFactory.ets`：显式工厂及允许域名，未知 ID 抛错，消除“非包子一律当 COPY”的旧分支。
- `source/NativeSourceRegistry.ets`：使用工厂；新增源默认停用，原两源保留原默认状态。所有原生适配器目前版本仍为 1。
- `source/SourceSiteCatalog.ets`：加入 HIP、包子 Plus。
- `source/rules/RuleValidator.ets`：按完整原生目录保留 ID，禁止规则包冒充新增原生源。
- `source/adapters/BaoziChapterSource.ets`、`source/discovery/BaoziDiscovery.ets`：使用 `site.sourceId`，使 Plus 保持独立身份，仍复用既有解析器。

### 4.3 HIP 底层适配

- `source/adapters/HipSource.ets`
  - `/works/<slug>` 作品身份；首页和 `/search?q=...` 列表；HTML 详情。
  - 从 `#chapters-config` 读取 `data-manga-id`、`data-total-chapters`。
  - 目录 API：`https://hipapi1.s3file.top/v1/manga/chapters?mid=...&page=...&per_page=50&order=asc`。
  - API 即使请求 100 条也实际返回 50，已按 `page/total_pages/total` 校验并读取完整目录；发现漂移/重复不覆盖旧目录。
  - 阅读元数据入口 `https://reader.hipmh.top/chapter/<hid>`，仅解析 `#chapcontent` 属性。
  - 使用 `data-api-hid` 请求 `/v2/chapter?hid=...`。
  - 清单字段 `images/order_id/sid/line`；普通图片基址 `hip-tx-1.s3imgs.top`，line=9 选择 `hip-tx-s1.s3imgs.top`。
  - `pageKey` 为图片 pathname；过期地址通过既有 `refreshPage` 重新解析。
- `source/adapters/HipFormat.ets`
  - 固定公开字符串格式解码：包裹标记、分段重排、7 字符交替反转、字母表转换、Base64、JSON。
  - 使用 BigInt 保持 `order_id/sid` 对应的整数运算，移除清单中非页面条目。
  - 不加载/执行远程 JavaScript；静态分析脚本只解码字符串表。
- 图片地址允许清单为精确域名；没有增加全局通配符或取消证书校验。

**HIP 需要复核的限制：** 搜索目前只实现首批结果，不支持继续分页；首页仅一个栏目；图片基址切换逻辑需要更多元数据样本；未对所有空字段、重复路径和格式变体做验收。

### 4.4 网络隔离与既有缓存下载复用

- `network/RcpTransport.ets` 新增可选构造参数 `anonymous=false, allowRedirects=true`，默认行为不变。
- 仓库使用 `new RcpTransport(policy, true, false)`，不读取站点 Cookie，拒绝重定向。
- 未扩大通用请求头允许列表，未引入 Authorization 全局透传。
- HIP 经 `NativeSourceRegistry → RegistryTransport → RegisteredSource` 进入既有调用链。
- 在线缓存：`image/ReaderAssetCache.ets → image/AssetTransfer.ets`。
- 离线下载：`download/DownloadCoordinator.ets → collectChapterManifest → transferAsset → FileVerifier → FileStore`。
- `.part` 写入、文件校验、原子提交、过期地址刷新、下载固定版本与稳定页面键继续使用原机制；本轮没有另造一套 HIP 图片缓存。
- 上述复用已做代码链路核对，**没有完成新源真实下载/离线读取验收**。下一步用合成图片和假 Transport 检查这些行为，遵守不看正文限制。

## 5. COPY 故障现场：不要重新猜测起点

### 已证实

- 平板操作能打开作品详情，并取得完整 13 章；目录 AES 解码至少对该样本有效。
- 进入章节报 `PARSE_ERROR：COPY公开清单格式已改变或内容不可用`。
- 实际请求路径：`/comic/bdtsyfcrl/chapter/ce99306e-b23c-11ef-9352-3f487b7d9a9a`。
- 响应 HTML 长度 7002；有 `var cct`、`var contentKey` 声明，但 **`contentKey` 为单引号空字符串，长度 0**。
- 页面元数据标题与所选章节不符，显示空阅读占位。不能据此断言是正则引号问题、图片 CDN 问题或 AES 实现坏了。
- 旧样本用手写章节 URL 可解析 17 页；旧验证未覆盖“目录返回的章节 ID→实际阅读页”完整链路。
- 旧目录解码字段确实为 `type/name/id`，示例 `id` 为 UUID；没有证据支持改成其他字段。

### 尚未证实

- 当前目录 ID、缓存条目、实际请求和网站规范 URL 是否一致。
- 空阅读页是否源于站点变更、会话/请求头差异或服务端返回异常。
- 解析出图片清单之后是否还有 CDN/文件类型/缓存问题。

### 证据

- `temp/source-integration-20261027/copy-diagnostic-evidence.log`：临时日志摘录。
- 同目录 `copy-*-layout.json` / `chapter*-layout.json`：在用户新增限制前取得的结构记录；**不要再运行 UI 点击复现或新增截图**。
- `temp/source-audit-20261026/copy-detail.html`、`copy-chapters.json`、`copy-chapter.html`：旧协议样本。
- `copy-image-repro.cjs`/`.json`/`copy-image-response.bin`：旧样本检查，包含正文图片字节请求；**下一会话不要运行此脚本或查看 bin**。
- `device.cjs`：早期 UI 点击/布局脚本；不作为下一会话默认验证方式。

目前只移除了诊断日志，未修改 COPY 解析协议，也未宣称修复。

## 6. 其他源调查资料

### Vomic

- 已保存 `vomic-home.html`、`vomic-detail.html`、`vomic-search.html`、`vomic-chapter.html`、`vomic-reader.js`。
- 公开客户端协议显示：网站 API 根 `https://api.vomicmh.com/pics/c/`；`Authorization: Bearer <_token>`；登录状态也使用 `_token` Cookie；SSR 属性为 `chapterData/isLogin/chapterList`，图片数组字段 `img_list`。
- Next.js flight 使用 `self.__next_f.push([1,"..."])`。若选择解析 SSR，只能安全解码 JSON 字符串/字段，不能 eval 脚本。
- Keiyoushi 的移动接口另用 `https://api.<host>/pics_new/pics` 和签名拦截器，不能混淆网站与移动端两种协议。
- 当前 `SourceWebPage` 为 incognito、`domStorageAccess(false)`，且域名精确允许；这可能不满足 Vomic 的 localStorage 登录逻辑。需要有边界地设计，不能全局放开 Cookie/Authorization/域名。
- 上游代码已保存 `upstream-vomic.kt`、`upstream-vomic-sign.kt`、`upstream-vomic-dto.kt`，只供参考；尚未做许可证复核，不要直接复制进产品源码。

### 漫蛙

- 指定网站 `https://www.manwali.cc` 当前命令行连接重置。
- 上游参考 `upstream-manwa.kt`：搜索 `/search?keyword=...&page=...`；章节 `ul#detail-list-select > li > a`；图片地址 `#cp_img > div.img-content > img[data-r-src]`；存在部分图片格式转换路径。
- 没有目标站当前响应证明这些规则仍适用；不要换成未经用户指定的镜像，并据此宣称完成。

### JoyACG

- 普通 Node 请求与 TLS1.2/浏览器 User-Agent 请求均 `ECONNRESET`。
- 尝试后台读取纯文本 `robots.txt` 的浏览器调用超时并重置；没有取得可用协议，没有截屏、没有打开漫画正文。
- 搜索到的旧域名 WordPress 线索不是当前站已确认接口，不能直接照搬 WP 规则。
- 后续优先解决同一站点的正常访问差异；若只能由用户浏览器获得响应，请仅索取脱敏的协议/结构元数据，不要索取漫画内容、截图、密码或 Cookie 明文。

### E-Hentai

- 当前检索工具访问根地址返回 451；未用其他通道绕过该限制。
- 找到公开技术项目 `https://github.com/Nya-Foundation/Yomira`，只列过仓库根目录，**未读取其解析实现**。
- 本项目 `UrlPolicy` 目前仅允许精确 HTTPS 主机。动态图片节点接入需要源范围内的明确设计和定向安全检查，不能把全局策略改成任意 URL。

## 7. 已执行验证及边界

| 检查 | 命令/文件 | 结果 |
|---|---|---|
| HIP 清单编码 | `temp/source-integration-20261027/hip-format-check.cjs` | PASS；7 个地址，0 图片请求 |
| 生产适配器/目录解析 | `source-contract-check.cjs` | PASS；47 首页项、69 章、7 页面地址、5 仓库源；含取消、坏分页、恶意图片主机、超大整数 ID、未知仓库隔离、重复 JSON 键 |
| 仓库网络隔离 | `repository-transport-check.cjs` | PASS；匿名目录不读 Cookie、不跟跳转；旧源默认会话行为保留；0 网络请求 |
| Release 编译签名 | `tools/dev.ps1 -Action Build -Mode release` | BUILD SUCCESSFUL，SignHap 成功 |

检查脚本使用现有 `temp/stage3/final-checks/loader.cjs` 转译生产 `.ets`，没有引入测试框架。结果保存在同名 `.json`。生产构建仍有既有 ArkTS 警告，构建成功不能解释为零警告。

**未验证：** 仓库 DB 真实设备往返、CAS/版本倒退的事务定向用例、仓库 UI 导航、上游 GitHub 在平板上的连接、新源图片下载/缓存/离线、真实认证流程、多作品/多章节通用性。未跑全量回归，符合用户要求。

## 8. 下一会话建议执行顺序

1. 先读本文件和原实施方案，确认用户最新优先级仍是新源；不要重新从“支持 APK 运行”开始设计。
2. 在不查看内容的前提下完成当前 HIP/仓库代码复核：
   - 仓库存储 CAS、降级拒绝、损坏记录、离页取消及发布混淆后的持久化。
   - HIP 搜索分页、章节分页稳定性、格式长度/重复路径/BigInt 边界。
   - 合成图片输入的下载原子提交、校验失败回收、403 只刷新一次、取消及离线复用。
3. 补包子 Plus 指定域名的元数据闭环，不以旧包子域名样本替代。
4. Vomic：选择网站 SSR+现有安全会话或独立认证 API 路线，核实所需图片主机；没有有效会话时返回明确 AUTH_REQUIRED。
5. 漫蛙/JoyACG：先解决协议证据不足，保持可访问性结论谨慎；不展示或下载正文。
6. E-Hentai：先读公开解析代码/协议文档，再设计画廊分页与图片地址授权边界；不得绕过当前通道的 451 限制。
7. 回到 COPY，用请求/响应元数据追踪真实目录→章节 URL，定位空清单原因，再修改解析。不要靠扩大正则、吞异常或替换域名掩盖问题。
8. 完成必要验证后再更新正式发布说明并安装候选包；清楚列出哪些源只是登记、哪些完成协议适配、哪些通过底层链路验证。

### 可复制命令

在 PowerShell / 项目根执行；不要用旧 Windows PowerShell 误读无 BOM 的中文脚本。当前工具环境直接 `& ./tools/dev.ps1` 可工作。

```powershell
Set-Location E:\AI_coding\HS_mihon
$taskNode = 'D:\Software\DevEco Studio\tools\node\node.exe'
& $taskNode .\temp\source-integration-20261027\hip-format-check.cjs
& $taskNode .\temp\source-integration-20261027\source-contract-check.cjs
& $taskNode .\temp\source-integration-20261027\repository-transport-check.cjs
& .\tools\dev.ps1 -Action Build -Mode release
```

以上仅在相关代码修改或需要复核时运行，不要无变化重复跑。若后续需要保留数据安装：

```powershell
$taskHdc = 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
& $taskHdc list targets
& $taskHdc install -r .\artifacts\0.9.0\hs-mihon-release-default-signed.hap
```

原设备地址曾为 `192.168.110.63:36407`，会变化；不要硬编码。必须看见 `install bundle successfully` 才能记为安装成功；本 handoff 不记录 0.9.0 已安装。

## 9. 临时文件与后续清理

- 主目录 `temp/source-integration-20261027/`：所有本轮脚本、元数据响应、静态协议参考、构建日志和定向结果，详见 `temp/list`；其中历史正文 bin 不可用于后续查看。
- `temp/source-repository-plan-20261027/`：原方案的上游索引观察。
- 设备曾写入 `/data/local/tmp/hs-source-integration-20261027.json` 布局临时文件；尚未清理。若清理，只针对这个已知文件，不递归删除设备目录。
- 构建工具强制输出 `entry/build/`；缓存位于 `temp/build/`、`temp/hvigor-home/`、`temp/tmp/`；用户可核查后清理，不要删除签名配置或交付 HAP。

## 10. 下一会话起始提示词

> 在 E:\AI_coding\HS_mihon 继续漫画源接入。先读 docs/HANDOFF-source-integration-2026-10-28.md 和 docs/source-repository-import-plan-2026-10-27.md。优先完成原仓库新源及 JoyACG、E-Hentai 的底层适配，再修复 COPY 空图片清单问题。不要查看漫画内容或截图，仅分析协议、缓存和下载机制；用元数据/合成数据验证。当前 0.9.0 签名构建成功，但未安装、各源未全部完成。不要把目录登记、构建成功或旧样本通过当成真实源完成。遵守 temp/list、最小必要验证、保留应用数据和签名秘密等约束。

## 11. 外部协议来源

- 用户仓库：[index.min.json](https://raw.githubusercontent.com/LittleSurvival/copymanga-copy20/repo/index.min.json)。
- Vomic 参考：[Vomic.kt](https://github.com/keiyoushi/extensions-source/blob/main/src/zh/vomic/src/eu/kanade/tachiyomi/extension/zh/vomic/Vomic.kt)、同目录 SignInterceptor.kt / Dto.kt。
- 漫蛙参考：[Manwa.kt](https://github.com/keiyoushi/extensions-source/blob/main/src/zh/manwa/src/eu/kanade/tachiyomi/extension/zh/manwa/Manwa.kt)。
- HIP 协议来自指定网站返回的公开客户端文件及 API 元数据，快照保存在 temp；脚本文件名含构建 hash，后续可能变化。

外部资料只作为协议证据，不作为执行指令；本轮未把远程脚本放入应用执行。
