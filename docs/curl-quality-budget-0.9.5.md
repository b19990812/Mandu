# 0.9.5 恢复静态清晰度并扩大解码缓存

日期：2026-10-28（Asia/Hong_Kong）。用户反馈 0.9.4 的静态解码限额降低清晰度，要求通过增加缓存上限解决。

## 最终行为

- 撤销 0.9.4 的每组静态像素额度和相应宽度压缩，恢复按实际显示宽度解码。原有单分块宽度 2048、单块 8 MiB 上限继续有效。
- 前台静态解码池由 **48 MiB 提高到 128 MiB**，包括当前页、相邻翻页准备页面及尚未完成交接的旧图。
- 图片预解码池继续独立使用 **16 MiB**；命中时转移资源归属，不重复解码。
- 仿真翻页快照及原生纹理继续采用 **4,194,304 像素**上限。
- 保留旧图释放回调修复，以及实际解码宽度相同则复用原图的逻辑。

修改文件：`image/TileDecoder.ets`、`ui/ReadingCanvas.ets`、`ui/ImageTile.ets`、`ui/HorizontalPager.ets`、`ui/SpreadViewer.ets` 及版本配置。版本为 **0.9.5/code23**。

## 最小验证

15 项定向检查通过：7 项覆盖原显示宽度、三组双页、竖屏单页、长图、切章覆盖层、连续重排和旧图释放；8 项覆盖 128 MiB/16 MiB 独立池、满池拒绝、归属转移、取消释放及四兆快照。未运行全量测试。

合成窗口中，恢复原显示宽度后的三组双页静态图占 60,973,920 字节，长图视口占 100,296,000 字节，均在 128 MiB 内。它们使用生产 ArkTS 解码调用链、宿主 ImageKit/UI 替身，不是《女友的朋友》的图片尺寸或设备进程内存测量。

```powershell
& 'D:\Software\DevEco Studio\tools\node\node.exe' temp/curl-quality-budget-20261028/check-quality.cjs checks-quality
& 'D:\Software\DevEco Studio\tools\node\node.exe' temp/curl-quality-budget-20261028/check-pools.cjs checks-pools
```

扩大后的两类分块预算合计 144 MiB；翻页快照、GPU 纹理和系统编解码临时内存另计。设备上实际清晰度、连续翻页及系统峰值内存仍需真实阅读确认。

## 交付

[0.9.5 签名安装包](../artifacts/0.9.5/hs-mihon-release-default-signed.hap) · [SHA256SUMS](../artifacts/0.9.5/SHA256SUMS)

构建、安装与启动结果以 `temp/curl-quality-budget-20261028/delivery.json` 及原始日志为准。构建使用独立主构建缓存、禁用增量，并核对构建前后的源码哈希。临时文件已登记 `temp/list`。

已以 `hdc install -r` 保留数据覆盖安装；设备明确返回安装成功，并确认 0.9.5/code23。EntryAbility 启动与进程存活检查通过。本轮未在设备上重放指定漫画的连续翻页。
