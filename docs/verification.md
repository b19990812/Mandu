# 验证记录

更新：2026-10-26，0.5.0。源码、主机替代适配器、PC响应和原生设备分别记录；旧版证据保留，不自动作为0.5全量回归。

## 0.5.0 本轮增量

完整功能和限制见[phase-0.5](phase-0.5.md)，有效结果集中`temp/mihon-parity-20261026/`。

| 范围 | 实际结果 | 边界/证据 |
|---|---|---|
| 32组核心定向 | storage6、backup6、reader-search6、archive4、local-import6、display-queue4全通过 | 各results.log；生产代码/SQL，SQLite/文件/网络/图像等替代适配器明示；非原生全量 |
| 集中原生诊断 | Raw Deflate、长度/CRC/虚假长度拒绝；schema6/外键；旧收藏2、离线章1保留 | native-result.json，对应前一Debug SHA；最后仅改阅读面板，未重复此诊断 |
| 最终Release最小交互 | 本地导入入口；自有示例统一阅读器、新显示选项；截图修正后面板居中/白字 | release-native-result.json与最终SHA绑定；release-reader-options.png；非实际选择器导入/恢复/导出 |
| 最终交付 | 两目标构建签名，Release SDK验签/包权限/路由/混淆/覆盖安装/启动通过 | artifact-result.json；Release13/Debug14路由；API26/min24不变 |

没有全量测试或新框架。G2真实双源、G3条漫旋转/长时内存、G4后台/强杀/异常/离线冷启动未闭环；COPY TLS和包子旧403未解决。系统选择器实际导入/备份恢复/导出和完整新UI/手势待验。后续只对改动模块运行必要检查，例如：`.\tools\dev.ps1 -Action Build`；核心脚本详见handoff，不默认全部重跑。

## 0.4.0 增量（历史）

完整交付与摘要见[0.4.0记录](phase-0.4.md)。生产阅读器新增左右点击、双页、默认后6/前1预取及可配置张数；修复条漫恢复、多指误翻和后台图像生命周期。

| 范围 | 结果和边界 | 证据 |
|---|---|---|
| 12组核心定向检查 | 生产VM/模型/UI处理器、真实设置SQL通过；Scroller/图像与资源使用替代适配器 | temp/reader-20261026/core-results.log；失败基线baseline.log、resource-baseline.log |
| 实际Release交互 | 本轮前一构建左右点翻、双页两列图、后台返回通过，原书架可见；自有示例 | temp/reader-20261026/device-result.json、release-spread.png；该构建SHA见phase-0.4.md |
| 最终Release资源补丁 | 最终包的双页设置恢复、两列图和一次后台返回通过；非原生内存/句柄计量 | temp/reader-20261026/final-reader-result.json，内含最终包摘要 |
| 最终包 | Debug/Release构建签名，Release SDK验签、混淆/权限/路由及覆盖安装通过 | temp/reader-20261026/artifact-result.json、signature-verify.log、release-install.log |
| 实时设备属性 | API26 / Release / tablet；最低API24工程配置保持原值 | 本轮HDC读取；artifact-result.json。旧API24设备记录不代表本次系统版本 |

未运行全量测试；本轮重点功能开发，真机只做集中必要核查。G2真实双源仍未通过；G3已有单页/双页部分证据，连续条漫旋转与长时间内存未闭环；G4后台下载系统矩阵未通过。真实源TLS/403没有因自有示例通过而被视为解决。

## 0.3.0及此前有效证据（历史）

| 检查 | 实际结果 | 证据路径（项目根目录起） |
|---|---|---|
| 规则导入/更新/回滚 | 主机7组及原生T10探针通过；非法v3保留旧版、陈旧请求隔离 | temp/stage3/rule-contract-checks.cjs；native-rule-update-result.json |
| 自有业务链路 | 原生导入HTML规则、搜索、完整3章、收藏、正式阅读1/2→2/2、历史通过 | temp/stage3/ui-rule-import-result.json、ui-search-result.json、ui-detail-result.json、ui-reader-next-result.json、ui-history-result.json |
| 下载/离线 | 原生自有c1完成2/2，下载入口进入同一离线阅读器；原收藏在升级后保留 | temp/stage3/native-download-first-result.json、native-offline-first-result.json、download-upgrade-library-result.json |
| 普通与长图区域解码 | 系统ImageKit/TileDecoder；PNG/JPEG/WebP普通图、PNG/JPEG 30000/60000高长图及15000高WebP；首中尾行号像素检查通过，释放后live map为0 | temp/stage3/image-marker-ordinary-result.json、image-marker-long-result.json |
| 局部长图内存 | 自有2160×60000分块探针VmHWM增量约59MiB；没有约494MiB整图RGBA增量 | temp/stage3/before-long-memory.log、after-long-memory.log；非20分钟/整机性能验收 |
| 用户阅读问题修复 | 原生普通图150%实际变宽、翻图；1080×30000实际滚动及双击200%；输入表单不覆盖阅读页 | temp/stage3/reader-ordinary-overlay-final-result.json、reader-long-overlay-final-result.json |
| 系统代理否定结果 | ends=1023时伪Range/分块响应仍写4096并完成；不能作为硬上限 | temp/stage3/native-agent-boundary-result.json、temp/fixtures/requests.jsonl |
| 两真实源快照 | 运行生产适配器；包子25搜索项/287章/163资源，COPY12搜索项/233章/17资源，均通过 | temp/stage3/final-checks/source-results.log；URL/加密使用宿主替代实现 |
| 持久化核心SQL | 生产仓库与迁移SQL在内存SQLite执行：目录回滚、正式/试读时间戳、200条保留、暂停恢复、完整提交、损坏单页修复、schema1→4保留数据通过 | temp/stage3/final-checks/storage-results.log；非SDK数据库/强杀验收 |
| 缓存并发 | 合并消费者、独立取消、持久复用、版本隔离、4引用、重试URI、清理保护、park重开通过 | temp/stage3/final-checks/cache-results.log；文件/图像/流写使用替代适配器 |
| 调度与分块模型 | 全局4、源/主机2、取消/时限/Retry-After、最后块定位及重试换代通过 | temp/stage3/final-checks/scheduler-strip-results.log；非手势/布局验收 |
| 双源试读入口 | 两源稳定章节标识、固定快照、自定义根映射、外站/凭据/HTTP/查询拒绝，禁用源不能绕过 | temp/stage3/final-checks/trial-entry-results.log；宿主URL/缓存替代适配器 |

以上定向检查只覆盖本次核心逻辑，未新增测试框架，未运行全量回归。旧cache-contract检查的“三文件及dispose删除”语义已过时，不能沿用其PASS证明当前持久缓存；当前有效证据是final-checks/cache-results.log。

## 0.3.0构建与包核查（历史）

Debug/lab完成CompileArkTS、PackageHap、SignHap，交付 `artifacts/0.3.0/hs-mihon-debug-lab-signed.hap`。Release/default交付 `artifacts/0.3.0/hs-mihon-release-default-signed.hap`，最终结果与包检查见[0.3.0记录](phase-0.3.md)和SHA256SUMS。

0.3.0当时Debug启动返回10106102（锁屏），其最终Release覆盖安装但未再次启动。该历史结果保持原边界；0.4.0时用户已解锁，最新包的启动和阅读检查以上方记录为准。

## 关卡

| 关卡 | 当前状态 | 必须补充 |
|---|---|---|
| G0 | 部分证据通过 | 0.4.0升级/启动/API26设备已补；故障/权限/文件选择器及句柄矩阵仍缺 |
| G1 | 核心更新回滚通过，Release收口待验 | 最终混淆包规则导入、更新回滚及文件选择器 |
| G2 | 未通过 | 两真实源各3章完整目录、图片顺序、真机整章与重开；COPY TLS、包子403限制 |
| G3 | 区域解码、页式修复和0.4.0双页部分通过 | 连续条漫/缩放/旋转、接缝、长时间内存及原生资源计量 |
| G4 | 未通过 | dataTransfer授予/后台/通知、暂停取消/杀进程/空间不足/损坏修复、飞行模式冷启动 |
| G5 | 后续 | 登录需求与逐源会话隔离，本版未实现 |

## 继续验证入口

```powershell
.\tools\dev.ps1 -Action Build -Mode release
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r .\artifacts\0.4.0\hs-mihon-release-default-signed.hap
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' shell aa start -a EntryAbility -b com.hsmihon.reader
```

用户已解锁且要求降低验证频率。后续集中核对：条漫跨图/缩放/旋转→返回跨重启位置；下载离线→后台/冷启动及真实双源。不要卸载、清数据库或以合成示例代替真实源验收。


## 2026-10-26 阅读器预渲染增量

0.5.1/code6新增有界PixelMap预解码复用、后续图与同图下一分块准备，保留0.5.0交付物及schema6。7组主机定向资源/并发检查通过；原生性能未验。实现、证据与复核入口见[预渲染说明](reader-prerender-0.5.1.md)。


## 2026-10-26：0.6.0水平翻页增量

新增三页稳定窗口、水平跟手拖动与完成/回弹、点击单页、旧画面保留及PixelMap帧后释放。最终Release构建通过；用户接管真机验收，未证明60FPS/无闪烁或长时内存达标。真实卷页仅有可行性方案，未启用。关键代码、验收步骤及范围见[0.6.0说明](reader-paging-0.6.0.md)。


## 2026-10-26：0.6.1连续阅读修正

移除正常等待覆盖文字；双页/纵向补齐280ms滑动过渡；水平章末手势和条漫到底接入自动续章，预取下一章前三张并在目标准备后交接会话。Release签名构建通过，真机由用户验收。详见[0.6.1说明](reader-continuity-0.6.1.md)。
