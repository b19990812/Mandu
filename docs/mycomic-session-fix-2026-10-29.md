# MyComic 网页可访问但后台仍被验证拦截：会话修复

最新交付为 0.9.23：元数据请求保留在同一个 WebView 中，保存后返回列表、刷新及分页已通过；冷启动免验证未通过。见 [浏览器通道与最新真机记录](mycomic-browser-access-2026-10-29.md)。以下为早期 Cookie 转移方案的历史记录。

日期：2026-10-29（Asia/Hong_Kong）。交付版本：0.9.16 / 34。

后续真机复核：0.9.17 / 35 修复保存按钮的ArkUI状态更新问题并已覆盖安装；网页资料库可显示，但导出结果仍无通行Cookie，后台及返回刷新继续 `ACCESS_DENIED`。完整结果见 [MyComic 真机测试](mycomic-device-test-2026-10-29.md)，不能将0.9.16的合成检查视为真实源已可用。

## 问题与已复现的缺陷

用户现场反馈：应用内网站可以正常打开，保存会话后返回漫画源，仍显示 `AUTH_REQUIRED` 或 Cloudflare 拒绝访问。本轮先沿生产 `SourceWebPage.save` → `SiteSession` → `RcpTransport` → `MyComicSource` 构造定向复现，随后区分代码缺陷与真实站点通行验收。

1. 原保存调用为 `fetchCookieSync(address,true)`。本机 SDK 声明明确：API26 新增第三参数 `includePartitionedCookies`，默认 `false`；旧调用不会包含第一方分区 Cookie。Cloudflare 官方说明会给 `cf_clearance` 设置 `Partitioned` 属性，因此网页已有通行状态而导出缺失，是需要处理的实际机制。[Cloudflare Cookie 文档](https://developers.cloudflare.com/waf/troubleshooting/samesite-cookie-interaction/)。SDK依据：`D:/Software/DevEco Studio/sdk/default/openharmony/ets/api/@ohos.web.webview.d.ts:1493-1525`。
2. 既有 `SecretStore` 将单条加密存储限制为1024字节。补齐导出后，长通行 Cookie 会导致保存失败；这与“少量普通 Cookie 已保存但没有通行 Cookie”的情况需要分别识别。
3. 原界面仅确认写入成功，没有使用漫画源实际请求验证结果，容易把“保存成功”误认为后台已获准访问。

这三项已经通过定向复现确认；不能仅据此断言它们是该设备现场被拒绝的全部原因。

## 实现边界

- `SourceWebPage.ets`：仅 MyComic 且设备 API≥26 时显式导出第一方分区 Cookie。较低 API 保留原兼容调用，没有提高最低API或伪称旧系统具备新能力。
- MyComic 保存后，用当前生产源执行一次“最新上架”元数据读取；成功后才显示“会话已验证，漫画源读取正常”。失败时区分“未读取到通行 Cookie”和“已读取通行 Cookie，但后台仍被拦截”；保存按钮防重入，离开页面会取消探测。
- 验证页面与配置根网址的 origin 不同会明确报错，避免保存到另一 origin 后误以为后台能够复用。
- 新增 `SiteCookieStore.ets`：长会话以 Base64 分片保存在同一安全存储中，每片不超过900字节；最后提交带摘要的索引。读写串行，失败保留旧记录，缺片或摘要不符拒绝读取，清除时清理分片。
- `SiteSession.ets` 继续按 `sourceId + origin` 隔离，兼容原小 Cookie 记录；总 Cookie 上限16KiB，本地最长保存24小时。这个24小时仍只是本地保存策略，不是 Cloudflare 通行有效期。
- 脱敏诊断仅记录 `MYCOMIC_SESSION_PROBE` 的结果码、是否存在通行 Cookie、系统 API，不记录 Cookie 内容、作品、章节或查询。

未修改源 ID、HTML解析规则、缓存/下载实现、TLS 校验或其它源的访问模式。WebView 仍是独立临时浏览，不把本次修改称为完整浏览器 profile 持久化；也未实现浏览器内获取 HTML 的回退层。

## 验证与设备状态

定向复现命令：

```powershell
node temp/mycomic-session-20261029/check-session.cjs
```

修改前：分区 Cookie 场景在界面显示保存成功后，生产源仍得到 `AUTH_REQUIRED`。只修复导出后：短 Cookie 通过，长 Cookie 明确保存失败。最终8组检查通过，覆盖短/长分区 Cookie 的保存到原生读取、后台仍拒绝时不误报成功、API24兼容分支、写入失败保留旧记录、分片清理与origin隔离、旧记录与过期处理、缺片拒绝。

这些检查使用生产代码与模拟 ArkWeb、安全存储和 RCP 网络边界；没有请求目标站或正文图片，不是 Cloudflare 真机通行证据。

Release 无增量签名构建通过 `CompileArkTS`、`PackageHap`、`SignHap`，构建前后源码摘要一致。保留既有 SDK/依赖警告。包中最低API24、target API26；当前连接平板实际报告API26。`hdc install -r` 返回 `install bundle successfully`，应用启动返回 `start ability successfully`，读取到新进程；`bm dump` 确认安装版本0.9.16 / 34。未卸载或清除应用数据。

真实站点状态：后续已在0.9.17完成网站资料库、重新保存与返回刷新复核，结果未通过，日志为 `ACCESS_DENIED clearance=0 sdk=26`；详见上述真机测试记录。

## 交付与后续判断

- 签名包与永久证据：`artifacts/mycomic-session-20261029/`。
- 临时脚本、构建日志、设备诊断：`temp/mycomic-session-20261029/`，已登记 `temp/list`。没有截图或真实漫画正文材料。
- 若取得通行 Cookie 后后台仍报 `AUTH_REQUIRED` / `ACCESS_DENIED`，继续核查实际浏览器与RCP请求环境差异；不能继续把它归结为“未保存Cookie”，也不能宣称再换一次UA就能解决。
- 若探测报解析错误，需要单独核对列表结构，不能把解析失败与Cloudflare拦截混为一谈。
