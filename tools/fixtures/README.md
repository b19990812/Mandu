# P0 自有样本服务

仅供开发。正式应用离线运行不需要此 Python 服务。所有故事、标题、HTML、JSON、PNG 都是本项目自有合成数据，按 CC0-1.0 使用，不代表真实漫画源已适配。

启动（Python 3.9+，无第三方依赖）：

```powershell
python -B tools/fixtures/server.py
# 同一局域网的手机连接时：
python -B tools/fixtures/server.py --host 0.0.0.0 --port 8765
# 改版样本：JSON items → results，HTML .comic → .comic-card
python -B tools/fixtures/server.py --revision 2
```

服务默认只绑定环回地址。不自动修改防火墙。手机使用电脑实际可达的 IP，或使用所选 hdc 支持的端口转发；不硬编码 Android 模拟器地址。开发实验室允许明确输入的单一 HTTP origin，正式目标不注册该入口。服务日志写到 `temp/fixtures/requests.jsonl`，只记路径、状态、字节数和虚拟请求头是否存在，不存 Cookie 或查询串。

| 路由 | 固定行为 |
|---|---|
| `/health` | 200，版本和 revision |
| `/probe-file` | UTF-8：`hs-mihon fixture stream` 加换行，24 字节 |
| `/api/search?q=&page=1` | 两部漫画，每批一部；无匹配返回明确空数组 |
| `/api/manga/m1` | 详情；m2 同理 |
| `/api/manga/m1/chapters?page=1` | c1～c3，每批一章；m2 为 c4～c6 |
| `/api/chapter/c1/pages?page=1` | 每章两页，每批一页；c1～c6 都可用 |
| `/search`、`/manga/m1`、`/manga/m1/chapters`、`/chapter/c1` | 同一数据的 HTML，具有 required/empty 标记、实体与懒加载属性 |
| `/images/page-1.png`、`page-2.png` | 自有 320×480 PNG；支持 Range；`?range=off` 关闭续传 |
| `/images/long-1080.png`、`long-2160.png` | 见 images/README.md；按需生成 |
| `/fault/slow?ms=5000` | 延迟响应，供超时与手动取消 |
| `/fault/rate-limit` | 429，Retry-After: 2 |
| `/fault/redirect` | 同域两跳 302 → /health |
| `/fault/cross-host` | 302 到 example.invalid；应在发送下一跳前拒绝 |
| `/fault/loop` | 循环 302 |
| `/fault/expired-image` | 403，明确的 fixture_signature_expired 标识 |
| `/fault/bad-image` | 200 HTML 假图 |
| `/fault/oversize` | 2MiB+1 字节，用于响应限额 |

预期清单：m1/m2；各 3 章；每章 2 页；章节与页序从 0 规范化，pageKey 固定为 `c1-p1` 等，不因签名 URL 变化。JSON/HTML 同一数据集，后续 T08/T09 须经同一个 Source 消费者完成四类操作。当前只提供服务样本，尚未实现规则解析器。
