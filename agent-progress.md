# Agent 进展记录

用于跨会话交接，避免重复摸索。每次会话结束时追加新记录，不覆盖历史。

## 记录模板（复制后填写）

### [YYYY-MM-DD HH:mm] 会话标题
- 会话目标:
- 选择功能: `Fxxx`
- 实际改动:
- 验证结果:
- 风险与遗留:
- 下一步建议:
- 对应提交:

---

### [2026-02-14 17:30] 初始化长任务脚手架
- 会话目标: 建立长任务协作规范与基础脚手架，让新会话可直接按流程推进。
- 选择功能: `F011`（尚未验证，仅建档）
- 实际改动:
  - 新增 `AGENTS.md`（全中文长任务规则）
  - 新增 `init.sh`（启动/停止/状态/smoke）
  - 新增 `feature_list.json`（结构化功能清单，默认 `passes=false`）
  - 新增 `agent-progress.md`（本文件）
- 验证结果:
  - 文件创建完成；
  - 尚未执行完整端到端验证，`feature_list.json` 暂无置为 `true` 的条目。
- 风险与遗留:
  - `init.sh` 的端口与日志路径为默认值，后续可按环境变量覆盖；
  - 各功能项仍需逐条实测后再更新 `passes`。
- 下一步建议:
  - 先执行 `./init.sh`，确认基础 smoke 通过；
  - 然后从 `F001` 或 `F014` 开始做第一轮严格验收。
- 对应提交: （待提交）

---

### [2026-02-14 17:31] 第一轮执行：完成 F011 基础 smoke 验证
- 会话目标: 跑通 `./init.sh`，验证长任务脚手架是否可执行。
- 选择功能: `F011`
- 实际改动:
  - 执行 `./init.sh` 完成启动与 smoke；
  - 更新 `feature_list.json` 中 `F011.passes=true`。
- 验证结果:
  - 服务启动成功：`服务已启动: pid=52595, url=http://127.0.0.1:39028`
  - 冒烟成功：`smoke 通过: http://127.0.0.1:39028`
- 风险与遗留:
  - 在沙箱内会出现端口绑定受限，需在提权环境执行启动测试；
  - 其余 `P0` 功能尚未逐条验收。
- 下一步建议:
  - 下一轮按单功能推进 `F001`（独立健康检查验收）或 `F014`（主流程 e2e）。
- 对应提交: （待提交）

---

### [2026-02-24 09:23] 切换 Flutter 默认后端地址到远端 3026
- 会话目标: 按需求将客户端后端接口地址默认改为 `http://121.43.118.53:3026`。
- 选择功能: `F017`
- 实际改动:
  - 修改 `flutter_client/lib/main.dart` 的 `ApiClient._defaultBaseUrl` 为 `http://121.43.118.53:3026`；
  - 修改后端地址输入框提示示例为 `http://121.43.118.53:3026`；
  - 更新 `README.md` 与 `flutter_client/README.md` 的 Flutter 启动示例地址。
- 验证结果:
  - 执行 `./init.sh`：`服务已启动: pid=89527`，`smoke 通过: http://127.0.0.1:39028`；
  - 执行地址检索校验，确认目标文件已使用 `http://121.43.118.53:3026`。
- 风险与遗留:
  - 尚未在模拟器/真机执行 Flutter 端到端请求验证，`F017.passes` 仍保持 `false`。
- 下一步建议:
  - 在设备上执行 `flutter run --dart-define=CITYLING_BASE_URL=http://121.43.118.53:3026` 并完成一次 `scan` 请求验证。
- 对应提交: `6714b0f`

---

### [2026-02-24 10:11] 修复 Web 端跨域预检失败（scan/image Failed to fetch）
- 会话目标: 修复 Flutter Web 调用远端 `/api/v1/scan/image` 的 `Failed to fetch`。
- 选择功能: `F017`
- 实际改动:
  - 在 `internal/httpapi/router.go` 新增 `withCORS` 中间件；
  - 统一返回 CORS 头：`Access-Control-Allow-Origin/Methods/Headers/Max-Age`；
  - 对 `OPTIONS` 预检请求直接返回 `204`，避免被路由层返回 `405`；
  - 在 `internal/httpapi/router_test.go` 增加 CORS 预检与普通请求头测试。
- 验证结果:
  - 复现远端问题：`curl -i -X OPTIONS http://121.43.118.53:3026/api/v1/scan/image ...` 返回 `405 Method Not Allowed`；
  - 本地测试通过：`go test ./internal/httpapi ./internal/service ./internal/store` 全部通过。
- 风险与遗留:
  - 你当前访问的是远端地址 `121.43.118.53:3026`，需要将本次后端修复部署到远端后，浏览器跨域错误才会消失；
  - `feature_list.json` 中 `F017.passes` 暂不改为 `true`（尚未完成远端 e2e 验证）。
- 下一步建议:
  - 部署本次后端改动到远端后，再执行浏览器端 `scan/image` 路径验证；
  - 部署后可用 `OPTIONS /api/v1/scan/image` 快速确认是否已返回 `204 + CORS`。
- 对应提交: `d90c465`

---

### [2026-02-24 10:41] 优化识别确认弹窗中文显示与滚动体验
- 会话目标: 将“识别结果/识别依据”改为中文展示，并在长内容时支持滚动条。
- 选择功能: `F017`
- 实际改动:
  - 调整 `flutter_client/lib/main.dart`：识别结果显示统一走中文标签；
  - 新增识别依据中文化处理：当后端返回 JSON 理由时，按中文字段格式化显示；
  - 调整确认弹窗内容区域为 `Scrollbar + SingleChildScrollView`，并限制最大高度，避免长文本溢出。
- 验证结果:
  - `./init.sh` 启动与 smoke 通过；
  - `/Users/xuxinghao/develop/flutter/bin/flutter analyze` 无问题。
- 风险与遗留:
  - 尚未在真实设备上完成一次完整识别弹窗交互截图验证；
  - `feature_list.json` 中 `F017.passes` 保持 `false`。
- 下一步建议:
  - 在浏览器端触发一次实际识别，确认长“识别依据”时滚动条可见且中文文案可读。
- 对应提交: `0d03c5e`、`a6762a9`

---

### [2026-02-24 10:48] 新增上传照片测试入口（前端识别）
- 会话目标: 在探索页支持手动上传照片，便于在 Web 端做识别联调测试。
- 选择功能: `F017`
- 实际改动:
  - 在 `flutter_client/lib/main.dart` 增加“上传照片测试”按钮；
  - 新增上传后识别流程：图片读取 -> `/api/v1/scan/image` -> 复用确认弹窗与生成流程；
  - 新增 `image_picker` 依赖，并更新 Flutter 插件生成文件。
- 验证结果:
  - `./init.sh` 启动与 smoke 通过；
  - 在 `flutter_client` 执行 `flutter pub get` 成功；
  - 在 `flutter_client` 执行 `flutter analyze` 无问题。
- 风险与遗留:
  - 尚未在真实浏览器交互中完成一次完整上传识别的端到端截图验证；
  - `feature_list.json` 中 `F017.passes` 仍保持 `false`。
- 下一步建议:
  - 在 Web 页面点击“上传照片测试”，选择图片并确认弹窗内容后完成一次生成流程验证。
- 对应提交: `4c0cc41`

---

### [2026-02-24 10:56] 封装 Web Chrome 启动脚本（默认远程后端）
- 会话目标: 一键启动 Flutter Web + Chrome，后续无需手工逐条执行命令。
- 选择功能: `F018`
- 实际改动:
  - 新增 `scripts/web-chrome-up.sh`，支持 `start|stop|status|restart`；
  - `start/restart` 默认仅构建并启动 Web 静态服务，默认不启动本地后端；
  - 支持环境变量注入 `CITYLING_BASE_URL`、`CITYLING_WEB_PORT`、`CITYLING_WEB_START_BACKEND`。
- 验证结果:
  - `bash -n scripts/web-chrome-up.sh` 通过；
  - `scripts/web-chrome-up.sh status` 输出 `backend: skipped (使用远程后端)`；
  - `scripts/web-chrome-up.sh restart` 成功，返回 `Web 已启动: pid=8964, url=http://127.0.0.1:7357`。
- 风险与遗留:
  - 该脚本以 `flutter build web + python3 -m http.server` 方式运行，定位是联调/测试，不是生产部署；
  - `feature_list.json` 中 `F018.passes` 暂未置为 `true`（尚未对 `scripts/pm2-up.sh` 路径完成验收）。
- 下一步建议:
  - 使用 `scripts/web-chrome-up.sh restart` 作为日常前端联调入口。
- 对应提交: `d544b7b`

---

### [2026-02-24 11:03] 修复 Web Chrome 启动脚本端口占用与状态判定
- 会话目标: 提高 `web-chrome-up.sh` 的稳定性，避免 7357 端口残留占用导致启动误判。
- 选择功能: `F018`
- 实际改动:
  - 在 `scripts/web-chrome-up.sh` 增加端口监听探测（`lsof`）；
  - `stop`/`restart` 增加旧 `http.server` 进程清理逻辑；
  - 启动后补充“新进程存活 + 端口监听”校验；
  - `status` 改为按端口监听状态输出，不依赖旧 pid 文件。
- 验证结果:
  - `bash -n scripts/web-chrome-up.sh` 通过；
  - `scripts/web-chrome-up.sh restart` 可清理占用并完成 Web 启动；
  - 启动后 `curl -I http://127.0.0.1:7357` 返回 `HTTP/1.0 200 OK`。
- 风险与遗留:
  - 在当前执行环境中，后台进程可能被回收，必要时可使用前台常驻方式启动。
- 下一步建议:
  - 若遇到后台进程回收，可直接在终端执行 `cd flutter_client/build/web && python3 -m http.server 7357` 保持常驻。
- 对应提交: `2112b89`

---

### [2026-02-24 11:08] 调整上传照片入口到顶部工具栏（固定可见）
- 会话目标: 解决探索页未明显看到“上传照片”入口的问题。
- 选择功能: `F017`
- 实际改动:
  - 将上传按钮从底部拍照区移动到顶部信息栏，与后端设置按钮并列；
  - 上传入口文案简化为“上传”，避免在小屏上被裁切。
- 验证结果:
  - `flutter analyze` 通过；
  - 重新构建并启动 Web 后，页面可访问（`HTTP/1.0 200 OK`）。
- 风险与遗留:
  - 当前环境下后台进程可能被回收，必要时需前台常驻启动 Web 服务。
- 下一步建议:
  - 刷新页面后检查顶部是否出现“上传”按钮；点击后应弹出系统选图。
- 对应提交: `6be0864`

---

### [2026-02-24 11:23] 修复 scan 错误码回归与脚本误判
- 会话目标: 完成未提交代码审查收敛，修复 `scan` 的 500 回归并降低 `codex-loop` 误判。
- 选择功能: `F012`
- 实际改动:
  - `internal/service/service.go`：新增 `ErrContentGenerate`，在“知识库无数据且 LLM 生成失败”时返回可识别的服务降级错误；
  - `internal/httpapi/handlers.go`：为 `ErrContentGenerate` 增加 `503` 映射，客户端返回固定中文文案，避免透出内部上下文；
  - `internal/httpapi/handlers_test.go`：新增回归测试，覆盖 `scan` 在该错误场景下的状态码与响应文案；
  - `scripts/codex-loop.sh`：移除过宽的 `Not Found` 关键字匹配，减少误报失败。
- 验证结果:
  - `./init.sh`：启动与 smoke 通过（`http://127.0.0.1:39028`）；
  - `go test ./...`：通过；
  - `bash -n scripts/codex-loop.sh`：通过。
- 风险与遗留:
  - 目前仅覆盖本地与单测验证，远端部署后仍建议对 `OPTIONS/POST /api/v1/scan/image` 与未知物体 `scan` 做一次实际联调。
- 下一步建议:
  - 远端发布后执行一次前端上传识别链路回归，确认 4xx/5xx 提示与预期一致。
- 对应提交: （本次提交）

---

### [2026-02-24 11:32] 修复 scan/image 对半截 JSON 的解析失败
- 会话目标: 解决线上 `scanImage internal error ... model output is not valid JSON` 导致的 500。
- 选择功能: `F005`
- 实际改动:
  - `internal/llm/client.go`：在 `parseVisionRecognizeResult` 增加字段级容错提取逻辑；
  - 新增 `extractJSONField`：当模型输出被代码块包裹或 JSON 截断时，仍可提取 `object_type/raw_label/reason`；
  - `internal/llm/client_test.go`：补充“截断 JSON”“缺右花括号 JSON”两类回归测试。
- 验证结果:
  - `go test ./internal/llm ./internal/httpapi ./internal/service` 通过；
  - `go test ./...` 通过。
- 风险与遗留:
  - 若上游模型仅返回自然语言且不含 `object_type` 字段，仍可能进入解析失败分支；
  - `feature_list.json` 的 `F005.passes` 暂不改为 `true`（待远端 e2e 验证）。
- 下一步建议:
  - 远端更新后再做一次上传图片识别，确认 `POST /api/v1/scan/image` 不再返回 500。
- 对应提交: （本次提交）
