# 0.8.1 图片请求固定等待修正

日期：2026-10-27（Asia/Hong_Kong）

用户报告内置包子图片缓冲失败，并怀疑同源请求的 500 毫秒间隔。代码和最小复现确认存在两层独立等待：

1. `AssetTransfer` 每次尝试下载图片前，无条件调用 `waitSourceInterval` 等待 500 毫秒。
2. `RequestScheduler` 每放行一个请求，又把相同源和相同域名的下次放行时间推后 500 毫秒，即使还有并发空位。

同一个等待函数还用于章节图片清单分页、图像地址刷新和目录分页，导致无网络延迟的分页仍然等待。

## 修改

- 移除共享请求前置等待及其全部生产调用点；图片首次请求、重试、清单/目录翻页和地址刷新均不再固定休眠。
- 调度器在并发容量可用时立即放行，取消正常请求间的固定间隔。
- 并发继续由调度器统一管理：全局最多 4 个、同源及同域名最多 2 个；前台请求优先于预取和下载。
- 保留服务器错误后的冷却及 `Retry-After`、取消、截止时间、有限重试和完整清单检查。

本次只修正已复现的固定等待，不修改网址协议、域名策略、证书验证、图片格式校验或缓存数据模型。

## 定向验证及边界

```powershell
node .\temp\http-access-20261027\check.cjs
.\tools\dev.ps1 -Action Build -Mode release
```

复现使用实际生产图片传输、RCP 调度路径和宿主真实计时；网络底层、原生接口和文件验证使用桩，因此不是公网包子下载或设备成功证据。

| 检查项 | 修改前宿主测量 | 修改后宿主测量 |
| --- | --- | --- |
| 第一张图片开始请求 | 523 ms | 4 ms |
| 第二张图片开始请求 | 1035 ms | 4 ms |
| 两次请求开始时间差 | 512 ms | 0 ms |
| 三批章节图片清单 | 1016 ms | 3 ms |
| 首批图片地址刷新 | 524 ms | 3 ms |

8 项定向检查通过，Release CompileArkTS、PackageHap 和 SignHap 成功。保留服务器要求等待的检查中，`Retry-After: 1` 仍等待约 1 秒。所有计时仅用于证明人工休眠已消除，不代表实际网络下载速度。

证据：`temp/http-access-20261027/baseline.json`、`checks.json`；构建日志在同目录 `build.log`。只做本次网络链路的定向检查，不运行全量回归。

签名包：`artifacts/0.8.1/hs-mihon-release-default-signed.hap`，摘要见同目录 `SHA256SUMS`。API26 目标/编译、API24 最低兼容保持。此包尚未完成设备安装或包子真实取图验收。

覆盖安装时保留原有数据：

```powershell
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r .\artifacts\0.8.1\hs-mihon-release-default-signed.hap
```

实际核查应重新打开原包子章节，观察起读及连续翻页的图片准备；若仍显示失败，需要保留完整错误文字与失败图片所属域名，进一步区分 CDN 响应、TLS 或缓存写入错误。不能仅凭本次宿主检查把图片缓冲失败标为已闭环。
