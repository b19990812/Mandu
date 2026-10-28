# 翻页与预解码缓存隔离

日期：2026-10-28（Asia/Hong_Kong）。基于当前 0.9.3/code21 构建。

## 修改结果

`CurlFrameStore` 原本已独立保存翻页快照。实际共用的是 `TileDecoder` 中前台图片与 `TileWarmCache` 预解码图片的用量计数；翻页前准备的静态页面同样经过这一解码路径。

| 资源 | 修改后预算与归属 |
|---|---|
| 前台显示及翻页前静态页面准备 | 独立 48 MiB；只统计已交给显示层的分块 |
| 图片预解码 | 独立 16 MiB；缓存淘汰只释放预解码资源 |
| 仿真翻页快照 | 独立 `CurlFrameStore` 和原生 GPU 缓存；单张最多 4,194,304 像素，最长边 4096 |
| 图片预下载 | 继续使用压缩文件磁盘缓存，不占上述 PixelMap 预算 |

命中预解码缓存时，`DecodedTile.promote()` 先检查前台容量，再同步转移字节归属，复用同一个 PixelMap。释放按转移后的所属池记账；前台已满时仍执行容量限制。解码器继续串行调用系统编解码接口。

`curlSnapshotScale()` 由 2,097,152 调整为 4,194,304 像素，并按整数尺寸收紧缩放比例，避免快照取整超过上限。`CurlFrameStore` 和原生 `CurlRenderer` 均检查实际像素数。

设计取舍：前台保留原 48 MiB 容量，另给预解码 16 MiB，已交付分块的合计上限成为 64 MiB。此数不包含系统编解码临时内存、翻页快照、原生复制及 GPU 分配，不能作为进程实际内存上限。

## 涉及文件

- `entry/src/main/ets/image/TileDecoder.ets`：分开计数、归属转移及释放；在异步关闭图像源后重新检查容量和取消状态。
- `entry/src/main/ets/image/TileWarmCache.ets`：按预解码池淘汰，显示时转移租约。
- `entry/src/main/ets/reader/PageTurnGeometry.ets`：四兆快照缩放上限。
- `entry/src/main/ets/reader/CurlFrameStore.ets`：快照实际尺寸检查。
- `entry/src/main/cpp/CurlRenderer.cpp`：原生纹理实际像素检查。

## 验证与交付

修改前宿主复现捕获了“图像解码预算已满，滚动后重试”。修改后 8 项最小定向检查全部通过：独立预算、缓存命中转移、淘汰与释放、前台满池、取消和异常、清理期间迟到结果、四兆缩放、快照拒绝及失效。

检查调用生产 ArkTS 函数，ImageKit 使用宿主替身。没有运行全量测试，也没有安装设备或进行真机连续翻页、GPU 呈现及长时间内存验收。

复核命令：

```powershell
& 'D:\Software\DevEco Studio\tools\node\node.exe' temp/curl-cache-split-20261028/check.cjs
```

Release 构建通过 ArkTS、原生 C++ 编译、打包与 `SignHap`。包内元数据：0.9.3/code21、API24 最低版本、API26 编译/目标、phone/tablet，包含 arm64-v8a 的 `libpagecurl.so`。

[本次独立修复包](../artifacts/0.9.3/curl-cache-split-20261028/hs-mihon-release-default-signed.hap)与 [SHA256SUMS](../artifacts/0.9.3/curl-cache-split-20261028/SHA256SUMS)。该包保留 0.9.3/code21，单独保存以便与此前同版本候选包区分。

证据目录：`temp/curl-cache-split-20261028/`，已登记 `temp/list`。设备复核应覆盖开启预存时连续单页/双页翻动、返回前页及切换章节；安装使用 `hdc install -r` 保留数据。

## 后续修复

用户随后反馈《女友的朋友》双页仍报解码已满。0.9.4 补充了截图前的静态窗口限额、旧图释放与重复解码修复，详见 [0.9.4 双页窗口修复](curl-window-budget-0.9.4.md)。0.9.3 的缓存隔离宿主检查不代表完整阅读场景已验收。
