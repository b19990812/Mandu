# 0.9.9 移除漫蛙与漫画柜 API 接入

> 历史记录：当前漫画柜已改为直接解析 HTML，本文中的 API 代码和设置入口已移除。请使用[HTML 接入说明与修复包](manhuagui-html.md)。下文保留 0.9.9 当时的实现、故障及验证范围。

日期：2026-10-28（Asia/Hong_Kong）。版本：0.9.9 / versionCode 27。

已移除漫蛙内置源、扩展目录中的漫蛙启用入口、适配器和专用流式图片解码器，新增漫画柜 JSON API 适配。当前第三方公共 API 的业务请求存在上游故障，**本轮没有证明漫画柜真实搜索或阅读可用**。

## 使用方式

1. 「更多 → 自定义网站（漫画源网站）→ 漫画柜 → 修改网址」：网站根地址默认 `https://www.manhuagui.com/`，API 根地址默认 `https://api-manhuagui.aoihosizora.top/`。API 输入只填 HTTPS 根网址，适配器自动拼接 `/v1`，不要把漫画网站当作 JSON API。
2. 如有兼容 Aoi-hosizora/manhuagui_api v1 的可用服务，在上述位置替换 API 根地址；保存设置只表示配置已落入存储，不代表网络验证成功。
3. 在「扩展仓库 → 新增网站适配状态 → 漫画柜」启用本项目适配器，或在原有源管理中启用。与其他新增源一致，默认不启用。启用后浏览页可打开漫画柜首页，也参与全局搜索。
4. API 失败会明确提示第三方服务无法获取上游内容，不会自动切回网页解析或其他漫画源。

API 是[第三方开源服务](https://github.com/Aoi-hosizora/manhuagui_api)，不是已确认的漫画柜官方 API。实现依据为本轮读取的服务 Swagger v1.0.1、仓库的搜索/漫画控制器及 DTO/目录顺序定义，不运行远程 JavaScript，也不依赖 WebView 提取正文。

## 请求与数据契约

| 功能 | v1 路径 |
| --- | --- |
| 搜索 | `/search?keyword=<编码关键词>&page=<页码>&order=popular` |
| 热门 | `/manga?order=popular&page=<页码>` |
| 更新 | `/list/updated_v2?need_total=true&page=<页码>` |
| 新上架 | `/list/published_v2?need_total=true&page=<页码>` |
| 完结 | `/category/genre/all?status=wanjie&order=popular&page=<页码>` |
| 详情与完整分组目录 | `/manga/<mid>` |
| 章节图片清单 | `/manga/<mid>/<cid>` |

响应要求 `code=200` 和对象 `data`。列表按 `page/limit/total/data` 校验分页位置、数量与重复项，支持该后端无搜索结果时的 `limit=0`。分页标记绑定源版本、网站、API 地址、设置 revision 和当前操作。

漫画柜固定源 ID 为 `org.hsmihon.manhuagui`，作品 ID 使用十进制 mid 字符串，章节 ID 使用 `<mid>/<cid>`。网页 locator 保持 `/comic/<mid>/` 与 `/comic/<mid>/<cid>.html`。目录保持服务端分组顺序，组内按数值 `number` 升序，校验连续序号、重复章节、所属作品与分组；最多100组、10000章，失败不返回部分目录。

正文使用 `pages` 字符串数组，校验 `mid/cid/url/page_count`、重复页面及2000页上限。稳定页面标识使用图片 pathname，保留源站完整 HTTPS URL 与签名参数；刷新时按页面标识查找，页面消失即返回 CONTENT_CHANGED。图片经过现有流式下载、容器/尺寸/摘要校验、缓存和原子提交，不引入新的图片解码器。

## 模块及兼容边界

- `ManhuaguiApiClient` 负责有界 JSON GET、HTTP/业务状态和响应路径；`ManhuaguiApiFormat` 负责身份、目录顺序和页清单；`ManhuaguiApiSource` 负责公开源接口与四个首页栏目。工厂及原生注册表沿用现有版本和请求取消机制。
- 网站设置增加可选 `manhuaguiApiBaseUrl`，沿用 schemaVersion 1；设置服务、持久化校验和 UI 支持读取、保存、恢复默认及冲突检查。新字段加入 Release 混淆保留规则。API 地址改变生成新源快照，旧请求及旧下载快照不能继续使用。
- 漫画柜 Transport 使用匿名模式，不读取网页 Cookie，也不携带 COPY 专用请求头。继续使用系统 TLS 验证、现有 HTTPS 公网地址规则和已放开的域名策略；域名声明仅为元数据，不恢复旧精确域名限制。
- 漫蛙历史网站设置、收藏、进度、已存离线文件不删除，也不映射到漫画柜；两站作品身份不能推断等价。移除后的漫蛙在线请求与续载不再支持，旧在线任务可在下载管理中取消。旧版本文档和临时证据保留为历史记录。

## 本轮验证

- 公共 API Swagger：HTTP 200，版本 v1.0.1；服务公告接口 HTTP 200 / `code=200`。这仅证明服务及文档可访问。
- 依照 Swagger 参数请求搜索、详情和更新，含 `allow_cache=true`：HTTP 500，业务码分别为50016、50002、50010，错误为上游漫画网站获取失败。直连 `www.manhuagui.com` 首页与搜索在本机超时。不能通过修改客户端请求字段解决外部服务的上游故障。
- 10组定向主机协议检查通过，包含本轮捕获的真实500响应。成功清单来自按 Swagger 和后端实现构造的合成样本，不能当作真实漫画成功证据。另5组普通图片下载检查通过，覆盖容器/摘要、原子提交、截断、刷新、取消及已移除编码拒绝；仅使用合成PNG，ImageKit使用替身。
- Release `CompileArkTS`、`PackageHap`、`SignHap` 和 `BUILD SUCCESSFUL` 通过。包内版本0.9.9/code27，最低API24、目标API26、手机/平板。保留现有资源及SDK异常声明警告。
- 未运行全量回归；本轮涉及源核心逻辑、可选持久化字段和下载解码分支删除，只运行相关最小检查。未做设备安装、UI确认、真实首图/全章/换章/下载/重启离线验收；真实业务接口失败时无法完成这些验收。

证据：`temp/manhuagui-20261028/` 下的 `swagger.json`、`probe-result.json`、`probe-api-result.json`、`probe-cache-result.json`、`checks.json`、`transfer-check.json`、构建日志及 `delivery.json`。临时清单在 `temp/list`。

## 交付与复核

[0.9.9 Release signed HAP](../artifacts/0.9.9/hs-mihon-release-default-signed.hap)，摘要见 [SHA256SUMS](../artifacts/0.9.9/SHA256SUMS)。本次仅生成签名包，未安装设备、提交或上传仓库。

```powershell
& 'D:/Software/DevEco Studio/tools/node/node.exe' .\temp\manhuagui-20261028\check.cjs
& 'D:/Software/DevEco Studio/tools/node/node.exe' .\temp\manhuagui-20261028\transfer-check.cjs
.\tools\dev.ps1 -Action Build -Mode release

# 用户确认设备时保留数据覆盖安装
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r .\artifacts\0.9.9\hs-mihon-release-default-signed.hap
```

待有可用的兼容 API 服务后，集中确认：搜索 → 详情 → 完整目录及分组顺序 → 正文首图/全章 → 换章 → 下载及重启离线；再确认 API 地址切换取消旧请求与持久化恢复。
