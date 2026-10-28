# 漫画源域名策略更新

日期：2026-10-28（Asia/Hong_Kong）。用户明确要求去除域名精准匹配限制。本记录替代早期设计中“精确主机清单控制访问”的约束；旧验证记录仍只代表当时版本。

## 当前行为

- `UrlPolicy` 不再要求请求域名存在于 `allowedHosts`。网站、封面、正文图片、分页和允许跳转的请求均可使用新的合规 HTTPS 域名，不自动继承或扩大任何 Cookie。
- 既有构造参数、源包 `allowedHosts` 和原生源主机常量继续作为声明元数据保留，兼容已有规则、持久化数据及调用代码；它们不再构成访问白名单。规则管理页对应显示“声明域名（不限制访问）”。
- 包子章节与 URL 试读移除旧主机及别名比较，继续按选定源解析路径，并使用已配置的根网址请求章节；换站时仍应在自定义网站中设置当前根网址。
- 共享站点客户端与 COPY API 允许响应域名变化，仍校验响应路径。JoyACG 保留画廊路径、页序及完整性校验，封面代理路径不再写死图片域名。
- 扩展目录与内置适配器按既有仓库地址、包名及外部源 ID 关联，站点换域名不再导致关联失败。不会自动覆盖用户的网站设置或自动运行 APK。

## 保留的边界

HTTPS、系统 TLS 证书验证、标准 443 端口、DNS 标签语法、网址长度、无凭据/片段及本地地址规则继续生效。生产请求仍拒绝 IP 字面量、HTTP 和非标准端口；本次不开放站点的 IP:8088 线路，也没有新增 DNS 解析或重绑定防护。

每次重定向仍检查目标 URL、最多五跳并检测循环。Cookie 继续由 `sourceId + origin` 隔离和重新选择；COPY API 专用头仅发往用户配置的 API origin 和 `/api/v3/` 路径，跳到其他域名时不携带这些头。仓库目录原有的禁止跳转策略继续生效。

源 ID、作品/章节身份、路径、页序、数量、刷新键、大小上限、取消与下载原子提交继续使用原有校验。域名放开不等于新网站协议已适配，也不能代替登录或解决服务端拒绝。

## 验证与交付

- 定向主机核验：13 组通过，覆盖未声明域名、HTTPS/地址限制、跨域重定向及流式响应、Cookie 隔离、COPY 专用头、响应路径、规则源、五个仓库关联、章节导入、JoyACG 画廊和栏目筛选。
- 脚本及结果：`temp/domain-policy-20261028/check.cjs`、`checks.json`。复用已有 ArkTS/TypeScript loader，RCP、调度和密钥存储采用内存替身；只使用合成文本和合成字节，无真实源网络或图片请求。
- Release 禁用增量后实际执行 CompileArkTS、PackageHap 和 SignHap，33 个构建任务全部执行，BUILD SUCCESSFUL。相关源码哈希在构建期间及交付归档前保持一致；构建仍有资源重名和 SDK 异常声明等告警，详见构建日志。
- [签名 HAP](../artifacts/0.9.4/domain-policy-20261028/hs-mihon-release-default-signed.hap)：8,002,120 字节，SHA256 `0be90157fabb0079da7f3601138336738144363aaf43947642e0164c1681422c`，另附 [SHA256SUMS](../artifacts/0.9.4/domain-policy-20261028/SHA256SUMS)。包内确认 0.9.4 / versionCode 22、API24 最低兼容、API26 目标及 phone/tablet；本次不调整应用版本号。
- 最终摘要、包内元数据和源码哈希见 `temp/domain-policy-20261028/delivery.json`，实际重新编译日志为 `build-release-fresh.log`。开发期间共享工作区的应用版本由其他改动更新到 0.9.4，本次包按当前工作区源码构建并独立归档，未覆盖其他任务的产物。
- 未执行全量回归、设备安装或真实整章验收。设备访问不同域名后的站点协议和实际网络表现仍需确认。

复核命令：

```powershell
& 'D:/Software/DevEco Studio/tools/node/node.exe' .\temp\domain-policy-20261028\check.cjs
.\tools\dev.ps1 -Action Build -Mode release
```

本次构建采用与 `tools/dev.ps1` 相同的 Hvigor 参数，最终包单独归档在 `artifacts/0.9.4/domain-policy-20261028/`，避免覆盖其他任务的既有交付物。
