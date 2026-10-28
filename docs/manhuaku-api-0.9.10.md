# 0.9.10 漫画库混合 API 接入及接口获取记录

日期：2026-10-28（Asia/Hong_Kong）。版本：0.9.10 / versionCode 28。用户确认采用“目录与线路 JSON API + 原生 HTTP 页面数据解析”。这不是全部操作都返回 JSON 的接口，也不是第三方代理服务。

## 交付与启用

已新增固定源 `org.hsmihon.manhuaku`，名称“漫画库”，默认网站 `https://www.manhuaku.com.cn/`。网站和数据接口使用同一根地址，无需单独填写 API 域名。现有源、漫蛙移除和漫画柜适配保持原状。

1. 「扩展仓库 → 新增网站适配状态 → 漫画库 → 启用本项目适配器」，或通过原有源管理启用。与其他新增源一致，默认不启用。
2. 返回浏览页打开漫画库，提供分类、更新、完结三个栏目；分类可组合地区、题材和连载状态。启用后也参与全局搜索。
3. 「更多 → 自定义网站（漫画源网站）→ 漫画库」可修改同协议站点根地址；地址变化沿用现有 revision、快照和在途请求取消机制，不改写书架及阅读身份。

[签名安装包](../artifacts/0.9.10/manhuaku-20261028/hs-mihon-release-default-signed.hap)，摘要见 [SHA256SUMS](../artifacts/0.9.10/manhuaku-20261028/SHA256SUMS)，版本/API/源码哈希及验证摘要见 [delivery.json](../artifacts/0.9.10/manhuaku-20261028/delivery.json)。最终包包含当前共享工作区的既有改动；构建前后生产源码及构建规则哈希一致，并独立归档避免其他构建覆盖。本轮未安装设备、未提交或上传仓库。

## 我如何获取接口信息

### 1. 从用户给定站点读取公开首页和真实作品链接

直接以标准 HTTPS 读取[首页](https://www.manhuaku.com.cn/)，得到搜索表单的 `action=/search`、`method=get`、关键词字段 `query`，以及分类 `/categories`、更新 `/updates`、真实详情 `/comic/<id>.html` 等链接。

随后读取搜索、分类和更新页，确认每页条目、`page` 参数、地区 `category`、题材 `tag`、状态 `status` 以及分页输入框 `value/max`。本轮读到的普通列表每页24项，搜索样本一页16项；实现以真实分页标记判断下一页，不把16或24当作所有页面的恒定数量。

入口快照在 `temp/manhuaku-20261028/probe-0.json`、`lists-0/1/2.json`；第二页、完结、空搜索、组合筛选在 `extra-0/1/2/4.json`。搜索词用于公开漫画检索，没有读取账户、书架或用户历史。

### 2. 从详情页的公开前端代码确认完整目录 API

读取[作品556详情](https://www.manhuaku.com.cn/comic/556.html)。页面初始只列出最近12章，却显示总计66章，并提供“加载全部章节”。该按钮的公开代码明确调用：

```javascript
fetch('/comic/' + contentId, { method: 'POST' })
```

因此请求实际的 `POST https://www.manhuaku.com.cn/comic/556`，不带请求体，得到 HTTP 200 / application/json，成功码为 `code=0`，完整章节数组为 `data.chapters`，共66项。

同一页面的 `renderChapters` 在默认倒序展示时调用 `items.reverse()`，切换正序时保留 API 数组顺序。因此阅读顺序使用 API 原数组，不能根据 `chapterNum` 排序，也不按标题数字或数据库 id 猜测章序。

详情页证据 `assets-1.json`，目录真实响应 `json-0.json`。JSON 接口的 GET 方式实际返回404；`/comic/556.html` 的 GET 才是详情页。这两个 URL 和 HTTP 方法不能混用。

### 3. 从阅读页确认图片数据模板和线路 API

读取[第66话](https://www.manhuaku.com.cn/chapter/556-150527.html)，发现声明数据：

- `contentId='556'`、`chapterId='150527'`：正文所属作品/章节。
- `totalPages=parseInt('12')`：本章12页。
- `imgBaseUrl`：`https://image1.manhuaku.com.cn/mh/<作品目录>/` 加 `chapterPath`，空路径才回退章节名称，再加 `/`。
- 图片循环：页码从1到 `totalPages`，文件名为 `<页码>.webp`。
- `.source-line-picker` 的 `data-source-id='1'` 和 `data-source-base`：站点内部图片源和初始域名。

再读取详情页引用的[站点线路脚本](https://www.manhuaku.com.cn/resource/js/source-lines.js?v=5)，发现其明确请求 `GET /api/source-lines/<data-source-id>`。实际请求[图片源1线路清单](https://www.manhuaku.com.cn/api/source-lines/1)，得到 HTTP200 / `code=0`，数据位于 `data.lines`。

本轮返回：

| id | 名称 | URL | enabled | isDefault | lazyLoad | sort |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 主线路 | `https://image1.manhuaku.com.cn` | true | true | false | 0 |
| 3 | 备用1 | `https://us2.manhuaku.com.cn` | true | false | true | 1 |
| 2 | 备用2 | `https://us1.manhuaku.com.cn` | true | false | false | 2 |

应用选择启用的默认线路；没有默认标记时使用启用列表的第一项，与公开前端规则相同。本轮只下载默认线路的一张图片，未测试两个备用域名的图片字节，也没有新增应用内测速、切线或自动故障回退。`lazyLoad` 是站点网页的提示，原生阅读器继续使用自身缓存/预取机制。

阅读页证据 `reader-0.json`、首章 `extra-3.json`，脚本 `reader-1.json`，线路 JSON `lists-3.json`。

### 4. 用实际响应交叉验证，不只记录看起来合理的 URL

API 中 `chapterNum` 分别为首章14、最新章12；阅读页 `totalPages` 与其一致。`chapterPath` 也与阅读页的目录名一致，canonical、页面 `contentId/chapterId` 和 API `contentId/id` 对应。

生产源类在 Node HTTPS 环境实际完成：搜索 → 详情 → 完整目录 → 首章及最新章页清单 → 获取最新章第一张图片。首图请求为：

```text
https://image1.manhuaku.com.cn/mh/ba3f57939593455d8f41b27fc189c7f2/3929aa9c-c6ff-4f75-912a-d9dadff59231/1.webp
```

实际 HTTP200、`Content-Type: image/webp`、238362字节；RIFF/WEBP标识及容器声明长度与文件长度一致。SHA256 `37e0a9e9bc0e6cc9f0fe67e8aded62d417405d380c3cf3be639ac6453141949b`。

这一地址是本轮样本，生产代码根据每章真实数据生成，不写死该作品或章节。脚本/API响应可能更新，日期和样本不能视为永久可用保证。

### 5. 明确没有确认的接口

没有发现覆盖搜索、详情和正文的统一公开 JSON API。按已知路由尝试 POST首页、POST搜索、POST无 `.html` 阅读地址均返回404，未用于实现。没有假设存在 `/api/v1/search`、`/api/v3/comics` 等路径；COPY 的字段、签名和平台头没有套用到此站。

公开页面中出现的登录、收藏、历史保存、统计和广告脚本不属于本轮连接目标，未执行或调用。应用不运行远程 JS，也不以 WebView 承载正文。

## 请求信息总表

以下路径均相对于当前配置的 `https://www.manhuaku.com.cn/`。

| 用途 | 方法 | 路径及参数 | 响应形式 | 关键读取内容 |
| --- | --- | --- | --- | --- |
| 搜索 | GET | `/search?query=<URL编码关键词>&page=<页码>` | HTML | `.catalog a.book`、h3、封面、pager |
| 分类 | GET | `/categories?page=<页码>`，可加 `category/tag/status` | HTML | 地区/题材/状态选项和作品卡片 |
| 更新 | GET | `/updates?page=<页码>` | HTML | `.update-timeline .timeline`、作品、时间 |
| 完结 | GET | `/categories?status=2&page=<页码>` | HTML | 同分类，固定完结状态 |
| 详情 | GET | `/comic/<作品ID>.html` | HTML | canonical、标题、作者、简介、题材、状态、封面、总章数 |
| 完整目录 | POST，无请求体 | `/comic/<作品ID>` | JSON | `code=0`、`data.chapters` |
| 阅读数据 | GET | `/chapter/<作品ID>-<章节ID>.html` | HTML及固定字面量 | 身份、`totalPages`、`imgBaseUrl`、图片源ID |
| 图片线路 | GET | `/api/source-lines/<图片源ID>` | JSON | `code=0`、`data.lines` |
| 正文图片 | GET | 线路根地址 + `/mh/<作品目录>/<章节目录>/<1开始页码>.webp` | WebP | 正文字节、容器、后续原生尺寸及摘要校验 |

本轮请求使用标准 HTTPS、User-Agent、Accept 与站点 Referer；API请求的 Accept 为 application/json。没有携带账号Cookie、Authorization或token，未发现必须的请求签名或图片解密步骤。此处说明的是已成功使用的请求方式，不宣称每一个请求头都不可省略。

## 接入一个源需要获取的全部信息，以及本站对应项

| 信息类别 | 需要确认什么 | 本站已确认信息及用途 |
| --- | --- | --- |
| 入口与协议 | 网站/API根地址、端口、TLS、方法 | 同一网站根；HTTPS443；多数GET，完整目录仅POST |
| 路由与参数 | 每个功能的精确路径、大小写、编码、请求体 | 上表；query需URL编码；page从1开始；目录POST无请求体 |
| 响应封装 | HTTP状态、Content-Type、业务成功码、data结构 | JSON成功码0，目录chapters数组、线路lines数组；其余HTML |
| 源和作品身份 | 应用固定SourceId、作品ID、可校验网页地址 | `org.hsmihon.manhuaku`，mid十进制字符串，`/comic/<mid>.html` |
| 搜索与分页 | 卡片身份/标题/封面、空结果、页码、总页数 | 卡片链接+标题+CSS封面；pager-input value/max；实测空搜索与第二页 |
| 分类 | 筛选名、合法值、组合方式 | category地区、tag题材、status状态；1连载/2完结；选项从页面读取 |
| 详情 | 标题、作者、简介、题材、状态、封面、总章数 | comic-profile及og:description、chapterCount、canonical；简介保留站点元描述内容 |
| 目录 | 数组位置、作品归属、章节ID/名称/顺序、完整数量 | id、contentId、chapterName；数组顺序正序；与网页总数及可见章节交叉校验 |
| 目录附加字段 | 字段语义和是否参与身份 | chapterNum为图片数；chapterPath为图片目录；createdAt/updatedAt为时间信息，不作为章序或本地身份 |
| 图片清单 | 章身份、数量、路径、扩展名、页码起点 | 页面身份 + API chapterNum/path；WebP；页码从1开始 |
| CDN与线路 | CDN根地址、默认/启用规则、是否签名/过期 | lines的id/name/url/enabled/isDefault/sort/lazyLoad；按当前默认线路；未观察到签名query |
| 认证和请求头 | 登录、Cookie、token、签名、Referer/UA | 已验证匿名公开读取；设置为匿名Transport；图片带站点Referer |
| 字符串/编码 | UTF-8、HTML实体、URL编码、脚本数据提取 | HTML解析解实体；ID按字符串保留；图片只读取固定表达式中的字符串字面量，不eval |
| 刷新与一致性 | 过期重取、稳定页面标识、换站版本 | pageKey为pathname；按键刷新，缺页即CONTENT_CHANGED；设置revision变化取消旧请求 |
| 异常与限额 | 空清单、重复、错书、分页不推进、响应上限 | 2MiB元数据、10000章、2000图；校验身份/总数/重复；源站拒绝按现有错误流程处理 |
| 图片实际可用性 | 正文字节、格式、尺寸、完整性、原生解码 | 已取一张完整WebP；HarmonyOS ImageKit实际解码与全章仍待设备确认 |
| 可复查证据 | 采集日期、请求/响应、脚本、样本、失败结果 | temp任务目录与list；原始发现快照、生产请求记录、9组检查及签名构建 |

这些信息不能相互替代：能打开网站不代表目录完整，目录返回JSON不代表正文可用，一张图片成功也不代表全章、换章和离线恢复已经验收。

## 实现与验证边界

- `ManhuakuClient.ets` 负责API读取及JSON封装校验，复用 `SiteJsonClient` 读取HTML；`ManhuakuFormat.ets` 负责列表/身份/目录/线路与图片数据；`ManhuakuSource.ets` 实现公开源接口及栏目。
- 共享 `RequestPlan` 增加可选 `method`，默认仍为GET。`ReadPostPolicy.ets` 只允许 `org.hsmihon.manhuaku` 的 `/comic/<十进制ID>` 无请求体metadata POST，禁止query、图片流式POST、其他方法及POST重定向；不开放登录、历史写入或其他站点任意POST。RCP仍使用系统证书验证、原调度和大小/取消限制。
- 9组定向主机检查通过：真实HTML/JSON快照、筛选分页、66章完整性、首/末章页数、刷新、异常与受限POST。SDK网络用替身，因此不能当作设备RCP证据。没有全量回归。
- 另一次生产源真实Node HTTPS核验通过：10次元数据请求和1张正文图；见 `live-result.json`、`live-1.json` 至 `live-10.json`。底层不是HarmonyOS RCP，不能证明设备TLS、UI或ImageKit。
- Release CompileArkTS、PackageHap、SignHap与BUILD SUCCESSFUL；包内0.9.10/code28、API24最低/API26目标、phone/tablet。既有资源及SDK异常声明告警保留。
- 初次构建的CompileArkTS和SignHap有实际执行记录；收尾源码一致性构建使用Hvigor增量缓存。对应日志分别为 `build-release.log` 和 `build-release-final.log`，最终生产源码/规则哈希在 `source-before.json`、`source-after.json`，独立归档时再次比对源码未改变。
- 未安装设备，未做真实全章图片下载、换章、缓存压力、备用线路、UI及重启离线验收。本次只做与核心协议和HTTP方法改动直接相关的最小验证。

```powershell
& 'D:/Software/DevEco Studio/tools/node/node.exe' .\temp\manhuaku-20261028\check.cjs
& 'D:/Software/DevEco Studio/tools/node/node.exe' .\temp\manhuaku-20261028\live.cjs
.\tools\dev.ps1 -Action Build -Mode release

# 用户设备确认时保留数据覆盖安装
& 'D:\Software\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' install -r .\artifacts\0.9.10\manhuaku-20261028\hs-mihon-release-default-signed.hap
```

后续设备确认按搜索 → 详情 → 66章正序目录 → 首章/最新章 → 首图/整章页序 → 换章 → 下载/重启离线进行。现场看到新模板、图片类型或API封装时，应先更新协议证据和解析器，不猜测新地址或静默混用其他源。
