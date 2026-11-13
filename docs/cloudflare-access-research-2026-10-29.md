# Cloudflare 访问挑战处理方案调研

后续实现与真机结果：0.9.23 已实现保留同一个 WebView 的元数据通道，返回列表、刷新及分页通过；冷启动免验证未通过。见 [最新实现及证据](mycomic-browser-access-2026-10-29.md)。下文保持初次调研时的源码快照与研究边界。

调研日期：2026-10-29（Asia/Hong_Kong）
范围：Cloudflare 官方文档、工具官方仓库和当前项目源码；本次仅新增调研文档，未安装或部署工具、未修改业务源码、未请求真实漫画正文或截图、未进行站点通行及真机验证。工具作者声明不等于本项目实测通过。

后续实现记录：本文件保留调研时快照。0.9.16 已修复 MyComic 分区 Cookie 导出、长会话安全存储，并增加保存后的后台探测；源码现状与验收边界见 [MyComic 会话修复](mycomic-session-fix-2026-10-29.md)。

## 1. 结论

**没有可以对所有 Cloudflare 站点稳定生效的通用“绕过”方法。对当前鸿蒙阅读器，优先验证同设备 ArkWeb 人工完成挑战后的会话续用；如果原生请求仍被挑战，再评估让受保护的元数据请求留在同一 WebView 中。** 这是根据官方约束与现有架构提出的工程顺序，尚未证明 MyComic 能通过。Cloudflare 明确限制嵌入式浏览器支持，且不支持使用自动化浏览器解决生产挑战；`cf_clearance` 绑定特定访客与设备，不能把电脑上的 Cookie 直接视作平板通行凭据。[支持的浏览器](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/)、[Clearance](https://developers.cloudflare.com/cloudflare-challenges/concepts/clearance/)。

需要先区分三种情况：

| 响应 | 含义与处理方向 | 一手依据 |
| --- | --- | --- |
| `cf-mitigated: challenge` | Cloudflare 返回了挑战页，应进入验证流程；不能交给业务 HTML/JSON 解析器当正常结果处理 | 官方将该响应头作为挑战页识别依据。[检测挑战响应](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/) |
| 明确 `Access denied` / Error 1020 | 安全规则阻止访问，需要站点方按 Ray ID 和时间核查事件；完成一次挑战不等于解除该规则 | 1020 官方排查流程是查 Security Events 并调整命中规则。[Error 1020](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1020/) |
| 只有 HTTP 403 或 429 | 单独状态码不足以确定是哪类 Cloudflare 行为，应结合响应头、有限错误标记及站点事件判断；不要无限自动重试 | Cloudflare 存在多个挑战触发来源，通行期也不覆盖限流规则。[挑战机制](https://developers.cloudflare.com/cloudflare-challenges/concepts/how-challenges-work/)、[Challenge Passage](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/challenge-passage/) |

## 2. 六种路线的能力与限制

Mihon 官方排查指南优先建议用户打开源 WebView 人工验证并更新 WebView。其现行 `CloudflareInterceptor` 也不是固定头部“万能通过”：它识别挑战、按 host 合并验证过程，检测新的 `cf_clearance` 后重试原请求，并为超时、失败和需要交互的情形保留退出路径。这可作为本项目流程参照，Android 的实现细节与等待时长不能直接当作鸿蒙结论。[Mihon 官方指南](https://mihon.app/docs/guides/troubleshooting/#cloudflare)、[CloudflareInterceptor 源码](https://github.com/mihonapp/mihon/blob/main/core/common/src/main/kotlin/eu/kanade/tachiyomi/network/interceptor/CloudflareInterceptor.kt)。

| 路线 | 能做什么 | 对本项目的适用性与边界 |
| --- | --- | --- |
| 同设备浏览器 / WebView 人工验证并续用会话 | 用户完成验证后，浏览器获得 `cf_clearance`；有效期内可能减少重复挑战 | 首选验证方向。保持实际浏览器环境和网络连续性；原生客户端复用 Cookie 仍需实测。官方说明挑战的原始请求与求解请求 IP 不同会导致无效，WebView 支持有限。[Clearance](https://developers.cloudflare.com/cloudflare-challenges/concepts/clearance/)、[挑战限制](https://developers.cloudflare.com/cloudflare-challenges/concepts/how-challenges-work/)、[浏览器支持](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/) |
| 受保护元数据在同一 WebView 内请求并提取 | 将网络请求留在已验证浏览器环境，再把页面 HTML 或所需结构化元数据交给原生解析层 | 工程回退建议，减少 WebView 与原生网络栈切换。OpenHarmony 文档提供页面加载后执行 `runJavaScript` 并回调结果的基础能力，但不证明 API24 真机或 Cloudflare 能通过。需保留同源、导航、会话和生命周期约束，不能把跨域 iframe 代理挑战作为方案。[OpenHarmony Web FAQ](https://github.com/openharmony/docs/blob/master/en/application-dev/faqs/faqs-arkui-web.md)、[官方环境限制](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/)、[挑战限制](https://developers.cloudflare.com/cloudflare-challenges/concepts/how-challenges-work/) |
| `curl_cffi` / `curl-impersonate` | 模拟浏览器 TLS/JA3、HTTP/2 等网络指纹，帮助评估普通 HTTP 客户端被识别的因素 | 可作桌面研究工具；它本身不等于完整浏览器或通用验证码求解器。官方 FAQ 对能否通过 Cloudflare 的回答有条件限制。当前 ArkTS/RCP 不能通过修改 UA 就获得这些能力；鸿蒙移植属于新增原生网络组件工作，未验证。[官方仓库](https://github.com/lexiforest/curl_cffi)、[官方 FAQ](https://curl-cffi.readthedocs.io/en/latest/faq.html) |
| FlareSolverr 浏览器服务 | 服务端使用 Selenium 与 undetected-chromedriver 启动 Chrome，等待挑战处理后返回 HTML、Cookie 等信息，支持会话 | 可研究为独立电脑/NAS服务；需要浏览器运行资源，不能视作直接嵌入 ArkTS 的库。README 要求 Cookie 续用时 UA 匹配；即使匹配，也不能据此保证跨设备有效或任意验证码都能自动解决。若采用，应先验证服务自身会话中的后续请求，不假设服务 Cookie 能转移到平板。[官方仓库](https://github.com/FlareSolverr/FlareSolverr)、[官方浏览器支持边界](https://developers.cloudflare.com/cloudflare-challenges/reference/supported-browsers/) |
| `cloudscraper` | 基于 Python Requests，并结合 JavaScript 解释器处理其支持的挑战；仓库提供相应会话接口 | 可列为桌面候选，不能把 README 中“v3”“100%”等作者表述当作当前目标站通过证据；没有取得本项目 ArkTS/鸿蒙兼容性证据，不建议优先集成。[官方仓库](https://github.com/VeNoMouS/cloudscraper) |
| 站点方提供 API、WAF Skip 或 Turnstile pre-clearance | 由站点方为可信流量配置明确接口、规则例外或预验证，降低反复挑战 | 有站点控制权或合作关系时优先。Skip 只能跳过所支持产品，不能跳过免费版 Bot Fight Mode；pre-clearance 需站点方配置匹配域名，并在服务端用 Siteverify 验证 Turnstile token。普通客户端不能自行对第三方站点启用。[WAF Skip](https://developers.cloudflare.com/waf/custom-rules/skip/)、[预验证配置](https://developers.cloudflare.com/cloudflare-challenges/concepts/clearance/) |

降低并发、缓存元数据、避免重复抓取可减少请求压力，但不是解除已触发安全规则或挑战的保证。随意改 UA、频繁换 IP、单独复制 Cookie 都不足以覆盖完整浏览器环境；挑战接收与求解期间切换出口反而可能形成验证循环。[挑战限制](https://developers.cloudflare.com/cloudflare-challenges/concepts/how-challenges-work/)、[验证失败排查](https://developers.cloudflare.com/cloudflare-challenges/troubleshooting/challenge-solve-issues/)。

## 3. 当前项目源码事实

本节是本轮对工作区代码的检查结果，属于实现状态，不是通行能力验收。

| 位置 | 当前行为 | 对方案选择的影响 |
| --- | --- | --- |
| `entry/src/main/ets/source/MyComicAccess.ets:3`；`source/adapters/MyComicSource.ets:47,126`；`pages/SourceWebPage.ets:58` | MyComic 使用固定 Windows Chrome/140 UA，WebView、元数据与图片请求共用该值 | UA 一致已有实现；该桌面 UA 与实际 ArkWeb 环境的关系需要核查，不能据此认定已找到根因，也不应随机轮换 UA |
| `entry/src/main/ets/source/adapters/MyComicSource.ets:50-53` | 显式封禁映射 `ACCESS_DENIED`；挑战响应头或 HTML 标记映射 `AUTH_REQUIRED` | 已具备挑战与明确封禁的分流基础 |
| `entry/src/main/ets/pages/SourceWebPage.ets:25,29,33,54-55` | 进入、退出时清理 Cookie；保存时用 `fetchCookieSync(address,true)` 提取；使用隐私模式，启用 JavaScript，并按源控制 DOM storage | 当前持久化的是选定 Cookie，不是完整持久浏览器 profile；不能推定退出后仍保留挑战所需的全部环境 |
| `entry/src/main/ets/network/SiteSession.ets:8,11` | 会话按 `sourceId + origin` 隔离，本地保存上限为 24 小时 | 24 小时只是应用保存策略，不是 Cloudflare 承诺的 Cookie 通行有效期 |
| `entry/src/main/ets/network/RcpTransport.ets:75-80` | 原生请求从会话仓库读取 Cookie | WebView 完成验证后仍切换到 RCP 网络栈；相同 UA/Cookie 不证明其浏览器信号一致 |

当前未发现把 WebView 中已取得的 HTML 传回原生解析的通用桥接。采用第二条路线，需要新增受限的浏览器获取适配层；业务 HTML 解析器继续只接受普通页面，不把挑战识别、浏览器脚本和页面解析混进一个模块。该边界为工程建议，本次未实现。

此前 `docs/mycomic-html-2026-10-28.md:24-31` 记录过实时请求 403 以及真机会话链路未验收；本次没有重新请求目标站点，不能将旧结果当作 2026-10-29 的实时可达性结论。

## 4. 建议的最小验证顺序

以下为后续实施或真机排查步骤，本次没有执行：

1. 在真实平板使用同一出口，确认系统浏览器能否完成挑战；再确认 ArkWeb 能否完成。只访问列表/搜索等必要元数据页面，并阻止真实正文图片加载。
2. ArkWeb 成功后，在浏览器会话仍存活时读取一个元数据响应；随后使用当前会话仓库给 RCP 发同类请求，比较挑战类型、最终地址和有限诊断信息。避免记录 Cookie 值。
3. 若 WebView 成功而 RCP 失败，优先检查会话保存与恢复、实际 UA/运行环境差异和请求生命周期。再用受限 WebView 获取适配层做最小原型，不直接扩展到全部源或下载链路。
4. 若 ArkWeb 本身失败，记录错误类型与 Ray ID；评估浏览器兼容性或站点方接口。桌面工具只有实际验证过才进入候选，不因 README 宣称“绕过”就替换现有网络栈。

本次没有代码改动或可执行产物，因此未运行构建、单元测试、集成测试或全量回归。尚未验证项包括：ArkWeb 挑战通过、Cookie 保存后 RCP 续用、浏览器内元数据获取回退、工具针对目标站点的实际效果、会话过期与重启恢复。以上需要后续实施或真机验证，不能由文档研究推断通过。
