# 0.8.2 加载同步、菜单和网站首页

日期：2026-10-27（Asia/Hong_Kong）

## 并发上限何时加入

原始会话中的 `RequestScheduler.ets` 新增补丁记录为：

- UTC：2026-10-25 13:54:14.638。
- 香港时间：**2026-10-25 21:54:14.638**。
- 原始会话：`01a171b1-3d52-7453-bcb8-5cbe428fe430`。
- 当时已经包含全局 4 个、同源 2 个、同域名 2 个的并发上限，以及每次放行后的固定 500 毫秒间隔。

```ts
for (...; ... && RequestScheduler.active < 4; ...) { ... }
if (... || sourcesForThisRequest >= 2 || hostsForThisRequest >= 2) { ... }
```

精确原始条件及时间在 `temp/reader-recovery-20261027/concurrency-history.json`。这证明源码的加入时间，不代表设备安装该代码的时间。0.8.1 移除了正常请求之间的固定间隔及业务层前置等待，保留并发上限；0.8.2 也没有调整并发数量。

## 内置星海图片准备状态

用户进一步确认内置“星海旅人”也会停在“图像 1／正在准备图片”。内置示例通过 `BundledSampleTransport` 读取应用 rawfile，不经过公网 RCP 和网络并发调度器，因此需要把本地显示链路与真实源网络错误分别验证。

这次增加显式的异步加载结果通知：

`PagerWindow.onChange → HorizontalPager.loadRevision → 单页/双页组件的本地 @State 显示快照`。

- 图片到达、失败和重试都会通知界面刷新。
- `PagerSlot.asset` 与 `companion` 显式初始化；页面组件在出现及状态同步时重新读取当前槽位。
- 图片加载状态变化不更改页面 key，不通过反复销毁页面来刷新。
- 旧页面取消后到达的结果不能覆盖当前页面；单页和双页的异步显示都加入定向检查。

状态交接设计参考 [OpenHarmony 官方状态刷新排查说明](https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/ui/state-management/troubleshooting-state-manage.md)。本次宿主检查证明显式状态交接通路，不能单独证明原生 ArkUI 画面或“星海卡住”已在设备上消失。

## 加载期间的阅读菜单

- 页数尚未读出时，底部“阅读菜单”入口仍显示。
- 无图片的加载/失败画面可点击打开菜单，并提供明确的菜单和返回按钮。
- 加载进度图标不拦截触摸。
- 菜单中在加载时可取消；来源已识别时可打开网站首页，无需等完整章节读完。
- 页内图片占位界面也提供“阅读菜单”按钮。

## 网站首页入口

1. **更多 → 漫画源网站 → 打开网站首页**。
2. **阅读菜单 → 网站首页**。
3. **浏览 → 来源右侧“网站” → 网站首页**，站内跳转后可以回到当前配置的根网址。

首页使用当前源配置，包含用户保存的自定义网址。站内浏览的当前地址和固定首页分开保存，地址栏更新不会重新创建整个 Web 页面。内置合成示例和本地漫画没有外部首页入口。

## 网络请求名额与错误反馈

修正 `RcpTransport` 的名额释放范围：读取站点会话和创建请求头也放在 `try/finally` 内。此前会话读取异常可能发生在 `finally` 之前，导致占用的并发名额无法释放。定向检查复现了请求异常后 active 从 0 留在 1；修改后会回到 0。

会话存储异常报告为会话读取失败；底层网络错误显示**域名和数字 SDK 代码**，不展示请求路径、查询参数、Cookie 或原始异常文本。这样下一次真实源失败可以按具体主机和错误码继续定位。

本次没有证明包子真实取图已恢复，也没有把本地状态交接改动等同于网络问题已解决。

## 验证和交付

直接相关宿主检查：新增 6 项、既有翻页 16 项、网络调度/传输 8 项，共 30 项通过。未运行全量回归，未引入测试框架。原生、UI、文件和网络接口在这些检查中使用相应桩；编译/签名不能替代设备交互验收。

```powershell
node .\temp\reader-recovery-20261027\check.cjs
node .\temp\reader-turn-20261027\check.cjs
node .\temp\http-access-20261027\check.cjs
.\tools\dev.ps1 -Action Build -Mode release
```

证据集中在 `temp/reader-recovery-20261027/`：修改前 `baseline.json`、修改后 `checks.json`、并发历史、只读已安装版本及构建日志。设备只读核查确认安装版本为 0.8.1/code12；本轮未安装新包或进行界面操作，原生星海显示及包子真实网络仍待集中验收。

签名包：`artifacts/0.8.2/hs-mihon-release-default-signed.hap`，摘要见同目录 `SHA256SUMS`。保留 API26 编译/目标、API24 最低兼容、phone/tablet，不修改数据库。

```powershell
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r .\artifacts\0.8.2\hs-mihon-release-default-signed.hap
```

集中核查顺序：覆盖安装后先打开内置星海，分别检查单页和双页图片；在完整章节读取及图片准备阶段打开菜单、取消和返回；从阅读菜单/漫画源网站打开首页；最后重试原包子章节，如失败则保留显示的主机和 SDK 数字代码。
