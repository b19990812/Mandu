# HIP 阅读修复：0.9.6

已将 HIP 正文图片清单改为直接通过网站公开 API 获取，并在平板上验证此前返回 403 的三个章节均能显示真实正文。0.9.6 / versionCode 24 已通过保留数据的覆盖安装交付。

## 问题与方案

旧实现进入章节后，先读取 `reader.hipmh.top/chapter/<hid>` 的 HTML，仅为提取 API 章节标识。这一步在真机上返回 Cloudflare challenge（HTTP 403），导致后续 API 和图片请求无法执行。仅更换 User-Agent 的对照仍失败，证据见 [此前诊断](hip-device-diagnosis-2026-10-28.md)。

网站目录和阅读页使用的公开标识编码相同作品、章节和顺序信息：

- 目录标识前段解码为 `m:15031-c:13975`，阅读页的 API 标识前段解码为 `c:13975`。
- 后段均为作品及顺序，例如 `15031:1.00`，转换时保留原编码。
- 对照材料为网站原 HTML 的 `data-frontend-hid` / `data-api-hid` 属性及目录 JSON。真实 API 取样返回 HTTP 200，并确认 `manga_id=15031`、`chapter_id=13975`。

新链路为：

```text
目录中稳定的章节标识
  → 校验并转换公开 API 标识
  → hipapi1.s3file.top/v2/chapter
  → 校验返回的 manga_id / chapter_id
  → 既有 HipFormat 图片清单处理
  → 既有 CDN、下载校验及原生图片解码
```

首页和详情仍解析 HTML，目录仍使用原 API；正文不再请求阅读页 HTML。

## 改动边界

- `source/adapters/HipChapterId.ets`：有界、规范 Base64 编码校验；验证作品标识、章节标识和顺序后段中的作品身份一致；只生成 API 请求标识。
- `source/adapters/HipSource.ets`：正文直接请求 API，校验返回的作品和章节 ID；适配器版本升级为 2。
- `source/CopyAccess.ets`：同步 HIP 原生版本和快照版本为 2。
- `AppScope/app.json5`：0.9.6 / code 24。

原 sourceId、作品 ID、章节 remoteId/locator、页面键不变，收藏和阅读进度继续使用原身份。原生快照升级后，旧 HIP 固定版本下载任务会明确提示版本变化；如存在此类任务，仅取消并重新加入对应 HIP 任务即可。

公共 `image/FileVerifier.ets` 的 SHA256 与修改前完全一致。本次没有为 HIP 添加图片 AES 解码或修改阅读器、缓存预算、TLS 和会话隔离。

## 最小验证

主机检查直接调用生产 `HipSource.pages()`：在阅读页固定返回 403、公开 API 正常的条件下，修改前失败，修改后通过。7 项检查覆盖直接 API 路径、稳定页面键、错误作品/章节拒绝、畸形标识拒绝、适配器快照版本一致，以及保留的 69 个真实目录标识转换。

```powershell
& 'D:\Software\DevEco Studio\tools\node\node.exe' .\temp\hip-api-fix-20261028\check-api.cjs
```

主机使用既有 Node loader 替代 ArkTS util 接口；这些检查与下述真机证据分别记录，没有运行全量回归。

| 真机重放 | 本次验证结果 |
| --- | --- |
| 《我独自升级 : 诸神黄昏》预热 | 真实图片显示；依次核对 1–2、3–4、5–6、7–7，共 7 页 |
| 同作品第1话 | 从预热末页换章成功；417 页清单，前两页真实图片加载成功 |
| 《登录武林系统》第1话 祝您武运昌隆 | 204 页清单，前两页真实图片显示 |
| 安装与版本 | `install bundle successfully`；设备 0.9.6 / code 24，进程存活，HIP 显示 v2 |
| 构建 | 禁用增量编译；CompileArkTS、SignHap、BUILD SUCCESSFUL |

这三个场景均未再出现阅读页 403 或图片容器错误。当前证据足以确认这些章节的打开故障已解除；未完成另外两个长章节的全页检查、下载后重启离线或完整 G2 验收。此前描述的独立容器错误未复现，未将其归因为缺少解密或通用格式校验错误。

## 交付与证据

- 签名包：`artifacts/0.9.6/hs-mihon-release-default-signed.hap`，8,002,215 字节。
- SHA256：`0a45a14c3e2f40605cb7c41b1956541cc6f9125261db67d21b7b81d6d80498c8`。
- 包内元数据：API24 compatible / API26 target-compile，phone/tablet，保留 native curl。
- 交付摘要和源码 SHA256：`artifacts/0.9.6/delivery.json`。
- 原始失败基线、7 项检查、构建、设备版本和 UI 文本：`temp/hip-api-fix-20261028/`。
- 真实显示截图：`warmup-page1.png`、`work2-page1.png`，均位于上述 temp 子目录。
- 临时文件用途及保留规则见 `temp/list`；未清除用户数据。
