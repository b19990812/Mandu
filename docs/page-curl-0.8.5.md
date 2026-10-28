# 0.8.5 原生曲面翻页与首页修复

日期：2026-10-27，Asia/Hong_Kong。版本0.8.5/code16；API26编译/目标、min API24、schema6不变。原生库为arm64-v8a。

## 问题与修复

1. 0.8.4遗漏default/lab构建目标的页面白名单。解包旧HAP确认没有pages/SourceHomePage，所以点击源名称无法进入。现已补全两处目标，修正首次实际编译首页发现的Select字体接口错误；图标与名称都可进入，路由失败会显示原因。
2. 旧卷页只沿整高窄条投影，没有二维页角约束；快照最长1024像素，翻动时清晰度降低。活动阅读器现使用独立的原生GPU曲面路径。
3. 旧页面销毁时的onReady(false)可能按相同页码影响新实例，造成图片已显示却一直等待。现按PagerSlot实例过滤就绪和失败回调。
4. Release混淆改名ArkTS中的原生present调用，而C++导出名称是字面量，造成首帧TypeError退出。现保留全部六个NAPI导出名称。
5. 真机复现双页翻动时未翻动左页下半幅变白。原缓存未充分隔离重新布局/绘制，截图也未等待全部渲染完成。现启用waitUntilRenderFinished，将每页绘制修订号纳入纹理键，同步淘汰CPU/GPU旧版本，拒绝迟到上传。

## 模块边界

| 模块 | 职责 |
|---|---|
| reader/CurlGesture.ets | 上下页角、二维抓取位置、速度、实际纸叶宽度与进度换算 |
| ui/HorizontalPager.ets | 三组稳定窗口、手势和状态机、图片就绪、末帧确认与进度提交 |
| reader/CurlFrameStore.ets | 有界屏幕尺寸PixelMap、共享截图请求、版本淘汰与延后释放 |
| reader/CurlGpuBridge.ets | 原生接口、上传去重、纹理版本和呈现序号 |
| ui/NativeCurlSurface.ets | 常驻XComponent纹理表面，空闲透明，触控继续交由阅读器 |
| cpp/CurlGeometry.* | 可展圆柱面、固定书脊、可达区域约束和法线参考计算 |
| cpp/CurlShaders.h | 静态二维网格的GPU形变、正反面UV、阴影与曲率光照 |
| cpp/CurlRenderer.cpp | NAPI、后台像素读取、EGL线程、NativeVSync、纹理预算和表面生命周期 |

XComponent支持原生EGL/OpenGL ES绘制，见[华为官方参考](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V2/ts-basic-components-xcomponent-0000001427902468-V2)。实际接口以本机API26 SDK的native_interface_xcomponent.h、pixelmap_native.h、native_vsync.h为编译依据；所用能力覆盖当前API24设备。没有依赖Android View或Android动画框架。

静止图片继续由现有ReadingCanvas和分块解码显示。各页视口完整就绪后，准备三组有界快照并等待绘制栅栏；原生后台任务读取RGBA/BGRA，EGL线程上传纹理。拖动只发布几何参数，顶点和片元着色器计算曲面及光影，手势中不截图或重新解码。

## 几何、纹理与双页

将纸叶宽度归一为1，纵坐标向下。固定外角为C，约束后的抓取点为T，d=|C-T|，n=(C-T)/d。半径R随进度与速度变化，并受书脊/可达区域约束；圆柱轴参考点F=C-n*(d+πR)/2。对材质点P，令q=dot(P-F,n)：

- q≤0：平坦区域保持原位。
- 0<q<πR：沿n投影为R*sin(q/R)，高度为R*(1-cos(q/R))。
- q≥πR：已翻过区域沿反向展开，高度为2R。

着色器以相同角度生成单位法线，UV绑定原始材质坐标。上下页角改变二维轴方向，产生不同的曲面边界；正交投影避免透视缩放导致抓取点漂移。超出物理可达范围的拖动受到约束。这是可展圆柱面近似，没有声称实现完整纸张有限元或纤维动力学。

双页LTR向前翻：当前左页保留，当前右页作为正面；下层显露目标右页，纸叶背面采用目标左页。反向翻与RTL按物理侧映射；背面UV按最终落页位置生成，不把当前漫画镜像冒充另一面。单页缺少独立纸背资源，使用不透明纸色和曲率明暗。最后不足两页时保留空白纸叶与书脊布局，继续使用双页曲面。

## 状态与交接

静止 → 准备纹理 → 拖动/自动完成 → 等待GPU末帧呈现 → 提交页码并交接静态页面 → 静止。

拖动不达阈值进入回弹；动画中按住可停留并继续拖动。自动动画采用带初速度约束的五次插值，终点速度和加速度平滑收敛。点击与手势使用相同曲面。

GPU确认最后一帧后才调用现有pagerCommit；目标快照覆盖静态页面交接的两帧，随后清除覆盖层。缩放、尺寸、模式和章节变化取消旧代动画，迟到请求及旧实例回调不得推进页码。目标不可用时保留当前有效图像。现有缩放、章节、进度、文件引用及离线链路继续复用。

## 性能边界

- 静态网格160×96，累计慢绘制时降为96×64，再降为64×40；每帧只更新uniform。
- 独立EGL线程和NativeVSync请求60–120Hz，实际刷新率由系统与设备决定。像素复制、上传在后台，大纹理上传不持有触控命令锁。
- 快照最长4096像素且最多8,388,608像素，单张32MiB、每级缓存96MiB；常见手机和本次2800×1840平板保留屏幕原尺寸。总内存还包含解码器及系统分配，预算不等于长时内存验收。
- 原生PixelMap句柄不经过Prop深复制，等待原生读取结束再释放；EGL、VSync与线程随表面销毁。缓存文件继续由原引用保护。

## 验证证据

证据位于temp/page-curl-20261027/，登记在temp/list；未运行全量测试。

| 验证 | 已确认 | 边界 |
|---|---|---|
| 生产C++几何 | 7项通过：平坦端点、二维抓取、上下角、单位法线、连续性、书脊和速度 | Windows直接编译生产函数，不是设备FPS验收 |
| 生产Pager状态 | 12项通过：纹理就绪、末帧确认、LTR/RTL、回弹、接管、缺图、预算、实例隔离、ABI、绘制修订与最后单叶 | UI和GPU确认使用宿主替身 |
| 真实双页白块 | 修复前后中间帧；未翻动左页下半区域平均RGB差由72.70降为0.00 | white-check.json只针对已取样区域，不覆盖全部视频帧 |
| 真机源入口 | 点击包子名称进入原生首页，显示48部推荐 | home-open-summary.json；不等于所有源/封面/筛选均验收 |
| 真机阅读 | 单页翻动、真实漫画右下角正向与左上角反向双页曲面、正确页序；最终包另验证RTL从19推进到21 | white-fixed、reverse-fixed和delivery-rtl截图及布局；末叶、完整RTL矩阵、手机尺寸仍需确认 |
| 性能观察 | 一次约464ms自动动画记录38次原生绘制提交，当时慢绘制计数为0 | 提交频率不等于显示端FPS；稳定60FPS、高刷、触控延迟与长时内存尚未完成系统验收 |

本轮未改动网络并发、VPN、TLS证书、下载或数据库schema。复核时另遇一次真实源TLS握手失败，重试成功；不能将卷页修复视为全部网络问题解决。

## 交付与复核

[Release签名包](../artifacts/0.8.5/hs-mihon-release-default-signed.hap)及[SHA256](../artifacts/0.8.5/SHA256SUMS)。采用hdc install -r保留旧数据。阅读设置选“双页仿真卷页”；单页选“单页仿真卷页”。临时DEBUG-curl-20261027标记已移除。

最终包7,862,875字节，SHA256为45918b0fb3bff785a509c3628f2c05ec9e9c0707312c5a2ebb565475bb5ee636。最终安装日志明确返回install bundle successfully，设备查询版本0.8.5/code16，EntryAbility启动且进程16311存活；最终定向日志未发现新增运行时退出。RTL未翻动右页下半区域与静止画面的RGB差为0。设备诊断临时文件已清理，方向恢复LTR，阅读器留在双页仿真卷页。完整索引见temp/page-curl-20261027/delivery.json。

    & 'D:\Software\DevEco Studio\tools\node\node.exe' temp/page-curl-20261027/check-pager.cjs
    & 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' temp/page-curl-20261027/check-geometry.py
    & 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' temp/page-curl-20261027/check-white.py
    .\tools\dev.ps1 -Action Build -Mode release
