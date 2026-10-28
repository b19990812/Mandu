# 0.3.0 功能交付记录

2026-10-26，API26目标、min24、phone/tablet，数据库schema4。

本轮把0.2原型推进为可构建的完整本地业务：源规则管理、搜索、详情目录、书架分类、历史进度、共享阅读器、下载离线、设置和手动更新。按用户反馈优先修复阅读画面过小、长图回顶及菜单无法操作，并对齐Mihon的主导航、章节入口和阅读顶底栏。

## 当前产物

- 正式签名包：artifacts/0.3.0/hs-mihon-release-default-signed.hap
- 开发签名包：artifacts/0.3.0/hs-mihon-debug-lab-signed.hap
- 摘要：artifacts/0.3.0/SHA256SUMS
- 构建日志：temp/stage3/release-0.3-build.log、reader-final-build.log
- 包核查：temp/stage3/final-checks/artifact-result.json

最终两目标均BUILD SUCCESSFUL并执行SignHap。正式HAP由SDK verify-app验证代码签名、摘要和权限签名通过；12个正式路由、API26/min24、phone/tablet与权限声明已从交付包读取。混淆缓存中持久化/路由字段未改名，Release没有实验室代码。最终Release覆盖安装输出为install bundle successfully；没有启动锁屏设备。

| 产物 | 字节 | SHA256 |
|---|---:|---|
| Release/default | 6037065 | f5067335dd3b7d33ef54e6da586e49ecccf9c8b7d7c43462503988e1182e2f24 |
| Debug/lab | 7186383 | cf70d9178beff07755e0390e9077da693cd7386663efd6e77de88185f9ff508b |

使用hdc install -r覆盖安装，保留用户数据；不要卸载或清空数据库。签名为本机DevEco开发签名，适用其授权设备。旧0.2.0包保留，但已经迁移到schema4的数据不能通过降级旧应用继续写入。

## 实现取舍

采用原生ArkUI行为对齐Mihon，没有移植Android运行时。规则为有限声明式协议，复杂的公开格式集中在内置适配器。图片先经受控网络提交私有文件，再按可见块解码；浏览缓存和离线文件相互独立。

包子搜索短标识通过详情明确声明的canonical映射到章节标识，重复目录合并。COPY仅读取公开页面同时提供的固定格式与编码清单，不执行站点脚本。网页快照分别得到287/233章和163/17个指定章图片资源，不等于原生整章通过。

系统下载代理Range限额的真机反例促使生产继续使用RCP硬限额流写，加上只覆盖当前图片的dataTransfer租约，见[后台决定](background-transfer-decision.md)。

## 验证和验收缺口

已完成与本轮核心变化直接相关的检查：双源快照、生产SQL迁移/进度/下载状态、缓存引用和清理、调度及分块模型。此前原生完成规则探针、书架/历史、自有章节下载和离线、普通与长图区域解码、页式体验修复。详细证据见[验证记录](verification.md)。

最终Release及新增条漫缩放/试读位置/dataTransfer尚未真机验证：设备再次锁屏，用户明确目前无法解锁，要求先做功能开发。COPY在设备TLS失败、包子此前302后403仍未解决，两个真实源各三章验收未齐。项目首版不能标记全部验收完成。

后续范围R12/R13/R15/R16，以及上游Mihon的其他高级功能，不因本次界面对齐被自动纳入首版。
