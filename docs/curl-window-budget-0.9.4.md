# 0.9.4 双页翻页解码预算修复

日期：2026-10-28（Asia/Hong_Kong）。用户反馈：《女友的朋友》在双页仿真翻页时仍出现“图片解码已满”。版本：0.9.4/code22。

后续状态：用户反馈静态限额导致清晰度下降；[0.9.5](curl-quality-budget-0.9.5.md) 已撤销该降分辨率策略，将前台预算扩大到 128 MiB，并保留旧图释放修复。下文记录 0.9.4 的历史实现与证据。

## 原因与修改

上一轮已分开前台与预解码池，但没有限制翻页窗口的静态图片用量。`HorizontalPager` 同时保留前、中、后三组；双页模式共六张静态图片，它们在截图之前就可能耗尽前台 48 MiB。四兆快照上限只约束截图及纹理，无法限制截图之前的分块解码。

此外，`ImageTile.presented()` 原来先检查解码代数，再释放旧图。如果新一轮解码先发生，旧回调会直接返回，跳过自己对应的旧图释放。布局改变时，即使实际解码宽度没有变化，也会再次申请 PixelMap。

修复涉及：

- `ReadingCanvas.ets`：增加可选的窗口像素额度，根据可见源区域、边缘分块、尺寸取整和替换所需空间计算分块最大解码宽度。长图按视口限制，不按整张长图缩小。
- `HorizontalPager.ets`、`SpreadViewer.ets`：每组提供 4,194,304 像素的静态解码额度；双页左右各半。额度至少保留四分之一用于旧/新图交接，并容纳一块替换图。实际静态图分辨率因此可能低于截图分辨率。
- `ImageTile.ets`：按限制后的宽度获取及预解码图片；实际宽度相同则复用原图。绘制回调释放自己捕获的旧图列表，再单独检查就绪通知是否仍有效，避免漏释放或提前释放更晚的图片。
- `AppScope/app.json5`：版本升至 0.9.4/code22，便于确认设备实际安装版本。

前台 48 MiB、预解码 16 MiB 和翻页快照 4,194,304 像素上限保留。常驻三组图片按额度为交接预留空间，而不是提高总显示预算。

## 验证

修改前，生产 `ImageTile.load` / `TileDecoder` 调用链在合成的 2400×3200 图片、2800×1840 双页窗口下复现原报错。此尺寸用于宿主复现，并非对《女友的朋友》实际图片尺寸的测量。

修改后的 7 项定向检查通过：三组双页、竖屏单页、长图视口、旧章节覆盖层交接、连续重排、旧代绘制回调释放、相同解码宽度复用。另复核上一轮缓存隔离及四兆快照契约的 8 项检查，全部通过；未运行全量测试。

| 宿主合成场景 | 已交付静态分块用量 |
|---|---:|
| 三组双页 | 37,532,448 字节，约 35.8 MiB |
| 三组竖屏单页 | 37,636,488 字节 |
| 三组双页长图视口 | 37,492,800 字节 |
| 三组及旧章节覆盖层 | 50,043,264 字节，低于 48 MiB |

检查使用生产 ArkTS 函数，ImageKit、UI 和帧通知为宿主替身；上述用量是分块租约计数，不是系统实测进程内存。

```powershell
& 'D:\Software\DevEco Studio\tools\node\node.exe' temp/curl-window-budget-20261028/check-window.cjs
& 'D:\Software\DevEco Studio\tools\node\node.exe' temp/curl-cache-split-20261028/check.cjs checks-window-followup
```

## 交付与验收边界

Release 的 ArkTS 编译、打包和 `SignHap` 成功。包内为 0.9.4/code22、最低 API24、API26 编译/目标、phone/tablet，包含 arm64-v8a 原生翻页库。

[签名安装包](../artifacts/0.9.4/hs-mihon-release-default-signed.hap) · [SHA256SUMS](../artifacts/0.9.4/SHA256SUMS)

已通过 `hdc install -r` 保留数据覆盖安装，结果明确返回 `install bundle successfully`；设备查询确认 0.9.4/code22。`EntryAbility` 启动成功，并取得进程存活证据。

本轮设备验证仅覆盖安装与启动；尚未在设备上重放《女友的朋友》的连续双页翻动。该漫画具体章节、双向连续翻页、旋转和切章，以及系统峰值内存和长时间运行仍由真实阅读确认。

证据位于 `temp/curl-window-budget-20261028/`；旧缓存隔离契约复核结果位于 `temp/curl-cache-split-20261028/checks-window-followup.json`。临时产物已登记 `temp/list`。
