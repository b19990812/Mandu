# 漫画柜 HTML 接入修复

日期：2026-10-28（Asia/Hong_Kong）。适用于当前工作区 0.9.10 / versionCode 28；漫画柜原生适配器版本由 1 更新为 2。

漫画柜已改为直接请求网站 HTML。旧第三方 API 搜索在本轮再次返回 HTTP 500、业务码 50016，因此已移除这条依赖及其设置入口。

## 使用

在漫画源管理中启用「漫画柜」。网站根地址默认为 `https://www.manhuagui.com/`，可在「漫画源网站」修改，无需填写 API 地址。首页保留热门、更新、新上架、完结四个栏目，并支持全局搜索、详情、目录及原生阅读。

本轮主机直连网站超时，使用本机已经启用的系统代理后成功取得真实页面和图片。设备使用自己的网络环境；此次未安装设备、未完成真机整章阅读验收。

修复构建：[Release 签名 HAP](../artifacts/0.9.10/hs-mihon-release-default-signed-manhuagui-html.hap)。沿用现有版本号和签名，可覆盖安装；未自动安装设备。

## 实现与兼容

- 搜索请求 `/s/<关键词>_p<页码>.html`，四栏目读取网站对应的 `/list/` 页面。解析 `book-result`、`contList` 和实际分页链接，分页标记绑定网站、操作、版本及设置 revision。
- 详情读取 `book-title`、`detail-list`、`hcover`、`intro-all`。目录读取每个 `chapter-list-*` 分组，将各个倒序 UL 块分别恢复为阅读顺序；公开页面内嵌的压缩目录由同一个有界 LZ-String 解码器读取。
- 章节从 HTML 中静态解包 P.A.C.K.E.R 参数及压缩字典，读取 `SMH.imgData` 的 JSON 数据，再按 `files`、`path`、`sl.e`、`sl.m` 组装签名图片地址。不执行远程 JavaScript，不依赖 WebView 提取正文。
- 固定源 ID `org.hsmihon.manhuagui`、十进制作品 ID、`<mid>/<cid>` 章节 ID 和网页 locator 保持兼容，收藏、阅读进度及已存离线文件不迁移或删除。版本 2 产生新的源快照；旧版本在线下载任务需取消后重新入队。
- 旧设置中的 API 字段被忽略，读取旧配置不会因失效 API 地址而报错。更新漫画柜网站设置时写入现行字段。COPY 的 API 配置保持原有行为。
- 删除 `ManhuaguiApiClient`、`ManhuaguiApiFormat`、`ManhuaguiApiSource`、`ManhuaguiAccess`，并移除 API 专用模型字段、校验、UI、草稿、快照、域名声明和混淆保留项。网络传输恢复使用现有网站会话。

解析职责分为 `ManhuaguiSource`（请求和公共源接口）、`ManhuaguiHtmlFormat`（HTML 列表、详情、目录）、`ManhuaguiReaderData`（章节静态解包和页清单）及 `LzString`（有界解压）。复用既有 Transport、HTML/JSON 解析器、请求取消和 HTTPS 验证。

页面及脚本结构核对参考：[Keiyoushi 漫画柜源](https://github.com/keiyoushi/extensions-source/blob/main/src/zh/manhuagui/src/eu/kanade/tachiyomi/extension/zh/manhuagui/Manhuagui.kt)。实现以本轮下载的实际 HTML 为核验依据，相关代码由本项目独立实现。

## 验证范围

- 11 组最小定向检查通过：真实搜索及空结果、四栏目、第二页、详情、完整目录和分块顺序、54 张图片清单、签名刷新、旧配置兼容，以及错误章节、坏结构、挑战页、403、跳转、取消和旧分页标记拒绝。
- 生产适配器在线请求成功：搜索第一页与第二页各 10 项；《鬼灭之刃》详情及 235 章目录；`/comic/19430/219425.html` 返回 54 张有序图片；第一张图片 HTTP 200、WebP、221638 字节。
- Release `assembleHap`、ArkTS 编译与签名成功。仅检查改动涉及的源与设置，未运行全量测试，也未执行真机整章阅读。

证据位于 `temp/manhuagui-html-20261028/`：`api-before.json`、实际 HTML、`checks.json`、`live-results.json`、`live-6.webp`、`build.log` 和 `delivery.json`。临时文件登记在 `temp/list`。

复核命令（项目根目录）：

```powershell
& 'D:/Software/DevEco Studio/tools/node/node.exe' .\temp\manhuagui-html-20261028\check.cjs
& .\temp\manhuagui-html-20261028\build.ps1
```

这些脚本属于本次任务的临时证据；保留期见 `temp/list`。
