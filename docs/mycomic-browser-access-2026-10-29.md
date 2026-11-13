# MyComic 浏览器元数据通道与真机结果

日期：2026-10-29（Asia/Hong_Kong）。交付：**0.9.23 / 41，已保留数据覆盖安装到 API26 平板**。

**保存会话后返回原生列表、刷新、30→60 部分页通过。冷启动直接加载仍触发验证；重新打开验证页、保存、返回刷新可以恢复。** 本记录只验收网站元数据访问链路，不代表正文、下载或整源全功能通过。

## 1. 已定位的拦截边界

0.9.18 的同请求对照记录位于 `artifacts/mycomic-access-diagnosis-20261029/evidence/comparison-baseline.json`：

- 同一个 `/cn/comics?sort=-id` 请求，ArkWeb 返回 200、可解析列表；RCP 返回 403、明确封禁页。RCP 再次请求仍为 403。
- 出口 IP 相同（仅保存比较结果），Cloudflare 边缘实际观察到的 UA 均与配置一致，双方均为 TLS1.3。
- 导出的分区 Cookie 包含 `cf_clearance`，加密保存内容与导出值一致，探测期间 Cookie 未变化。证据没有记录 Cookie 值。
- 原生实际使用 HTTP/2，浏览器实际使用 HTTP/3。后续 HTTP/3 参数实验的实际原生协议仍是 HTTP/2，因此没有完成真正的协议等值对照，也不能声称已排除 HTTP 版本差异。
- 请求头跟踪实验的解析没有证明最终线上 Cookie 缺失；不能把该实验输出当成确定的漏发证据。

因此已确认：**将网页会话 Cookie 复制到原生 RCP，不能使同一请求获得浏览器的通行结果。** 来源根网址不是上述对照差异的解释。具体 Cloudflare WAF/Bot 规则、TLS 指纹或某个单一浏览器信号，未取得站点侧证据，不能确定。

## 2. 本次实现

请求路径：`RegistryTransport → MyComicBrowserTransport → MyComicBrowserSession → ArkWeb fetch → MyComicSource HTML解析`。

| 模块 | 职责 |
| --- | --- |
| `network/MyComicBrowserTransport.ets` | 只接管 MyComic 元数据请求，保留请求调度、限流与错误返回；图片及文件流仍使用现有原生通道 |
| `network/MyComicBrowserSession.ets` | 当前源同源 GET 页面请求，最大 2MiB，8192 字符分片过桥；保留 HTTP 状态和挑战标记，处理取消、超时、串行访问和前台状态 |
| `ui/MyComicBrowserHost.ets` | 由 BuilderNode 持有一个 Web 和 WebviewController；验证页挂载 NodeContainer，返回时仅卸载容器，保留同一个 Web 的运行环境 |
| `pages/SourceWebPage.ets` | MyComic 显示上述同一个 Web；保存后执行真实生产列表解析，成功才显示“会话已验证”；遇到挑战则显示实际列表验证页 |
| `source/NativeSourceRegistry.ets` | 在原有来源与版本校验内部安装传输适配器，稳定源 ID 仍为 `org.hsmihon.mycomic` |
| `pages/HomePage.ets`、`entryability/EntryAbility.ets` | 持有浏览器资源生命周期；应用后台时拒绝新的浏览器元数据请求，销毁时释放引用 |

MyComic 使用专用的常规浏览器上下文，调用 `saveCookieAsync()` 保存浏览器 Cookie；其他来源网站仍使用隐私上下文。原有原生 Cookie 快照继续按 `sourceId + origin` 隔离并加密保存，长 Cookie 用受限分片存储。浏览器上下文与 Cookie 快照的有效期不能等同。

元数据目标仍由已选来源根网址解析。验证页定位到 `/cn/comics?sort=-id` 是为了在用户可见页面处理同一个列表请求的挑战，不修改来源配置中的根网址。初始化只接受同源页面元数据；跨源跳转、非 GET、超限响应失败退出。HTTPS、公网地址和证书校验保留，没有暴露网站可调用的原生 JavaScript 代理。

离线 Web 的创建、挂载和复用方式依据本地 API26 SDK 的 `BuilderNode`、`NodeController`、`WebviewController` 声明，以及 [OpenHarmony 官方离线 Web 文档](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/web/web-offline-mode.md)。相关能力在本次 API26 真机上复核；API24 实机未验证。

## 3. 最终版本的真实验证

证据目录：`artifacts/mycomic-browser-20261029/evidence/`。只保存页面路径、按钮、状态、条目计数及 HTTP 状态/字节数，不保存 Cookie、正文或截图。UI 树原始导出在提取后删除。

| 操作 | 实际结果 | 证据 |
| --- | --- | --- |
| 覆盖安装与启动 | `install bundle successfully`，`start ability successfully`；设备版本 0.9.23 / 41，API26，应用进程存在 | `install-0.9.23.log`、`v0923-start.json`、`device-0.9.23.json` |
| 保存会话并探测 | 显示“会话已验证，漫画源读取正常；返回后可刷新加载” | `v0923-save.json` |
| 关闭网站，打开原生列表 | 已加载 30 部；可见 16 个 GridItem；无验证/封禁错误 | `v0923-native.json`、`v0923-native-loaded-assertion.json` |
| 原生刷新 | 已加载 30 部 | `v0923-refresh.json` |
| 加载更多 | 已加载 60 部；列表断言通过 | `v0923-more.json`、`v0923-more-loaded-assertion.json` |
| 停止进程后重启，直接打开原生列表 | **未通过**：`AUTH_REQUIRED`，0 个 GridItem；进程由 8545 变为 8678，未清除数据 | `restart-0.9.23.json`、`v0923-restart-loaded-assertion.json` |
| 重启后打开验证页、保存、返回刷新 | **恢复成功**：保存探测通过，原生列表有 16 个可见 GridItem，无验证/封禁错误 | `v0923-recovery-save-finished.json`、`v0923-recovery-loaded-assertion.json` |

最终应用留在已恢复的 MyComic 原生列表。上表是当前版本的设备证据；0.9.19—0.9.22 属于过程包，不能代替 0.9.23 的验收。0.9.20 的两次冷启动失败也保留在证据目录。验证页与保留宿主此前使用两个 Web 的方式已被同实例方案替换，但同实例方案仍未解决冷启动免验证。

## 4. 最小检查与构建

- 浏览器通道 8 组定向检查通过：生产 HTML 解析、可见/保留控制器交接、挑战文档就绪、同源与方法限制、会话归属/前台状态、串行与取消、大小/重定向、UTF-8 分片与图片原生委托。
- 保存会话/安全存储 8 组定向检查通过：API26 分区 Cookie、长 Cookie、探测失败状态、API24 兼容 API、写入失败保留旧值、按 origin 清除、旧记录/过期、缺失分片拒绝。
- 上述检查运行生产代码，但 SDK、HTTP 和存储由受控替身提供；第二组还显式替换了 UI 浏览器资源，不覆盖真实 BuilderNode 生命周期或真实 Cloudflare。相关生命周期与通行结果以上表真机记录为准。
- Release `CompileArkTS`、`SignHap`、`BUILD SUCCESSFUL`；构建期间源码摘要一致，交付前复核摘要仍一致。
- `git -c core.whitespace=cr-at-eol diff --check` 通过。临时 MyComic 诊断探针及 RCP 协议/请求头实验代码已移出当前生产源。
- 按最小验证原则未运行全量回归。未改变正文图片/下载传输方式，且遵守只做元数据验证的范围，未验收正文、下载、离线阅读、后台更新与 API24 真机。

项目根目录下的复核命令（临时脚本依赖也位于 `temp/`，清理后需恢复相应脚本）：

```powershell
& 'D:/Software/DevEco Studio/tools/node/node.exe' 'temp/mycomic-browser-20261029/check.cjs'
& 'D:/Software/DevEco Studio/tools/node/node.exe' 'temp/mycomic-session-20261029/check-session.cjs'
pwsh -NoProfile -File temp/mycomic-browser-20261029/build.ps1
```

## 5. 使用与交付

在 MyComic 中打开“网站”，完成出现的真人验证，点“保存当前站点会话”，等到“会话已验证”后返回并刷新。如果保存探测仍要求验证，应用会打开实际列表页面，完成验证后重新保存。冷启动后可能需要重复此过程；本次冷启动直接加载测试确实失败，不承诺浏览器 Cookie 持久化即可免验证。

- 签名包：`artifacts/mycomic-browser-20261029/hs-mihon-0.9.23-release-signed.hap`
- SHA256：`31926f2768a89910a4b9b43874b970e627624a1091cb48defec7f13ca800b5e6`
- 证据与源码摘要：同目录 `evidence/`、`checks-0.9.23.json`、`session-checks-0.9.23.json`、`build-evidence-0.9.23.json`、`source-0.9.23.json`、`source-current-0.9.23.json`。
- 所有安装均为 `hdc install -r`；未卸载或清除应用数据。工作区原有阅读器改动保留，未提交或推送 Git。
