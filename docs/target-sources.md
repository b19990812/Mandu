# 首批真实源登记

> 2026-10-28 更新：[域名策略](source-domain-policy-2026-10-28.md) 已移除精确主机匹配，原 CDN 清单仅作声明。下方设备及网站证据仍只代表原记录时点。

更新：2026-10-26。用户指定包子和COPY，实际章节域名为twmanga.com和mangacopy.com。早期展示站baozimanhua-vip.com.cn、kbmh.com.cn不足以提供漫画四操作，不作为当前适配目标。

| 项目 | 包子漫画 | COPY漫画 |
|---|---|---|
| 固定SourceId | org.hsmihon.baozi | org.hsmihon.copy |
| 默认根地址 | https://www.twmanga.com/ | https://www.mangacopy.com/ |
| 当前实现 | BaoziSource及BaoziChapterSource | CopySource及CopyFormat |
| 搜索/目录快照 | 搜索25项，目标目录287章 | 搜索12项，目标目录233章（含附加分组） |
| 指定章清单快照 | 4段去重163资源 | 17资源 |
| 原生已观察限制 | 早先302到cn.dzmanga.com后403；新四操作适配器尚未真机跑完整 | 真实搜索发生SDK1007900035 TLS握手失败；TLS1.2兼容重试仍失败 |
| 当前判断 | 适配代码与快照通过，G2未通过 | 适配代码与快照通过，G2未通过 |

## 样本和公开格式

包子：[用户指定章节](https://www.twmanga.com/comic/chapter/silingfashiwojishitianzai-mantudezhuyuanzhuheiniaoshe_rjogsq/0_286.html)，目标《死靈法師！我即是天災》。搜索短标识与详情canonical后缀不同，适配器只接受页面明确声明、与原标识对应的六位后缀映射，不允许跨漫画任意改身份；最新章节与完整目录的重复项合并。图片从amp-img.comic-contain__item提取，不混入封面/推荐图。

COPY：[用户指定章节](https://www.mangacopy.com/comic/naoodngxueshenghui/chapter/50fea5ac-c587-11ec-8361-024352452ce0)，目标《腦洞學生會》。2026-10-26 PC匿名HTTPS已取到搜索、详情、目录与章节正文，旧403记录保留为历史，不能再断言PC始终403。公开网页向匿名浏览器同时提供编码清单和固定格式字面量；适配器只解析字面量并用系统标准AES128/CBC/PKCS7读取JSON，不执行下载的脚本，不处理验证码、付费或DRM绕过。完整目录为主分组220章加其他分组，共233个唯一章节。

生产适配器对已保存页面快照的核查结果见 `temp/stage3/final-checks/source-results.log`，页面快照在 `temp/source-audit-20261026/`，包子章节分段在 `temp/chapter-audit-20261025/`。主机检查采用宿主URL及标准加密替代实现，不能证明SDK加密、原生TLS或漫画图可读。

## 域名与自定义网址

包子页面默认精确允许twmanga.com/cn.dzmanga.com重定向对，封面static-tw.baozimh.com，图片s1.bzcdn.net。COPY当前已观察图片/封面主机为sn/sc/sz/sj/sd/sl.mangafunb.fun，逐个登记，没有放行整个任意后缀。新增CDN需要核查适配。

“更多→漫画源网站”可独立修改各源根地址、恢复默认、切回上次。固定ID不随网址改变；快照键随根地址改变，旧请求失效，旧下载不静默迁移到新版本。完整离线阅读不依赖在线源开关。试读也经统一Registry检查禁用状态，不再绕过内置源管理。

用户自定义根域名不会自动继承旧页面域名或任意CDN权限。仅适用于同结构迁移，保存网址不代表验证可用；结构改变需更新规则/适配器。见[配置契约](source-site-settings.md)。

## 仍需验收

每源至少3章的真机完整读取、实际页序和图片视觉对照、重启恢复。PC200与快照解析不替代设备网络；不关闭系统证书验证、不降级HTTP、不自动替换用户网址，也不把合成图当真实源成功。0.4.0续作时用户已解锁，随后要求降低真机验证频率、优先完整功能开发；本轮未重复真实站点设备请求，旧网络错误仍未定位解决。


2026-10-26修正：书架《绍宋》原生复现s2.bzcdn.net被拒绝。现BAOZI_IMAGE_HOSTS精确登记s1.bzcdn.net和s2.bzcdn.net，适配器与传输策略共用；不放开其他bzcdn子域名。补充后第一章42张清单及真实图片已显示，非所有章节/双源验收。
