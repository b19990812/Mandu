# 0.8.3 真机图片加载诊断与修复

日期：2026-10-27（Asia/Hong_Kong）。用户授权真机测试，覆盖安装保留书架、下载、会话及设置。设备为 API24 Release 平板；应用继续 API26 编译/目标、最低 API24、schema6。

## 已确认并修复的软件问题

| 问题 | 真机证据 | 修改 |
|---|---|---|
| 双页状态对象绑定异常 | ArkUI 报 `@ObjectLink slot ... not ... @Observed ... UI will not update` | 页面槽位由稳定的 ForEach key 持有，子页保留原对象，异步结果统一通过 loadRevision 刷新本地显示状态，避免嵌套对象绑定 |
| 进度保存失败，下一章停在原章节 | 星海和绍宋均报 IO_ERROR；调用栈定位 ProgressRepository 写后回读，空结果引发 TypeError | 在事务写入前读取已有状态并计算最终已读值；两张表仍在同一事务更新，取消依赖未提交写入的回读，不改 schema、不清数据 |
| 双页下一组导致进程退出 | PID43294：PixelMap `fail to unwrap context`；BookCurlCanvas.paint 访问 undefined.size，应用因 JS_ERROR 退出 | Canvas 直接保留父组件拥有的原生位图句柄，移除 @Prop 对句柄的复制；保留数值动画参数的 @Prop，并防御无效尺寸 |
| 翻页时在父组件渲染中改写 VM | ReaderPage 报 `State variable vm has changed during render` | 属性监听收到命令后，在当前渲染结束的微任务中启动翻页，隔离已被替代的 revision；不增加固定等待 |

ReaderDatabase 只记录操作类型和数字错误码，不记录 SQL、参数、凭据或用户阅读内容。去掉了把所有异常都归因于“存储空间”的提示。临时调用栈日志已移除。

## 真机结果与边界

- 0.8.2 基线中，星海试读与已下载第1话的双页图片实际可见；切换水平单页及直接打开第2话也可见。因此本次没有重现基线一直停在“准备图片”，不能将后来发现的每个错误都等同于该症状的唯一根因。
- 0.8.3：星海第1话→第2话→第3话可切换；单页、双页图片可见。强制结束进程后重新启动，目录保留位置/已读状态，“继续阅读”恢复第3话。
- 包子真实《绍宋·人设物料》共6张：实际显示1–2、3–4、5–6，并向后翻回；修复后的最终渲染版本 PID46710 保持运行，定向日志未再出现对象绑定、渲染中改写状态或位图退出错误。图片读取包含此前已取到的磁盘缓存，不能称为最终构建冷缓存下载全章验收。
- 章节请求失败时可打开菜单和来源网站首页；回到阅读器时，“正在读取完整章节”与取消加载按钮同时可见。网站首页入口可达，页面内容一度为空，不能标记网站整页加载成功。
- 本轮没有进行两源各三章、连续手势帧率、旋转、长时内存、后台下载等完整矩阵。未运行全量测试套件。

## 网络排查

VPN 是用户明确要求保留的访问前提，本轮保持开启。`vpnEnabled:1` 只记录环境，不证明 VPN 导致超时。

同一轮实际网络既出现 HTTP200（成功握手约5–8秒），也出现 `1007900028`。失败主机包括 `www.twmanga.com` 和 `s2.bzcdn.net`。系统栈记录 `weakNetTlsTimeout`，部分请求未发出 HTTP 请求头、未收到响应头；这不是 HTTP403、域名白名单拒绝或固定500毫秒等待的证据。

应用此前硬编码连接上限10秒，失败日志的 `cfgConnectMs:10000 / totDur≈10002ms` 与其一致。现改为 `min(30000, 调用剩余时间)`，保持原有总截止时间。真机30秒配置下，HTTP200请求的握手耗时15740.62ms、总耗时16072.66ms，证实存在旧10秒上限无法完成的成功连接；同时仍有一次30秒超时，因此这不是所有请求都已可靠成功的证明。

同一已配置来源主页顺序对比：RCP原配置 HTTP200/12312ms；RCP系统TLS配置 12038ms超时；强制TLS1.2 12048ms超时；系统HTTP HTTP200/11663ms。时序与服务波动未被控制，不能凭这些单次结果断言替换接口或TLS版本即可解决。本次保留RCP和既有TLS1.2–1.3/系统证书验证，没有关闭VPN或修改代理规则。原始证据为 `connect-after30-log.txt`、`compare-network-final-log.txt`。临时接口对比代码与入口均已移除。

[华为官方超时说明](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V5/_rcp___timeout-V5)及本机 API26 RCP 声明均说明 connectMs 为连接建立时限；SDK 默认值60000毫秒。

## 最小验证与复核

直接相关宿主检查共36项：进度独立读写连接4项、加载同步/请求释放/连接预算7项、翻页17项、网络调度8项。进度检查使用两个真实 SQLite 连接，先复现原始写后回读失败，再验证修改后的保存、已读保持、过期写隔离和外键归属；不把宿主 SQLite 等同于原生 RDB。

```powershell
node temp/device-image-20261027/check-rdb.cjs
node temp/reader-recovery-20261027/check.cjs
node temp/reader-turn-20261027/check.cjs
node temp/http-access-20261027/check.cjs
.\tools\dev.ps1 -Action Build -Mode release
```

设备布局、截图、脱敏日志、安装/启动及构建记录集中在 `temp/device-image-20261027/`，索引为 `temp/list`。签名包见 `artifacts/0.8.3/hs-mihon-release-default-signed.hap`，摘要以同目录 SHA256SUMS 为准。

最终无诊断入口交付包：code14，6431346字节；SHA256 `73f7861b78377b8e5347872ca2d3838e6e8a56dc979a35154eddb382f7ca8f02`。`install-delivery.log` 包含 `install bundle successfully`，已安装版本0.8.3、启动成功，最终本地章节核查进程PID51564，星海双页和第1话→第2话可见。此前用于网络/渲染对比的同版本中间包不是最终交付物。
