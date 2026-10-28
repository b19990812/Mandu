# 环境记录

记录日期：2026-10-25，Asia/Hong_Kong。信息来自本机安装文件、命令输出和构建产物。

## 已确认的开发基线

| 项目 | 实际值 |
|---|---|
| 工程 | E:\AI_coding\HS_mihon；单 entry、Stage、ArkTS；声明 Phone、Tablet |
| IDE | D:\Software\DevEco Studio；26.0.0.851 |
| IDE build | 261.23567.138.36.2600851 |
| SDK | IDE 内置 HarmonyOS 26.0.0 Release；26.0.0.105 |
| 最低兼容 / target | 6.1.1(24) / 26.0.0 |
| compile | 由 IDE 内置 SDK 管理；合并产物记录 26.0.0.105 |
| Hvigor / 插件 | 6.26.8 / 6.26.8 |
| OHPM | 26.0.0.630 |
| Node | IDE 配套 v24.14.1 |
| JBR | IDE 配套 OpenJDK 25.0.2，JBR-25.0.2+1-329.117-nomod |
| hdc | 3.2.0f；兼容性排障时已连接平板，读取到 API 24、Release |
| Python | 本机 Python 3.12；样本服务只使用标准库，不进入应用 |
| 签名 | 本机自动开发签名方案 default 已绑定 default 产品；Debug/lab signed HAP 已在 API24 平板安装、启动并读到进程 |

## API 26 决定与配置格式

用户明确指定“目标 api 为 26”，工程最初将最低兼容、目标和编译版本统一到 26。2026-10-25 设备兼容性排障时，通过 HDC 读到当前连接平板的 `const.ohos.apiversion=24`、`const.ohos.releasetype=Release`、`const.ohos.fullname=OpenHarmony-6.1.1.120`、`const.product.devicetype=tablet`；应用和设备的发布类型一致，但设备低于原最低兼容版本。

最低兼容版本现调整为 `6.1.1(24)`，目标版本仍为 `26.0.0`，编译继续使用 IDE 内置 API 26 SDK。API 24 的版本字符串已对照本机 SDK 的 `hms/ets/build-tools/ts-checker-hooks/sdkApiVersionMap.json`。API 24 设备上的安装、启动及功能验收须单独记录，不能由构建通过推定。原方案的 API 20 环境假设仍保留供追溯。

API 26 的实际 SDK 版本字符串是 `26.0.0`，而非旧式 `26.0.0(26)`。`modelVersion` 也采用 `26.0.0`。`compileSdkVersion` 不显式配置，使用 IDE 配套 SDK；该写法与[官方 build-profile 参考](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hmos-hvigor-build-profile-app)一致，且已经实际构建。IDE 系列说明见[官方 DevEco 26 版本说明](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/deveco-studio-new-features-2600)。具体补丁版本以本机记录为准。

AppScope当前对外版本为0.5.0、versionCode=5，数据库schema6；0.1.0～0.4.0交付目录保留。entry的OHPM包版本仍为1.0.0；它不是产品完成度声明。

2026-10-26本轮0.4.0覆盖安装前重新读取，当前连接设备报告`const.ohos.apiversion=26`、`const.ohos.releasetype=Release`、`const.product.devicetype=tablet`。这是本次实时属性，旧API24记录保留为历史，不能把0.4.0功能冒烟当API24上的同版本验收。工程最低API24保持不变，没有因设备报告改变而调整API。

同日0.5.0沿用API/工具链与签名配置，最终Debug/Release签名构建及Release验签/覆盖安装/启动通过；原生归档诊断和最小Release入口/阅读菜单核查单列于[0.5记录](phase-0.5.md)。没有更改工程最低API或新增应用权限。

## 工具与缓存边界

本轮执行环境 PATH 只有系统 Node/Java 等通用工具，未直接解析到 hvigor、ohpm、hdc。`tools/dev.ps1` 为子进程配置配套工具，不改机器永久 PATH。

Hvigor 用户缓存、显式包缓存、日志和临时文件归入 `temp/`。`tools/dev.ps1` 使用已验证的 `build-cache-dir` 参数，把 Hvigor/ArkTS 的缓存、生成文件和编译中间结果集中到 `temp/build/`。SDK 仍将最终包与符号复制到 `entry/build/default/outputs/`；脚本再将长期交付 HAP 及摘要保留至 `artifacts/`。首次核查时默认位置的旧 Hvigor 缓存移入 `temp/legacy-hvigor/`，不保留散落的中间目录。

OHPM用户配置及npm引导缓存若由工具生成，使用用户目录，已登记工具路径例外。首轮空dependencies没有锁文件；0.2.0引入@ohos/htmlparser2 1.0.4，OHPM已实际生成entry/oh-package-lock.json5。oh_modules及entry/oh_modules为标准安装/链接位置，属于temp外路径例外。IDE直接构建也应使用temp构建缓存目录；本轮保留用户已有.hvigor/和.idea/状态，不自动移动。

桌面执行沙箱曾阻止 Node 的 `realpath` 和本地 socket。使用正常权限边界外的本机构建调用后完成构建；工具版本和工程配置保持一致。两个不同执行沙箱间的 loopback 服务不可直接互通，后续本机服务冒烟改为在同一进程启动和访问，结束即关闭。这不构成设备网络验证。

## SDK 声明核对

对照本机 `sdk/default/hms/ets/api/@hms.collaboration.rcp.d.ts` 已确认存在：`createSession`、`Session.fetch`、`Session.cancel`、`Session.close`、`Configuration.transfer.autoRedirect`、`Configuration.tracing.httpEventsHandler`、`onDataReceive` 和 `onStatusCodeReceive`。代码已用这些真实声明编译，未借用旧 HTTP 模块的假想开关。

SDK 声明包含异步数据回调返回类型；本机代码采用每块 await 写入。实际回调顺序、取消时序、缓冲峰值和资源回收仍须在设备验证。

Debug/Release编译仍有SDK系统调用异常提示及依赖示例资源page_show重名提示，没有关闭检查。Hvigor首次引导pnpm的审计提示保留，未执行强制升级。当前依赖与溯源边界见[依赖台账](THIRD_PARTY_NOTICES.md)。
