# 0.9.8 阅读历史删除与封面搜索交付

日期：2026-10-28。版本：0.9.8 / versionCode 26。

## 用户行为

历史页每部漫画提供“删除历史”。“批量删除”展开时间选择，删除的是**最近时间内**的历史，按每部漫画最近一次阅读时间筛选，不是删除早于该时段的记录。

| 选项 | 范围 |
| --- | --- |
| 最近1分钟 | 确认预览时刻向前60秒 |
| 最近1小时 | 向前60分钟 |
| 最近1天 | 向前24小时 |
| 最近7天 | 向前7×24小时 |
| 最近1个月（30天） | 向前30×24小时 |
| 全部历史 | 不限制时间 |

时间范围包含起止边界，按滚动时间计算。弹窗先显示将删除的漫画数量，确认后执行。只移除历史列表记录，阅读位置、已读状态、收藏、书签、下载保留；再次实际阅读会重新进入历史。

同一漫画的旧章节会一并从历史中隐藏，避免删除最近记录后又出现旧章节。弹窗出现后如果该漫画又被阅读，提交时检测最新阅读时间变化并保留该漫画，反馈跳过数量。延迟到达的旧阅读进度不会让删除项重新出现。

全局搜索改为封面卡片，封面下显示两行内的漫画名，宽度自适应2至7列。每个源默认预览一行，可“查看全部”本次已取得的结果；“加载更多”仍只请求对应源下一页。点击源标题可折叠整组，顶部提供“全部展开”“全部折叠”。折叠不清空结果、计数、分页状态，展开不重新搜索。封面复用现有本地缓存和取消机制；折叠、离屏后释放视图。

## 实现边界

- `entry/src/main/ets/model/HistoryDeletion.ets`：时间范围、预览计划与参数校验。
- `entry/src/main/ets/storage/ProgressRepository.ets`：按漫画最新阅读时间预览、事务内重新核对并隐藏历史，沿用已有字段，无数据库迁移。
- `entry/src/main/ets/vm/HistoryVM.ets`：预览与提交分离、忙碌状态和结果反馈。
- `entry/src/main/ets/ui/HistoryPanel.ets`：单项删除、时间选择和确认弹窗；独立历史页复用该组件。
- `entry/src/main/ets/vm/SearchVM.ets`、`pages/SearchPage.ets`：按源折叠状态、封面行、宽度适配；保留迁移页使用的平铺结果数据。

HIP API修复、公共图片校验器与漫画源接入方式未改动，交付脚本核对0.9.6记录的相关源码哈希全部一致。封面排查中添加的日志和无效请求改动均已移除。

## 验证及证据

最小验证范围包含本次历史数据操作和搜索状态变化，没有运行全量回归。

1. 7项历史定向检查通过：5个时间窗口及边界、单项与全部隐藏、进度/收藏/书签/下载保留、确认前重新阅读、延迟进度回调、非法计划拒绝、VM预览不修改数据与提交刷新。使用隔离SQLite和生产Repository代码，涵盖双连接读取。
2. 12项搜索定向检查通过：并发聚合、源过滤、独立分页重试、取消与关键词代次、预览展开、单源及全部折叠、2列/7列重排不丢失漫画身份且不额外搜索。
3. 最终签名构建通过，包含`SignHap`；`hdc install -r`明确返回`install bundle successfully`，Ability启动成功，有进程，设备安装版本0.9.8/code26。
4. 最终包真机搜索“升级”：8个已激活源完成，共191部。全部折叠时结果封面Image节点为0；单独展开COPY和HIP时各有7个实际Image节点，截图核实均为真实封面。
5. 点击COPY“無限升級in武林”封面进入对应源详情，返回后关键词、191部计数和折叠状态保留。历史页再次确认17部记录显示，批量菜单为“最近”语义。

真机操作期间曾误触最近一天删除确认，17部历史被隐藏。已停止应用、备份数据库，按该次操作唯一时间戳恢复每部漫画最近历史的可见性。恢复前后12张表比对，除历史可见字段外没有差异，最终界面重新显示17部；相关数据库备份仅保存在本地`temp/history-search-20261028/history-recovery/`，不放入交付包。该次操作也验证了原生批量提交与列表刷新；单项及其他时间范围实际提交由隔离数据库验证，不额外删除真机既有数据。

### 封面可用性限制

真机网络访问包子静态封面域名`static-tw.baozimh.com`返回Cloudflare 403、HTML响应。生产解析器可正确取得57/57个封面地址；主机相同公开地址返回200 JPEG。真机调整User-Agent、移除Referer、去除缩略图参数的对照均不能消除403，故未保留这些无效改动。当前包子源封面会显示占位，漫画标题及详情导航可继续使用；不能把COPY/HIP成功扩展为所有源封面均通过验收。

尚未进行全量回归、所有源所有封面/分页穷举、不同屏幕尺寸的真机覆盖。2至7列已做状态检查，真机界面为横屏平板7列。网络结果数量随源数据与激活设置变化。

### 证据路径

证据统一在`temp/history-search-20261028/`，详见`temp/list`：

- `checks-history.json`、`checks-search.json`：定向检查结果。
- `history-cover-release-build.log`、`release-install.txt`、`release-start.txt`、`release-version.txt`、`release-process.txt`：最终构建安装。
- `hs-release-folded-layout.json`、`hs-release-copy-open-layout.json`、`hs-release-hip-covers-layout.json`：最终原生节点。
- `hs-release-copy-covers.png`、`hs-release-hip-covers.png`、`hs-release-history-manage.png`：最终界面截图。
- `hs-single-dialog-layout.json`、`hs-history-ranges-layout.json`、`hs-recent-day-dialog-layout.json`：单项/时间范围/批量确认预览。
- `cover-diagnostic.log`、`baozi-cover-probe.json`：封面403与地址解析对照。
- `history-recovery/verification.json`：恢复后逐表一致性核对。

复查命令（项目根目录PowerShell）：

```powershell
& 'D:\Software\DevEco Studio\tools\node\node.exe' .\temp\history-search-20261028\check-history.cjs
& 'D:\Software\DevEco Studio\tools\node\node.exe' .\temp\history-search-20261028\check-search.cjs
& .\temp\history-search-20261028\build.ps1 -Label history-cover-recheck
```

## 安装包

`artifacts/0.9.8/hs-mihon-release-default-signed.hap`，8,028,161 bytes。

SHA-256：`952844d1aa9e774aea26cb118b49d642563ca53936239e19a06c8a51dd765e54`。

包内元数据：兼容API24（60101024），目标API26（260000026），compileSdkVersion 26.0.0.105，phone/tablet，保留`libpagecurl.so`。`delivery.json`包含源文件哈希、验证范围和限制，`SHA256SUMS`供文件校验。此包与最终真机安装的签名包哈希相同。
