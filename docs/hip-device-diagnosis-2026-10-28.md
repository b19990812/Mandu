# HIP 真机阅读故障诊断（2026-10-28）

> 后续已交付 [0.9.6 修复](hip-api-fix-0.9.6.md)：正文清单直接使用公开 API，三个原失败章节在真机显示成功。下文保留修复前的诊断时点与证据。

本轮已定位到当前阅读失败的阻断点：`reader.hipmh.top` 返回 Cloudflare challenge，HTTP 403。尚未复现此前描述的“图片容器解码失败”，不能将这两类错误视为同一根因，也未宣称故障已修复。

## 真机与复现范围

- 已安装版本：0.9.5 / versionCode 23，API24 compatible / API26 target。
- 界面确认来源：`org.hsmihon.hipmh`。
- HIP 首页可加载 47 部作品。
- 《我独自升级 : 诸神黄昏》的“预热”“第1话”，以及《登录武林系统》的“第1话 祝您武运昌隆”，进入原生阅读界面均显示 `ACCESS_DENIED：站点拒绝访问（403）`。
- 本轮使用 HDC `uitest` 操作真实平板；没有用宿主替代接口作为设备证据。

## 请求证据

为定位阶段，临时签名包仅增加 HIP 请求阶段、主机、HTTP 状态、长度和格式日志；另对同一阅读页执行一次仅改变 User-Agent 的对照。没有记录 Cookie、Authorization、章节路径或查询参数。

2026-10-28 14:14 的设备日志显示：

```text
stage=reader-html host=reader.hipmh.top status=403 bytes=5537 type=text/html; charset=UTF-8
reader403 title=Just a moment... challenge=challenge server=cloudflare
reader-browser-ua status=403 bytes=5708 type=text/html; charset=UTF-8
```

这里 `challenge` 取自响应头 `cf-mitigated`。单独改为浏览器 User-Agent 仍然返回 403，因此“仅替换 UA 即可修复”不成立。现有证据没有区分验证 Cookie、请求特征和网络条件各自的贡献。

失败链路为：

```text
点击章节 → HipSource.pages() → 请求阅读 HTML → Cloudflare 403 → requireHttpSuccess() 抛出 ACCESS_DENIED
```

这次重放没有进入 `/v2/chapter` 图片清单请求，也没有进入正文 CDN 下载、FileVerifier 或 ImageKit 解码。因此不能据此认定 HIP 缺少图片 AES 解密、清单解码错误、图片格式不兼容或缓存预算不足。

应用内 WebView 能打开 HIP 首页和作品详情；网页章节链接的跳转未形成有效阅读页对照，不作为“浏览器能正常阅读”的证据。

## 结论与未完成项

当前可确定的是阅读域名的 Cloudflare 验证阻断了原生 HTTP 请求。原生适配器读取 HTML 时不能完成浏览器挑战流程。后续需先核对阅读域名在正常浏览器中的验证与会话兼容，再重放同一章节；只有取得实际图片响应后，才能继续确认原始“容器解码失败”的原因。

本次没有实施正式协议修复，没有完成真实图片或整章阅读验收，没有运行全量回归。

## 恢复与证据位置

- 临时诊断涉及 `RcpTransport.ets`、`image/FileVerifier.ets`。两文件已按修改前 SHA256 精确恢复。
- 真机已通过 `hdc install -r` 恢复原始 0.9.5 签名包；安装、启动、进程与书架两部作品均已核对，没有清除应用数据。
- 原包 SHA256：`3d7fde32cfba7da794aedca41ff9ecb1e47e358dc5ef044342e4d73f62d20cbf`。
- 请求日志：`temp/hip-device-20261028/final-device-requests.txt`。
- 错误截图：`temp/hip-device-20261028/hip-error.png`。
- UI 文本、诊断包、源码备份及恢复记录均在 `temp/hip-device-20261028/`，用途和保留规则见 `temp/list`。
- `app-log-first.txt` 包含 hilog 参数互斥错误，不是应用故障证据。
