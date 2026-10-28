# 0.2.0 解析与章节试读原型

日期：2026-10-25。目标/编译API26，最低兼容6.1.1(24)，保持既有签名与手机/平板声明。用户已确认上一阶段Release真机结果，本阶段独立记录新增能力及证据。

## 交付范围

统一Source包含search/details/chapters/pages/resolveImage，分页标记绑定源版本、操作和对象。JSON保留数字原始字面量，避免大整数ID精度丢失；HTML通过固定htmlparser2回调构树，不执行网页脚本。两种提取器限制2MiB、50000节点、64层；CSS子集支持标签、类、ID、属性、后代/子代，规则只允许有限字段转换。类型不符、缺必填字段、挑战页和明确空结果分别处理。

规则目前是内部ArkTS定义，尚非稳定外部JSON协议，不开放规则导入。DemoRules的两套定义通过相同Source消费流程读取自有数据。T10持久化规则包及更新回滚未实现，因此不宣告G1通过。

包子ChapterPageSource仅实现章节清单和图像请求，尚未实现真实搜索/详情/目录。章节合并按文档顺序去重，拒绝跨章分页、循环、无进展、同标识不同地址和未完成的超限清单；最多100批/2000资源。归档样本4段共175个amp节点，得到163个唯一图像资源，普通img后备节点及推荐封面被排除。资源数不是逻辑漫画页数，尚未完成切块拼接与页序视觉验收。

试读页支持输入包子第一段网址、开章、取消、换图及清缓存后重试。单图先经注入的Transport写入.part、提交本地文件、ImageKit核对尺寸，再由Image(file://)显示；每图2MiB/4194304像素上限，当前会话最多3个已验证文件。尚无长图区域解码、缩放、书架/历史、下载或跨重启续读。异常退出可能留下缓存，后续需全局清理与磁盘预算，不能据此宣告G3/G4完成。

“读取内置示例（合成图）”是独立显式入口。使用自有18个响应和2张640×1024 PNG，经HTML Source及同一缓存/解码器显示；BundledSampleTransport不会访问网络，也不会在真实请求失败时接管。它验证系统文件和图像能力，不能证明RCP真实图片流写已经通过。

## 实际验证

| 层次 | 结果 | 证据 |
|---|---|---|
| 编译 | Debug/lab、Release/default构建与签名成功；Release保持属性/顶层/文件名/导出混淆 | temp/logs/Build-*.log；artifacts/0.2.0/ |
| 核心定向检查 | JSON大ID/坏结构/限额、HTML闭合/实体/选择器、双格式四操作、参数编码/分页绑定、缺字段/挑战页、包子归档清单、分页冲突/预取消通过 | temp/phase2-core-checks.cjs；temp/phase2-core-results.log |
| Debug原生解析 | 实际htmlparser2节点/实体及JSON大整数探针通过 | temp/phase2-device/debug-parser-result.json |
| Debug原生双格式 | 两源各搜索2项、详情、章节3项、图像2项及明确空结果通过 | temp/phase2-device/debug-dual-result.json |
| Release原生示例 | 覆盖安装启动成功；混淆后HTML解析、私有文件提交、PNG解码/显示、1→2换图、重试通过；已查看截图 | release-install.log、release-demo-*-result.json、release-demo-visible.png，均位于temp/phase2-device/ |
| 真实包子 | 设备收到302：www.twmanga.com→cn.dzmanga.com，精确登记后收到403并显示ACCESS_DENIED；未取得原生完整清单或漫画图 | debug-reader-final-result.json、redirect.log |
| PC普通HTTPS | 原用户章节200、50个首段amp图节点；cn.dzmanga.com同路径302回原站。与设备响应不同，不互相替代 | temp/phase2-device/live-source-summary.json |
| COPY | 延续此前根站/指定章普通HTTPS403记录，本轮未重复无关请求 | docs/target-sources.md；temp/chapter-audit-20261025/ |
| 最终产物静态核对 | 版本0.2.0/code2、min60101024、target260000026、compile26.0.0.105；Release不注册实验室；40个源码文件相对导入无缺失/循环、model无SDK导入；持久化及Parser回调未被改名 | temp/phase2-artifact-audit.json |

主机检查执行实际业务源码及固定Parser JS，但URL采用Node替代适配器，不能证明HarmonyOS URL/RCP行为。没有安装测试框架或跑全量套件。真实源403、长图/内存、多格式、数据库重启及后台下载未通过，原因和后续顺序见development-status.md。

## 使用与重跑

签名安装包：artifacts/0.2.0/hs-mihon-release-default-signed.hap；开发实验室包：hs-mihon-debug-lab-signed.hap。SHA256SUMS存放同目录。保留0.1.0历史包，当前开发签名只用于授权设备。

| 文件 | 字节 | SHA-256 |
|---|---:|---|
| hs-mihon-release-default-signed.hap | 371968 | 1ddc021b374023d0069862e78e54fef06ce271824e485936f7cd4153a1ff88d3 |
| hs-mihon-debug-lab-signed.hap | 720319 | 2e89ad3a6c680fb2d049231825c03fee6014e11f75fbd016228362e78c309552 |

```powershell
.\tools\dev.ps1 -Action Install
.\tools\dev.ps1 -Action Build
.\tools\dev.ps1 -Action Build -Mode release
```

设备进入“章节试读→读取内置示例（合成图）”检查显示和换图；Debug实验室的“解析器自检”“本地JSON/HTML双源全链路”无需服务端。主机定向脚本保留期间可用DevEco配套Node重跑temp/phase2-core-checks.cjs；temp可删，不能作为长期测试框架依赖。真实访问失败保持错误，不用样本成功替代。

原始许可证在docs/licenses，随HAP携带THIRD_PARTY_LICENSES.txt；发布包缺源码gitHead与依赖page_show警告如实记录，详见THIRD_PARTY_NOTICES.md。
