# MyComic 真机测试：网页可访问，原生列表仍被拒绝

后续结果：0.9.23 已改用同一个保留 WebView 请求元数据，保存后返回列表、刷新及分页通过；冷启动直接加载仍要求验证。见 [浏览器通道与最新真机记录](mycomic-browser-access-2026-10-29.md)。本文件保留 0.9.17 的历史失败证据。

测试日期：2026-10-29，20:04—20:14（Asia/Hong_Kong）。结论：**未通过真实源访问验收**。测试中修复了保存按钮不可用的问题，最终平板安装并运行0.9.17 / 35。

## 环境与范围

- HDC连接的真实平板实际API26；`bm dump`确认0.9.17 / 35，读取到应用进程。
- 正式Release签名构建通过，构建前后源码摘要一致，覆盖安装返回 `install bundle successfully`；没有卸载或清除用户数据。
- 通过UITest操作源列表、MyComic网站导航、保存会话、返回和刷新。仅保留页面路径、导航按钮、错误状态与脱敏探测日志；界面树导出后立即删除。
- 没有打开作品详情或章节阅读页，没有截图，也没有读取、输出或保存真实Cookie值。网页只进入首页与资料库，未进行正文阅读、下载或离线验收。

## 实际结果

| 步骤 | 结果 | 证据（交付目录下 `evidence/`） |
| --- | --- | --- |
| 进入MyComic原生首页 | `ACCESS_DENIED`，没有元数据条目 | `native-before.json` |
| 打开应用内网站 | 能显示MyComic网页 | `web-open.json` |
| 检查保存按钮 | 修复前禁用；修复后可用 | `save-button-before.json`、`save-button-after.json` |
| 在首页保存并探测 | `ACCESS_DENIED`；`clearance=0`；`sdk=26` | `native-probe-root.log` |
| 点击网页“漫畫資料庫” | 地址显示 `https://mycomic.com/comics`，出现“排序”“最新上架”“最高人氣”等列表标记 | `web-catalogue-loaded.json` |
| 在资料库重新保存并探测 | 显示“未读取到通行 Cookie”；日志仍为 `ACCESS_DENIED clearance=0 sdk=26` | `catalogue-save-final.json`、`catalogue-probe-final.log` |
| 返回原生首页并刷新 | 仍为 `ACCESS_DENIED`；元数据条目为0；通过断言失败 | `native-final.json`、`native-final-assertion.json` |

已核对焦点窗口与应用界面树中的窗口编号一致，避免把不在前台的旧窗口误当作操作结果。测试期间存在人工操作与脚本操作，表中不把所有保存动作都归因于脚本；最后一次资料库保存、返回和刷新由脚本明确执行。

脱敏日志样例：

```text
MYCOMIC_SESSION_PROBE result=ACCESS_DENIED clearance=0 sdk=26
```

`clearance=0`只说明本次导出的Cookie字符串没有 `cf_clearance`，不能单独区分站点未签发、所访问页面未产生挑战或分区Cookie仍未被导出的原因。

## 测试中修复的问题

上一轮在保存按钮的 `enabled` 条件加入了 `owned`，但该字段不是ArkUI状态字段。真实页面已经取得会话占用并显示网站，按钮仍保持禁用，导致用户无法执行保存。

本轮把 `owned` 改为 `@State`，版本升为0.9.17 / 35。真机断言从失败变为通过：

```powershell
# 前置：应用内MyComic“网站”页面已打开，当前没有探测请求在进行。
node temp/mycomic-session-20261029/device-test.cjs assert-save-ready save-button-after
```

原有8组生产代码定向检查继续通过，但使用模拟SDK/网络边界，不能替代本表中的真实站点失败结果。没有运行全量测试。

## 结论与下一步

当前“网页打开 → 导出Cookie → RCP后台读取”的路线在这台设备上仍未贯通。长Cookie与分区Cookie处理已经补齐代码路径，不能因此把真实源标记为可用。

另一个需要优先对齐的变量是路径：网页本轮进入 `/comics`，当前生产适配器的列表路径为 `/cn/comics`。本轮没有让WebView和RCP对同一个 `/cn/comics` 请求逐项比较，因此尚不能确认是否属于特定路径访问策略，也不能把全部差异直接归因于TLS/浏览器指纹。

后续应先让验证入口与适配器访问同一列表地址，确认浏览器是否能获取该页面及通行Cookie；如果同一地址在WebView可读而RCP仍被拒绝，再验证同一WebView内获取HTML并交给原生解析的回退。不要以继续重复保存或随机更换UA代替这一步诊断。

## 交付位置

- 正式签名包：`artifacts/mycomic-session-device-20261029/hs-mihon-0.9.17-release-signed.hap`。
- SHA256：`5e38987ed122db6bb38c22e8ea4d6069e0f1bd47d7d25be205fc0289652042fd`。
- 实际版本、结果汇总、构建与源码摘要：同目录 `delivery.json`、`package-metadata.json`、`build-evidence.json`、`source-after.json`。
- 脱敏真机证据：同目录 `evidence/`。
- 临时操作脚本与状态材料：`temp/mycomic-session-20261029/device-test.cjs`、`device-test/`；均已登记 `temp/list`。

设备最终停留在MyComic原生首页的失败状态，便于继续复核。没有修改站点根网址或其它源状态。
