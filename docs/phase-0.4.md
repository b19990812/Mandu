# 0.4.0 阅读器续作

2026-10-26，Asia/Hong_Kong。versionCode=4，API26目标/编译、最低API24、phone/tablet，数据库仍为schema4。基于0.3.0续作，未重新建工程。用户最新要求降低真机验证频率，优先功能完整开发；本轮集中做必要核查。

## 可直接使用的功能

- 阅读器设置提供“单页 / 条漫 / 双页”。单页/双页1×时点击左30%上一页/组，右30%下一页/组，中间40%展开菜单。双击仍缩放；多指结束不翻页，放大后优先平移。左右点击的前后含义固定，排版方向只影响双页顺序和横划映射。
- 默认提前缓存后6张、前1张，可在更多→设置选择2/4/6/10张或关闭。当前图开始读取时就安排后续预取，条漫跨图继续补齐，重叠的在途请求保留；最多2项预取并发，当前图排队优先于预取，预取优先于普通下载。仍遵守全局/源/主机限额与浏览缓存字节预算，缓存文件不等于已提交离线章节。
- 双页固定相邻配对，一次翻两张；末尾不足两张单独显示。LTR/RTL只改变左右排版，稳定pageKey不变。两张各自适屏/分块/滚动，保存正在操作的页及比例，退出双页可继续该页；横屏通常能减少黑边。
- 修复条漫未知尺寸占位项将恢复比例写成0；尺寸重排期间阻止临时布局覆盖进度，匹配代次恢复后再接收滚动位置。可见失败项重试时失效该图缓存与分块代次。
- 前后台生命周期直接暂停VM、预取与缓存会话。ImageTile/WebtoonTile直接接收后台通知，取消请求、清PixelMap/文件引用，无需等待后台界面渲染；回来后重新获取图像。离线切章保留offlineOnly参数，切章先提交进度。

页面只负责布局/手势，ReaderVM负责会话/可见页/进度，ReaderPreloader负责有界预取窗口；现有缓存、下载和源边界复用。预取张数使用reader_settings原始键，旧设置缺该键时默认6，不迁移或清理书架/历史/离线数据。

## 验证和证据

- `temp/reader-20261026/core-checks.cjs`：12组生产VM、模型、UI处理器及设置SQL的定向检查通过；使用替代Scroller、资源和数据库适配器，不是原生手势/内存验收。原先条漫占位、多指误翻、后台缓存及像素未释放的失败结果保留在baseline.log、resource-baseline.log。
- 两目标CompileArkTS、PackageHap、SignHap通过；Release由SDK verify-app验证通过，包内API/权限/路由/持久化字段混淆/排除实验室核查通过。见debug-build.log、release-build.log、signature-verify.log、artifact-result.json。
- Release覆盖安装明确输出install bundle successfully，启动成功；原书架“星海旅人 & 归途”可见。没有卸载、清数据库，也没有把书架可见扩展为全部旧进度/离线文件验收。
- 本轮前一Release构建（SHA256 ff7813c0cedbe0b87fa9fa6bb92820fd3d1d893718567fcfb91fcd15ca9e9dba）集中核对：右点到2/2、左点回1/2、两列实际解码图、后台返回。见device-result.json、release-spread.png；画面位置为左[125,0,1275,1840]、右[1525,0,2675,1840]。
- 最后图像生命周期补丁后的最小核查捕获第二列停留占位项：@Builder按值传递的异步asset未及时刷新。已改为独立SpreadPage的响应式@Prop，重建、覆盖安装，并用相同复现流程核对最终包的双页设置恢复、两列解码和一次后台返回通过。失败保留在second-column-failure-result.json/layout.json，最终成功见final-reader-result.json（含最终HAP摘要）。这不测量原生PixelMap峰值或证明所有后台句柄已经归零。
- 本次设备实时报告API26 / Release / tablet；交接中的API24是旧记录，最低API24工程决定保持不变。

本轮未运行全量单元、集成或E2E回归，没有新增测试框架。定向检查仅因涉及进度、设置存储、并发预取及资源释放而运行。

## 最终产物

| 产物 | 字节 | SHA256 |
|---|---:|---|
| artifacts/0.4.0/hs-mihon-release-default-signed.hap | 6065348 | 9fb115f195f2a4d692f1138bab984e05deb5fce61d0b832c273c3b7c5cff53b6 |
| artifacts/0.4.0/hs-mihon-debug-lab-signed.hap | 7261141 | cf1b7e349b4ff4c61137ea99e4398ce6b1993a862b1254754929e6defc090306 |

摘要在artifacts/0.4.0/SHA256SUMS。旧0.3.0包保留。签名授权材料及temp中的签名配置不外传。

## 未闭环

R01–R11核心功能已有实现，但首版不能宣称全部验收完成。COPY原生TLS错误和包子旧302→403未解决；本轮没有重复真实站点设备请求。G2两源各3章及图片顺序、真实下载离线链路仍缺。G3连续条漫旋转/接缝/长时间内存、G4后台下载权限/通知/强杀/空间不足/损坏修复/离线冷启动仍待验。新增预取在真实源网络中的等待时间改善尚无实测数据。

复核命令（有针对性需要时执行，不默认全量回归）：

```powershell
& 'D:\Software\DevEco Studio\tools\node\node.exe' --no-warnings temp/reader-20261026/core-checks.cjs
.\tools\dev.ps1 -Action Build -Mode release
```

继续开发时以development-status.md和实际源码为准。后续设备检查集中进行，优先真实源问题、位置/离线恢复和G3/G4未覆盖项，不重复已经通过的自有样本流程。
