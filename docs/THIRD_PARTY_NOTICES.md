# 依赖与素材台账

更新时间：2026-10-26。

- 应用运行时依赖：HarmonyOS 系统 Kit，以及 OHPM 固定版本 `@ohos/htmlparser2@1.0.4` 和工具锁定的传递依赖。锁文件由 OHPM 实际生成，未手写完整性摘要。
- Mihon：参考其主导航、详情及沉浸阅读交互，见[对齐记录](ui-mihon-alignment.md)；ArkUI实现为本项目编写，未复制Mihon源码、Android扩展、图像或商标资源。
- HTML 解析：已接入 `@ohos/htmlparser2@1.0.4` 的流式 Parser 回调，应用自行构建有大小/深度限制的树；不运行站点脚本。
- 项目图标：本项目新建 SVG 几何图形。
- `tools/fixtures/data/catalog.json`、服务返回的 HTML/JSON、`png_image.py` 生成的图片：本项目新建合成素材，声明为 CC0-1.0；不含真实漫画页面。
- DevEco、Node、JBR、Hvigor、OHPM 等开发工具：使用本机已安装工具，不复制到应用包或源码交付。
- temp中的真实站点HTML/静态载荷是只读核查快照，不属于自有CC0素材，不打包进HAP；站点脚本没有在应用中执行。

本文件不授予第三方网站漫画内容的权利，不将开发工具或未安装候选依赖的许可证误记为应用已包含依赖。

## 0.2.0 HTML 依赖审查

| 包 | 实际版本 | 发布包内许可证/声明 |
|---|---|---|
| @ohos/htmlparser2 | 1.0.4 | LICENSE、NOTICE、README.OpenSource；LICENSE 为 MIT |
| @ohos/node-polyfill | 1.0.0 | LICENSE、NOTICE、README.OpenSource；含 MIT 声明以及 OpenHarmony polyfill 0.18.6 的 MulanPSL-2.0 声明，不能统称全部为 MIT |
| entities | 4.5.0 | MIT LICENSE |
| domelementtype | 2.3.0 | BSD-2-Clause LICENSE |
| domhandler | 5.0.3 | BSD-2-Clause LICENSE |
| domutils | 3.2.2 | BSD-2-Clause LICENSE |
| dom-serializer | 2.0.0 | MIT LICENSE |

原始许可证与声明逐份保留在 [licenses/](licenses/manifest.json)，包含版本、锁文件 integrity 和文件索引；相同文本已打包到 `entry/src/main/resources/rawfile/THIRD_PARTY_LICENSES.txt`。README.OpenSource 中列出的组件版本按发布包原文保留，不推定它们都在本应用运行路径中被调用。

官方 OHPM 发布包 [htmlparser2-1.0.4.har](https://ohpm.openharmony.cn/ohpm/@ohos/htmlparser2/-/htmlparser2-1.0.4.har) 为 34041 字节，SHA-256 为 `8b1d9b16341b89608075e971383bfaaf51b1b857ebd709bc10a46aa99e3ba2fd`。发布信息指向 `openharmony_tpc_samples/htmlparser2`，但未提供 gitHead；已固定发布包与 integrity，源码提交与二进制对应关系仍是溯源缺口。

实际构建保留了依赖示例资源 `page_show` 重名提示，没有修改已安装依赖或关闭资源检查。运行入口不引用该示例资源。自有内置双格式样本由 `tools/fixtures/export_samples.py` 从项目样本服务导出，沿用项目合成素材的 CC0-1.0 声明；真实站点快照和漫画图片不打包。
