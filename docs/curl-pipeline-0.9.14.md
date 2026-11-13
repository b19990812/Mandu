# 仿真翻页像素与纹理流水线优化

日期：2026-10-29（Asia/Hong_Kong）。候选版本：0.9.14 / code32。

**真机追加：0.9.14存在新增NAPI接口被混淆导致卷页初始化退出的问题，已由0.9.15修复并替代。不要使用本页旧候选包验收卷页。最新有效前台监控结果、签名包与边界见[真机监控报告](reader-curl-device-2026-10-29.md)。以下保留首次实现交付时的历史记录。**

本轮按“减少像素复制 → 提前准备目标纹理 → 调整上传与活动翻页调度 → 评估分块直接合成”执行。前三项已实现，第四项完成源码和本机 SDK 可行性评估。尚未安装或进行本轮设备性能验收，不宣称准备提示已消除。

## 1. 已实现

### 1.1 直接使用一份原生读取缓冲

原路径：`PixelMap → ReadPixels 缓冲 → 第二份 RGBA 缓冲及逐像素转换 → glTexImage2D`。

现在：`PixelMap → 一份读取缓冲 → 移交上传任务 → glTexImage2D`。

- RGBA 保留原始通道。
- BGRA 通过 OpenGL ES 3 的 `GL_TEXTURE_SWIZZLE_R/B` 设置采样通道，不在 CPU 逐像素交换红蓝。
- 行距可用整像素表示时，通过 `GL_UNPACK_ROW_LENGTH` 上传原始行距；完成或失败后恢复为 0。
- 极少见的非整像素行距在原缓冲内用 `memmove` 按行压紧，不分配第二份整图缓冲。
- 检查原生读取返回的有效字节数，拒绝不完整数据。GPU 预算按实际宽×高×4计算，不把 CPU 行尾 padding 算作纹理显存。
- 延续每帧像素上限、读取缓冲上限和 GPU 缓存预算。

这减少的是一次原生上传任务内的附加图像缓冲和转换；PixelMap、自有读取缓冲、GPU 纹理仍分别存在，**不是零拷贝，也不代表应用总内存减半**。通道映射和行距属于已有 ES3 上下文的核心功能，见 [Khronos ES3 glTexParameter](https://registry.khronos.org/OpenGL-Refpages/es3.0/html/glTexParameter.xhtml)、[glPixelStorei](https://registry.khronos.org/OpenGL-Refpages/es3.0/html/glPixelStorei.xhtml)。真实驱动颜色输出仍待设备确认。

实现：`entry/src/main/cpp/CurlRenderer.cpp` 的 `CacheExecute`、`UploadTexture`。

### 1.2 当前页和请求目标先准备

新增 `reader/CurlSnapshotQueue.ets`，只负责组件快照排队：

1. 当前组。
2. 用户请求或正在拖向的目标组。
3. 最近请求方向的下一组。
4. 另一侧相邻组。

同一时刻最多执行一个组件快照；它完成后，下一个快照可以与上一份像素的原生读取/上传重叠。已经开始的快照不强行中止；尚未开始的任务随最新意图重排，过期任务拒绝并由原有帧存储清理。

整条准备流程仍通过完整帧键去重。视口、绘制修订、局部阅读位置及页身份检查保留；截图仍使用 `waitUntilRenderFinished: true`。活动卷页锁定当前画面后，暂缓新邻页快照，交接结束后恢复。

优先顺序同时发布到 `CurlGpuBridge` 和原生上传队列。相同顺序不重复发送原生调用；方向改变只影响尚未开始的任务，不能抢占已经在执行的截图或 GL 上传。

### 1.3 活动翻页绘制优先

原生循环不再一次清空上传队列后才绘制：

- 已到达的 VSync 绘制优先于上传。
- 卷页表面可见时，不选取新的后台上传；活动卷页使用的当前/目标纹理在 `Present` 前已就绪。
- 表面清除后，按最新优先级一次选取一个上传任务，再重新检查帧和队列。
- 活动卷页等待 VSync 时，有后台上传也不会导致线程空转。
- 后台上传等待超过既有 5 秒预算时，移除仍在队列中的任务，避免之后上传已被调用方放弃的缓冲；在途任务继续按持有引用安全完成。邻页失败不取消无关的用户翻页目标，闲置后可重试。

输入在一次 GL 上传开始之后到达时，无法中途抢占该 GL 调用。本轮没有引入另一个共享 EGL 上传上下文。

新增计数：`rgbaUploads`、`bgraUploads`、`stridedUploads`、`rowCopyBytes`。它们与原有 `readMs`、`convertMs`、`uploadMs`、`uploadQueueMs` 一起供后续合成回放分析；上传队列时间可能包含有意等待活动卷页结束的时间，不能单独当作交互延迟。

### 1.4 保留的行为与边界

手势阈值、跟手曲面、单页纸背、双页正反面、LTR/RTL、窄书脊、末帧序号确认及静态页交接没有改动。正式解码默认仍为 4 路，预热最多启动 1 路，显示/预热像素预算不变；网格初始仍为 160×96，原有自动降档保留。

仅修改 5 个既有源码/版本文件，新增 1 个快照队列文件；未修改源站、数据模型、迁移、阅读设置或其他既有工作区变更。

## 2. 分块直接合成评估

### 2.1 当前可复用能力

- `DecodedTile.retain/release` 已提供独立消费者租约，可保护图像分块在合成期间不被释放。
- `TileDecoder` 有按图像、块索引及目标宽度去重的像素缓存；不需要为合成另建全图解码流程。
- 现有 EGL/GLES3 渲染线程可作为 FBO 离屏纹理合成的宿主。最终合成结果可留在 GPU，继续按现有帧键提交卷页，不必再读出整屏像素。
- 本机 SDK 26.0.0.105 头文件有 `OH_PixelmapNative_GetNativeBuffer`、`OH_Drawing_SurfaceCreateFromGpuContext` 和 `OH_Drawing_CanvasDrawPixelMapRect`，均标注 since12。API 声明可用不证明当前分块拥有 DMA 缓冲，也不证明两个 GPU 上下文可直接共享纹理。

SDK 证据路径：

```text
D:/Software/DevEco Studio/sdk/default/openharmony/native/sysroot/usr/include/
  multimedia/image_framework/image/pixelmap_native.h:1451
  native_drawing/drawing_surface.h:49
  native_drawing/drawing_canvas.h:320
```

`GetNativeBuffer` 明确可能返回 `IMAGE_DMA_NOT_EXIST`。本轮没有调用该接口探测真实 PixelMap，也未验证 EGL 原生缓冲导入和同步条件，不能宣称已经找到零拷贝生产路径。

### 2.2 推荐的原型边界

优先在现有 EGL 线程中，以**分块纹理 → FBO 视口纹理**验证合成；分块首次上传复用本轮的单缓冲路径。若随后证明当前解码产物可安全导入原生缓冲，再单独评估省去分块读取/上传。

需要一个不可变的视口描述，至少包含：

- 页/跨页身份、绘制版本、视口物理像素尺寸和背景。
- 实际布局后的图像矩形、裁剪矩形、分块源/目标矩形和采样规则。
- 左右页顺序、书脊中缝、外侧留白、奇数尾页空白半页。
- 已恢复的长图局部位置；首轮可限定现有允许卷页的 zoom=1，缩放阅读继续走既有路径。

布局描述应由静态显示与合成共同使用。不能在 C++ 再凭比例重写一套 `ReadingCanvas.baseWidth()`：其 auto 模式对长图另有适宽规则，居中上下留白、滚动恢复以及双页半宽都影响最后画面。

目前 `ImageTile` 的可见租约和 `ReadingCanvas` 实际布局位于组件内部。直接合成前要提供受控的租约借用及布局快照入口，不能靠组件私有字段或全局 PixelMap 表耦合。合成结果同样需要代次校验、字节预算、当前手势引用保护和失效回退。

### 2.3 本轮判断

**可进入离线合成图原型阶段，暂不替换生产截图路径。** 必须先证明静态页与合成页在普通图、长图局部位置、双页/LTR/RTL和奇数尾页下布局一致，并比较冷/热合成耗时、首个有效卷曲帧和内存峰值。普通 OffscreenCanvas 绘制后再导出 PixelMap 仍可能保留读取/上传，不等于上述 GPU 内合成路径。

第四项授权是评估，本轮已完成评估；FBO 合成器、分块纹理缓存及共享布局入口均未实施。

## 3. 最小必要验证

改动涉及像素格式、异步调度和资源生命周期，因此运行直接相关的 18 项宿主检查，没有运行全量回归，也没有新增测试框架：

| 分组 | 项数 | 内容与证明边界 |
|---|---:|---|
| 原生像素 | 4 | 将修改前后的 `CacheExecute`、`UploadTexture` 方法原文编译为 Windows DLL；80 组尺寸/RGBA/BGRA/行距布局输出一致；分配计数由两份变一份；短读取、非法格式及 GL 失败恢复。PixelMap、分配计数和 GL 采样使用受控替身，不是真实驱动验收。 |
| 原生调度 | 4 | 编译生产 `Run` 选择分支与唤醒条件；绘制优先、活动表面暂停上传且不空转、恢复与换向、过期任务丢弃。没有模拟真实线程竞争和驱动时序。 |
| 阅读器准备/交接 | 10 | 41次移动仍共用1条准备链；末帧确认、过期截图释放、失败重试；快照串行、换向重排、暂停恢复；请求目标优先、无关邻页失败隔离。ArkUI/GPU为替身。 |

结果：18/18 PASS。80 组像素数据差分包含在其中一项检查内，不能写成额外 80 项测试。

Release default 非增量构建：33项任务执行，原生编译、CompileArkTS、PackageHap、SignHap、assembleHap通过；334个源码/资源/构建支持文件构建前后摘要一致，归档前再次核实。沙箱内首次遇到 Node realpath EPERM，沙箱外重试成功。现有 `page_show` 资源冲突警告和 clang `--gcc-toolchain` 未使用警告仍存在，本轮未做无关资源整理。

## 4. 签名包与证据

- 包：`artifacts/curl-pipeline-20261029/hs-mihon-0.9.14-curl-pipeline-release-signed.hap`
- 版本：0.9.14 / code32；8,115,047字节。
- SHA256：`9965535641ee8207e93c329e0cd7a6d66ba81f342f841dae3fe18f28178690b1`。
- 包内：min API24（60101024）、target API26（260000026）、compile SDK26.0.0.105，phone/tablet，含 `arm64-v8a/libpagecurl.so`。
- 同目录：`delivery.json`、三组 `*-checks.json`、`source-sha256.json`、`SHA256SUMS`。
- 临时脚本、修改前快照、编译产物、构建日志：`temp/curl-pipeline-20261029/`，已登记 `temp/list`。构建强制使用 `.hvigor/`、`entry/build/`，清单沿用已有记录。

没有安装、启动或运行设备回放；没有读取真实漫画正文；没有 Git commit、push、PR 或新自动化。

## 5. 复核与未验证项

项目根目录 PowerShell 可复核相同范围：

```powershell
python temp/curl-pipeline-20261029/native-check.py
python temp/curl-pipeline-20261029/schedule-check.py
& 'D:/Software/DevEco Studio/tools/node/node.exe' temp/curl-pipeline-20261029/pager-check.cjs pager-checks.json
& ./temp/curl-pipeline-20261029/build.ps1 -Stage recheck -Target default
```

未验证真实设备上的 RGBA/BGRA颜色、纹理行距、冷/热等待、触摸到显示延迟、物理 FPS、API24运行和长时间内存。原因是本轮以核心实现及最小宿主/构建检查为范围；历史0.9.12/0.9.13结果不能替代本包验收。

后续设备复核应使用固定合成样本重建 lab 包，普通单页及长图双页均保持4路、相同网格和节奏，以旧包/新包同条件比较。可从下列命令开始；本轮未执行这些设备操作：

```powershell
& ./temp/curl-pipeline-20261029/build.ps1 -Stage device-lab -Target lab
& 'D:/Software/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe' install -r 'temp/curl-pipeline-20261029/device-lab/device-lab-lab-signed.hap'
& 'D:/Software/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe' shell aa start -a EntryAbility -b com.hsmihon.reader --ps readerProbe synthetic --ps probeMode curl --pi probeLanes 4 --pb probeLong false
```

长图双页将 `probeMode` 改为 `spread`，`probeLong` 改为 `true`。设备结果必须单独归档在本任务 `temp/` 子目录并维护清单；保留应用数据，禁止卸载或清数据。动画最终序号确认是交换确认，仍不是物理屏幕扫描完成时间。
