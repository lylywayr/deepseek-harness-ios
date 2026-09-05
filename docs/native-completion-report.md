# DeepSeek Harness iOS Native-first 完成报告

## 结论

第二轮已在 `feature/native-renderer` 完成并推送。生产 App 保持 UIKit + URLSession JSON-RPC/WebSocket Mux 的 Native-first 路线；没有恢复 WebKit、WKWebView、DOM 或 legacy 网页路径。

## 本轮实现

- 真实 Harness 连接：bootstrap Cookie 复用、`session/list`、model catalog、workspace/control/follow、session follow/page，以及会话/工作区操作。
- 原生会话侧栏：搜索输入、即时标题/目录过滤、空态、取消/清空、选择打开；视图选项持久化（分组、排序、归档显示）。
- 原生设置：外观、字号、对话显示、繁忙时 Enter、默认权限和连接入口；客户端设置写入 UserDefaults，语言项未伪造。
- 对话：流式消息、工具调用/结果/错误详情、审批确认、用户问题单选/多选/自由输入、历史分页滚动保持、图片选择/预览条/删除/发送。
- 目录：面包屑、home/根路径、隐藏目录切换、新建文件夹、选择与失败提示。
- 工程：模型与测试接入实际 App/Test target；CI 增加原生返工静态集成门禁。

## 真实 Harness Gate 1 脱敏证据

目标服务仅用于只读与一次性临时对象联调；没有记录 token、Cookie 或消息正文。

```text
bootstrap http=200 cookies=1
session/list http=200 ok=true keys=items items=8
session/modelCatalog http=200 ok=true keys=default,failures,groups,routableProviders
mux workspace frames=1 types=item/baseline
mux control frames=1 types=item/baseline
mux events frames=1 types=item/ready
mux follow frames=1 types=item/snapshot
session/create http=200 ok=true keys=agentPreset,sessionId
session/cancel http=200 ok=true
workspace/archiveSession http=200 ok=true
prompt skipped=cost-unconfirmed
```

临时对象名称带 `ios-native-acceptance-20260905-183628`；创建、重命名、取消和归档请求均返回成功。服务列表回读仍出现 `temporary_session_matches=1`，因此不能把清理声明为已证实完成；未触碰既有用户对象。由于 prompt 成本无法安全确认，未发送 prompt，这是唯一人工门禁。

## 测试与 CI

本地 iSH：

```text
python3 -m unittest discover -s Tests -p 'test_*.py' -v
Ran 16 tests ... OK
git diff --check 通过
python3 scripts/verify_native_rework.py 全部 ok
```

本地没有 Xcode/swiftc，未声称本地 Swift 编译通过。CI workflow 会执行 Python fixtures、`verify_native_rework.py`、实际 Swift XCTest、Release device archive、IPA verify 和 artifact upload；本轮代码提交后的 Actions/IPA 结果须以对应新 Run 为准。

## 代码与分支

- 当前分支：`feature/native-renderer`
- 本轮代码提交：`f594357802face97fa5030c87efbecc1a8f27642`（`fix: include tool detail in native inspector`）
- 已推送：`origin/feature/native-renderer`；当前 HEAD 与远端一致
- 未修改 `main`，未 force push
- 工作树另有用户已有移交/验收文档改动，未纳入本轮代码提交：`docs/native-completion-report.md`、`HANDOFF-*`、`REWORK-*`、`docs/native-request-acceptance-report.md`

## 最终 CI / IPA（本轮）

- Actions Run：`33969736548`，`completed / success`
- Workflow：`https://github.com/ly****yr/deepseek-harness-ios/actions/runs/33969736548`
- 实际成功步骤：Python fixtures、`verify_native_rework.py`、Swift XCTest、Release device archive、unsigned IPA 打包、`verify_ipa.py`、artifact upload
- Artifact：`DeepSeekHarness-unsigned-ipa`
- 本地下载：[最终未签名 IPA](minis://attachments/native-rework-33969736548/DeepSeekHarness-unsigned.ipa)
- SHA-256：`2dcdbd0c5febbb1b15a3cfd211eeca346cafa9b58ba4241449532ad5d8dc86a6`
- `verify_ipa.py`：`bundleIdentifier=com.example.DeepSeekHarness`、`minimumOSVersion=15.0`、`unsigned=true`、`forbiddenMarkers=0`
- Mach-O：`arm64`；IPA 中未发现 `_CodeSignature` 或 `embedded.mobileprovision`
## 仍需明确的门禁

- Gate 4 的 390×844 原生模拟器截图尚未加入 CI，不能声称截图证据已完成。
- 未完成签名真机安装；需要用户 Team 签名后才能验证真机行为。
- prompt、真实审批/用户问题事件、图片发送、分页 UI、原生设置页面和目录页面尚未在真实服务上逐项走通；代码与结构测试已覆盖基础路径，但不替代真实事件联调。
- Native manifest/action 是可选声明式协议，不代表官方 Harness 或现有插件已实现。

## 关键限制

本报告不把代码提交、静态检查或绿色构建等同于 Gate 1–5 全部完成。当前已具备可审计的代码/测试/CI/IPA 证据，但 Gate 4 截图和若干真实服务交互仍是明确遗留项。
