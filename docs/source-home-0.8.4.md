# 0.8.4 漫画源原生首页

日期：2026-10-27，Asia/Hong_Kong。版本：0.8.4 / code15，Release/default。API26编译与目标、min API24、schema6不变。

后续更正：0.8.4遗漏构建目标的页面白名单，最终HAP未包含原生首页路由。本页保留实现与宿主检查记录；可进入的首页及实际页面编译修复由[0.8.5](page-curl-0.8.5.md)交付，不能把0.8.4构建成功视为首页原生验收。

## 使用入口与栏目

浏览页点击已启用的包子或COPY名称进入原生首页；也可从“漫画源网站”列表点击“漫画源首页”。首页保留搜索和网站按钮，卡片进入现有详情页，再收藏或打开章节阅读。浏览列表本身不会自动收藏作品，仅点击的作品写入现有漫画目录。

| 来源 | 栏目 | 筛选及分页 |
|---|---|---|
| 包子 | 推荐、热门、更新、新上架、完结、分类 | 分类支持题材、地区、状态；完结固定已完结，可选题材、地区。分类/完结按网站声明的AMP接口加载下一页；其他栏目显示网站当前返回的条目。 |
| COPY | 推荐、热门、更新、新上架、完结、排行榜、分类 | 热门/更新支持题材、地区、状态，分别固定热门/更新时间排序；分类另可排序，完结固定已完结并支持题材、地区、排序；排行榜支持男/女频与日/周/月/总榜。分类列表和新上架按网站提供的分页加载。 |

封面网格按窗口可用宽度显示2至8列；窄屏默认收起筛选，点击“展开筛选”后选择，宽屏直接显示。选项来自各源网站及其已确认的状态/排序契约，组合条件可重置。切换栏目或条件重新从第一页加载；加载中可切换栏目或取消，旧请求结果不会覆盖新栏目。后续分页失败保留已加载条目，可重试；没有下一页时隐藏“加载更多”。

## 实现边界

- `model/SourceTypes.ets` 增加可选 `Source.discovery` 能力，注册层负责来源版本隔离；旧JSON/HTML规则的四个操作和导入格式不变，暂不自动推断任意网站的首页。缺少此能力的规则源继续进入搜索，也可打开网站。
- `source/discovery/` 处理两站栏目、筛选、分页和数据解析；`SourceDiscoveryService` 复用现有目录存储；`SourceHomeVM` 负责取消、分页去重和状态；`SourceHomePage` 使用现有封面与界面样式。
- COPY页面的列表属性使用单引号数据字面量。新解析器只接受受限数据语法，不执行网页脚本或 `eval`。封面仅加入实际观察到的精确域名，章节图片域名策略保持现状。
- 分页令牌绑定源身份、网址修订号、栏目与筛选值。列表最多2000项，单次响应上限2MiB；重复分页和来源结构变化会显示错误，可从“网站”继续访问。
- 点击首页卡片复用 `CatalogRepository.saveSearch`。修正其“事务未提交即从独立连接读取新记录”的问题，改为提交后回读，避免首次点击无法取得作品ID；原有收藏、章节、进度和稳定身份继续保留。没有数据库迁移。
- 本轮未调整网络并发、连接时限、VPN或证书验证策略。主机能获取源页面不等同于平板原生TLS/所有章节图片均已可用。

## 验证证据

已对本次公共能力接口、分页取消和首次存储链路执行最小定向检查，未运行全量测试：

| 检查 | 结果与边界 | 证据 |
|---|---|---|
| 生产解析器与VM定向检查 | 12项通过。包含真实首页/列表/分页快照、COPY组合筛选、数据语法拒绝脚本、列数、切换栏目取消和迟到结果隔离。使用宿主URL/界面替身，未模拟原生渲染。 | `temp/source-home-20261027/check.cjs`、`checks.json` |
| 首次访问与存储检查 | 4项通过。用独立SQLite读写连接核对提交后回读、重复访问保留收藏和章节进度、取消回滚、选择卡片的来源检查及监听释放。不是原生数据库或迁移验收。 | `check-catalog.cjs`、`catalog-checks.json`（同目录） |
| 既有两源操作 | 两源搜索、详情、目录、章节清单的旧快照定向场景通过，未扩大全量回归范围。 | 执行 `temp/stage3/final-checks/source-snapshots.cjs` 的工具输出 |
| Release构建 | CompileArkTS、PackageHap、SignHap通过，交付实际签名HAP。 | `temp/source-home-20261027/build-delivery.log`；[摘要](../artifacts/0.8.4/SHA256SUMS) |

最终HAP为6,469,904字节，SHA256为 `ea153adf8ab5d7d162e9cd92879f2e8927680a31bfbead98abc030685ec7f6ee`。包内版本、API、设备类型与页面快照摘要保存在 `temp/source-home-20261027/delivery.json`；确认版本0.8.4/code15、min60101024、target260000026、Release及phone/tablet。

公开页面于本轮获取并保留在 `temp/source-home-20261027/`：[包子首页](https://www.twmanga.com/)、[分类](https://www.twmanga.com/classify)、[新上架](https://www.twmanga.com/list/new)；[COPY首页](https://www.mangacopy.com/)、[分类](https://www.mangacopy.com/comics)、[新上架](https://www.mangacopy.com/newest)、[排行榜](https://www.mangacopy.com/rank)。COPY组合响应包含题材kehuan、地区0、状态1和热门排序，50条均为完结；两站均保留第二页响应。包子组合筛选的额外在线获取未成功，其组合参数已按真实选项链接检查，尚无对应真实组合响应验收。排行榜其他周期检查覆盖参数构造，未逐个在线获取。

## 安装与待确认项

本轮没有执行设备安装或新首页真机操作。交付包：[0.8.4签名Release](../artifacts/0.8.4/hs-mihon-release-default-signed.hap)。保留原应用数据覆盖安装：

```powershell
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r .\artifacts\0.8.4\hs-mihon-release-default-signed.hap
```

真机集中确认以下操作：

1. 保持可联网的VPN环境，从浏览页打开包子/COPY，核对推荐、热门、更新、新上架。
2. 分类选择题材、地区及完结，确认重置、第二页与空结果；COPY另核对排行榜周期。
3. 加载中快速切换栏目、取消、重新加载，确认旧结果不串栏、已有分页结果保留。
4. 点击首次访问的卡片进入详情，收藏并读一章；返回检查原收藏、已读和阅读位置。
5. 横竖屏及窄窗口确认封面列数、筛选展开、标题与入口可操作。
6. 从首页进入搜索和网站首页，确认返回链路。新首页的原生封面、TLS、布局/旋转和长时内存行为仍以设备结果为准。

若需复核本轮检查与构建：

```powershell
& 'D:\Software\DevEco Studio\tools\node\node.exe' temp/source-home-20261027/check.cjs
& 'D:\Software\DevEco Studio\tools\node\node.exe' temp/source-home-20261027/check-catalog.cjs
.\tools\dev.ps1 -Action Build -Mode release
```
