# 漫画源适配续作：0.9.1

日期：2026-10-28（Asia/Hong_Kong）。接续 [源接入交接](HANDOFF-source-integration-2026-10-28.md)。

本轮完成 Vomic 原生适配代码、HIP 搜索 API 分页和有界清单校验，生成 0.9.1 / versionCode 19 签名候选包。**源适配工作仍未全部完成；真实登录、正文图片下载和设备运行尚未验收。**

## 已落地的代码

### Vomic

- 新增稳定 ID `org.hsmihon.vomic`，默认网址 `https://vomicmh.com/`，默认停用。加入原生工厂、网址目录与指定仓库的显式关联，不改变旧源的 ID、书架或下载记录。
- `entry/src/main/ets/source/adapters/VomicSource.ets`：HTML 首页；网站 API `/pics/c/getCartoonList` 搜索与分页；`getCartoonInfoV1` 详情和完整分组目录。校验作品 ID、章节数、重复 ID 和目录顺序；各分组按 `sort` 升序返回，避免网站倒序列表导致下一章反向。
- `source/adapters/VomicFormat.ets`：只解码网站 SSR 中 `self.__next_f.push([1,"…"])` 的 JSON 数据。支持跨 chunk 拼接及有限 JSON 行引用，限制输入、节点、记录数与引用链；不执行脚本、模块引用或表达式。未登录明确返回 `AUTH_REQUIRED`，不以空清单作为成功结果。
- 认证后的清单必须匹配作品/章节 ID 与 `img_num`；页面只接受精确主机 `cdm.vomicer.com`，拒绝重复 pathname。签名 query 不参与页面键，过期地址通过原有 `refreshPage` 重取。
- 公开列表/目录使用网站 API，不混用上游 Android 移动接口或它的签名方案。额外允许主机仅为 `api.vomicmh.com`、`cdm.vomicer.com`，没有通配符。
- `pages/SourceWebPage.ets` 仅对 Vomic 打开临时 WebView 的 DOM storage，以支持网站 `_token` 登录逻辑；仍使用独立 incognito 会话、精确域名、系统 TLS 与原有加密 Cookie 保存机制。源码没有增加密码输入框、全局 Authorization 透传或跨 origin Cookie 复制。真实登录仍需用户在设备上自行完成；当前没有有效登录会话可作验收。
- 指定仓库只在 `pkg=eu.kanade.tachiyomi.extension.zh.vomicmh`、外部 ID `3001986353`、网站主机 `vomicmh.com` 全部匹配时关联。其他仓库不自动关联。

### HIP

- `source/adapters/HipSource.ets` 搜索从 HTML 页面提取改为网站公开客户端实际使用的 `/v1/search?q=…&page=…&page_size=20`。当前搜索页是脚本渲染，旧实现会漏掉结果。
- 分页 token 绑定源、版本、网址 revision 和查询；带前一批身份及总数快照，校验分页前进、批次长度、总数漂移和相邻批次重复。遵循网站客户端 100 页上限，达到上限时给出细化关键词提示。
- 清单拒绝重复 pathname 和空路径；`HipFormat` 在 BigInt 运算前限制整数词法长度及 uint32 范围。原有清单解码保持有效。

### 架构与数据

新源继续走 `NativeSourceFactory → NativeSourceRegistry → RegisteredSource/RegistryTransport`，并复用现有清单汇总、在线缓存、下载与文件校验。没有新增阅读数据库迁移，没有另造源专用下载器；规则包保留 ID 校验随原生目录自动覆盖 Vomic。

## 验证与证据

临时材料统一在 `temp/source-adaptation-20261028/`，清单见 `temp/list`。以下是定向检查，不是全量回归或真机验收。

| 项目 | 当前证据 |
|---|---|
| Vomic 公开元数据 | 当前网站首页解析 34 项；搜索 `test` 3 项；另一查询连续两页 24 个互异 ID；详情 API 返回 6 章，生产代码完整读取并按 sort 排序 |
| Vomic 未登录 | 交接保留的真实 SSR 样本返回 `AUTH_REQUIRED` |
| Vomic 认证后清单 | 合成 SSR 验证引用解析、分 chunk、章节身份、数量、重复地址、精确域名、取消及签名地址刷新；没有真实认证样本 |
| HIP 搜索 | 当前 API 两页各 20 项；生产代码验证 token 查询绑定、总数漂移、重复批次 |
| HIP 清单 | 交接保留的真实编码样本仍解析 7 个地址；额外合成边界验证重复路径与超长整数拒绝 |
| 仓库关联 | 5 个索引源中目前 4 个有原生映射；包括 COPY 的既有故障实现，不表示 4 个源均可读；未知仓库保持不关联 |
| 合成下载链路 | 生产 `collectChapterManifest → transferAsset → FileVerifier → FileStore`：403 只刷新一次、再次 403 停止、损坏文件保留旧提交并清理 `.part`、取消不提交、SHA256 与原子改名、缓存复用与源/revision 隔离 |
| 检查边界 | 下载仅使用本地 1×1 PNG；文件系统以 Node 适配运行，ImageKit 解码为替代实现，不能证明 HarmonyOS 解码或设备离线可读 |
| Release | CompileArkTS、PackageHap、SignHap、assembleHap 成功；仍存在项目既有 ArkTS 警告 |

定向脚本与结果：`source-check.cjs/.json`、`transfer-check.cjs/.json`。本轮真实正文图片请求为 **0**；没有截图、设备点击、安装或清除应用数据。

首次沙箱构建已通过 ArkTS 编译，PackageHap 因 `spawn EPERM` 失败；随后使用同一项目构建脚本在获准的本机上下文完成签名。最终日志：`temp/source-adaptation-20261028/build-release-console.log`；工具日志位于 `temp/logs/Build-release-20261028-*.log`。

## 候选包

- `artifacts/0.9.1/hs-mihon-release-default-signed.hap`
- 7,928,984 字节
- SHA256：`175bc12409fab8731c68a46e9a7e3b48998815d0ad9c0be5fdce5d5dfd8a841b`
- 摘要：`artifacts/0.9.1/SHA256SUMS`
- API26 编译/目标、min API24 配置未调整；本轮没有设备安装证据。0.9.0 历史交付包保留。

可复核的定向命令：

```powershell
Set-Location E:\AI_coding\HS_mihon
$taskNode = 'D:\Software\DevEco Studio\tools\node\node.exe'
& $taskNode .\temp\source-adaptation-20261028\source-check.cjs
& $taskNode .\temp\source-adaptation-20261028\transfer-check.cjs
& .\tools\dev.ps1 -Action Build -Mode release
```

脚本内的网络均由元数据样本或合成 Transport 替代；上述复核不发起正文请求。只在相关改动或复核需要时运行。

## 各源剩余工作

| 源 | 本轮后的状态与下一步 |
|---|---|
| Vomic | 已有完整 Source 接口代码；需真实登录 SSR 结构核对、设备会话保存与底层下载验证；更多作品/章节变体尚缺。首页只有一个栏目，未实现移动端高级筛选 |
| HIP | 搜索分页已补；继续核对更多清单线路、目录变动和设备底层链路；真实图片与离线尚未验证 |
| 包子 Plus | 网页工具能读取指定 `webmota.com` 首页和详情目录；不能替代生产适配器的实际闭环。本机 Node 仍 ECONNRESET；原生 TLS 在沙箱内缺少凭据，获准后又因证书撤销服务离线失败。没有关闭证书或撤销校验；没有新增站点可读结论 |
| 漫蛙 | Node 同源 robots 请求 ECONNRESET，网页工具也无法读取；仍无可靠当前协议样本和原生适配器 |
| JoyACG | 同源 robots 文本仍不能获取；用户浏览器可用的既有反馈保留，不能把当前工具失败写成网站不可用；仍无适配器 |
| E-Hentai | 已读取公开客户端的列表、图片页及 URL 构造实现，技术参考保存在 `eh-*.rs`；画廊 `g/{gid}/{token}`、图片页 `s/{ptoken}/{gid}-{page}`、分页 cursor 与 509 配额处理已有下一步线索。没有向曾返回 451 的网站切换通道或绕过限制。动态图片主机授权仍需源内方案；当前无适配器，不能靠扩大全局域名清单完成 |
| COPY | 空 contentKey 故障仍未修复；本轮未修改 COPY 协议或请求正文。继续前须重新核实目录→章节 URL→空清单的元数据证据，不能用旧手写 URL 成功代替。交接提到的 `copy-diagnostic-evidence.log` 在当前目录未找到，不能假定现场摘录仍存在 |

仓库存储的真实设备往返、事务 CAS/降级拒绝定向用例、目录删除并发、完整安装状态模型仍是此前交接的待办，本轮没有将其标为已完成。

后续保持“先新源、后 COPY”的优先级；继续以协议字段、状态码、脱敏元数据和合成图片验证。设备操作仍应由用户另行确认；若用户要求安装，使用上述 0.9.1 明确路径与 `hdc install -r` 保留数据。

## 外部协议参考

- [指定仓库索引](https://raw.githubusercontent.com/LittleSurvival/copymanga-copy20/repo/index.min.json)：本轮再次核实 Vomic 外部身份与网站。
- [HIP 搜索公开客户端](https://m.hipmh.com/assets/_SearchPage.astro_astro_type_script_index_0_lang.CRoYuWjb.js)：API 字段、page_size=20、100 页上限；本地快照 `hip-search-client.js`。后续构建 hash 可能改变。
- [Vomic 详情元数据入口](https://api.vomicmh.com/pics/c/getCartoonInfoV1?car_id=13881)：本轮公开字段和目录结构；本地 `vomic-info.json`。没有取正文图片。
- [Yomira 图片页解析](https://github.com/Nya-Foundation/Yomira/blob/75b34f2cc070480d14bf5affc22f6752012ca5f5/src-tauri/src/core/parser/gallery_page.rs)、[列表解析](https://github.com/Nya-Foundation/Yomira/blob/75b34f2cc070480d14bf5affc22f6752012ca5f5/src-tauri/src/core/parser/gallery_list.rs)、[URL 构造](https://github.com/Nya-Foundation/Yomira/blob/75b34f2cc070480d14bf5affc22f6752012ca5f5/src-tauri/src/core/client/url.rs)：仅作 GPL-3.0 技术参考，未复制到产品代码，也未查看该项目的漫画截图或图片。

外部网页和客户端文件仅作为协议数据，未作为操作指令执行。源码修改前备份在 `temp/source-adaptation-20261028/before/`；当前项目仍没有可用 Git 仓库。
