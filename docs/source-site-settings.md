# 漫画源自定义网址

> 2026-10-28 更新：[域名策略](source-domain-policy-2026-10-28.md) 已移除精确主机匹配；下文旧主机清单描述属于历史实现。HTTPS、443、地址格式、会话隔离和既有源解析要求继续适用。

2026-10-25 用户要求为漫画源增加自定义网站功能，以便网站地址失效后调整。当前按“现有源的根网址可替换”实现；不是仅输入任意网站就自动获得漫画解析能力。

## 可操作内容

首页“更多→漫画源网站”，分别对包子漫画和COPY漫画执行：

1. 修改网址：填入新的 HTTPS 根网址并保存。
2. 恢复默认：恢复到当前以用户实际章节域名确认的地址（包子twmanga.com，COPY mangacopy.com）。早先展示/下载页地址不再作为默认值。
3. 切回上次网址：当前记录存在上一次地址时可用。每次成功更换会保留一个上次地址；再次切换会将刚离开的地址作为上次地址。
4. 重新读取：重新读取本地设置，失败时保留当前列表和输入。

没有网络自动跳转、备用域名自动发现或下载执行脚本。保存只写入配置，不把连接、解析、下载标成成功。

## 边界与依赖

设置调用：`SourcesPage → SourceSitesVM → AppContainer → SourceSiteService → SourceSiteSettingsStore`。Preferences适配器位于storage，设置服务只依赖模型内存储接口。0.3.0正式和试读均经统一SourceRegistry及受控Transport，源禁用同样适用；实验室单独组装，正式目标不注册实验室页。

源身份分别固定为 `org.hsmihon.baozi`、`org.hsmihon.copy`，不由网址生成。0.3.0已实现漫画、章节、收藏、进度和离线仓库；修改网址不改写这些记录，固定源快照与浏览缓存身份随网址revision改变，旧在途请求失效。

`SourceSiteService.access(sourceId)`返回当前baseUrl、单一根域名allowedHosts和revision副本。内置适配器每次开章固定读取快照，原用户章节路径映射到当前根网址，迁移不产生新SourceId。默认twmanga.com/cn.dzmanga.com精确302对由适配器登记，自定义根网址不继承旧页面权限，图片CDN独立登记。真实设备限制见[目标源登记](target-sources.md)。

替换地址只适用于解析规则兼容的迁移。站点路径、DOM、JSON或图片解码变化仍需更新规则/适配器。旧绝对locator的规范化和刷新由后续适配器处理，不批量改写历史数据。图片CDN需单独核查，不因输入根网址而自动获得跨域权限。

本轮没有登录凭据或Cookie存储。后续会话模块接入时，origin变更必须使旧会话失效，不能把旧站凭据复制到自定义域名；这属于T03b/T43的接入条件，不能从“源ID保持不变”推导出凭据可以迁移。

## 校验与存储契约

- 只接受标准443端口的HTTPS公网域名根网址，去掉输入两端空白并规范化大小写和默认端口。
- 拒绝凭据、查询参数、片段、子路径、控制字符、反斜杠、IP字面量、localhost和无效域名；沿用现有 UrlPolicy。
- 此处校验URL语法和域名清单，不代表已防住DNS重绑定，也不代表网站可以读取。保存不会触发请求。
- Preferences 名称为 `source_site_settings`，单键 `source_sites_v1` 保存带 schemaVersion=1、全局revision和分源revision的JSON快照，不保存Cookie、密码或图片URL。
- 写入使用旧revision检查；陈旧页面或快照冲突会拒绝保存并提示重新读取。读到坏JSON、重复ID或未来schema时拒绝操作，保留原数据。
- 只有flush成功才显示保存成功。flush失败会尝试恢复上一快照，且不会覆盖期间出现的较新写入；真实落盘、异常及重启行为仍需设备验证。
- `schemaVersion/revision/sites/sourceId/baseUrl/previousBaseUrl/updatedAt` 在混淆规则中显式保留，避免Debug/Release和后续升级更改JSON字段名。

## 验证与待验

API26 Debug 与开启混淆的 Release 已构建。针对持久化格式和域名安全变化，执行8组最小主机逻辑核验：默认值、只更换当前源、旧版本拒绝、恢复/切回、非法网址、重新打开替代存储、flush失败、坏数据/未来版本保护。核验运行项目实际 service/repository，URL和Preferences使用主机替代适配器；结果见 `temp/logs/source-site-settings-smoke.json`，不等同于鸿蒙运行验证。未安装新测试框架、未跑全量回归。

设备核验仍待补：保存包子新地址→退出重开→确认COPY未变→切回/恢复默认并重开；非法地址应拒绝且旧设置保留。本轮已在签名Debug/Release覆盖安装后只读到两项默认值，没有修改用户网址，不能据此声称编辑与重启矩阵通过。
