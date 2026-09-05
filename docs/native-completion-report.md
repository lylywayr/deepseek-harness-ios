# DeepSeek Harness iOS Native-first 完成报告

## 结论

第三轮定点修复已在 `feature/native-renderer` 完成并推送。生产 App 保持 UIKit + URLSession JSON-RPC/WebSocket Mux 的 Native-first 路线；没有恢复 WebKit、WKWebView、DOM 或 legacy 网页路径。

## 本轮实现

- 真实 Harness 连接：bootstrap Cookie 复用、`session/list`、model catalog、workspace/control/follow、session follow/page，以及会话/工作区操作。
- 原生会话侧栏：搜索输入、即时标题/目录过滤、空态、取消/清空、选择打开；视图选项持久化（分组、排序、归档显示）。
- 原生设置：外观、字号、对话显示、繁忙时 Enter、默认权限和连接入口；客户端设置写入 UserDefaults，语言项未伪造。
- 对话：流式消息、工具调用/结果/错误详情、审批确认、用户问题单选/多选/自由输入、历史分页滚动保持、图片选择/预览条/删除/发送。
- 目录：面包屑、home/根路径、隐藏目录切换、新建文件夹、选择与失败提示。
- 原生截图夹具：提供 8 个 Native-only 场景，仅由 `-UITestFixture -NativeFixtureScreen <scene>` 启动参数进入，不影响正常生产入口。

## 本轮第三轮定点修复

- 设置接线：对话控制器持有 `AppState`，字号传入消息 Markdown/正文和 Session 日志；`transcriptView` 通过生产展示策略即时过滤过程行；`busyEnter` 计算 queue/steer，并保留 Cmd/Ctrl+Enter 反向语义；新会话创建成功后通过官方 `commands/execute` 权限命令应用 `defaultPermission`。
- 视图选项：`HarnessPresentationPolicy.sections` 按全部 workspace 的 `sessionIDs` 分组，flat 为单列表，未归属会话进入“其他会话”；归档仅作展示过滤，updated/manual 均尊重数据顺序。
- Markdown：补齐行内代码样式、HTTP/HTTPS `.link` attribute；消息使用可选择复制的原生 `UITextView`，仅安全打开 HTTP/HTTPS 链接。
- 截图夹具收尾：入口和实现均置于 `#if DEBUG`；移除会让滚动内容撑满视口并拉伸 arranged subviews 的高度下限；连接场景改为单一垂直内容栈；对话场景的权限控件设置独立宽度；Release IPA 门禁禁止 fixture marker 与真实内网地址；fixture 使用虚构示例地址，最终 8 个场景无纵向拉伸、重叠或裁切。


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

临时对象名称带 `ios-native-acceptance-20260905-183628`；创建、重命名、取消和归档请求均返回成功。服务列表回读仍出现 `temporary_session_matches=1`，因此不能把清理声明为已证实完成；未触碰既有用户对象。由于 prompt 成本无法安全确认，未发送 prompt，这是人工门禁。

## 测试与 CI

本地 iSH（静态/协议辅助测试，Linux 无 Xcode）:

```text
python3 -m unittest discover -s Tests -p 'test_*.py' -v
Ran 16 tests ... OK
git diff --check 通过
python3 scripts/verify_native_rework.py 全部 ok
python3 scripts/verify_native_ui_fixture.py 全部 ok
```

Swift XCTest、Release device archive、IPA gate 和原生截图 job 均由最终 CI 执行成功：Run `33986018201`，对应代码 HEAD `57ac816c172b7ad2f285ffbd6aac0b6d082d04ff`。其中 Swift 协议回归测试通过，包含生产模型的 workspace/flat、归档过滤、Compact 过程显示、busy Enter、Markdown inline code/link 断言及创建权限参数测试。

## 代码与分支

- 当前分支：`feature/native-renderer`
- 最终构建代码提交：`57ac816c172b7ad2f285ffbd6aac0b6d082d04ff`（仅 Debug 截图夹具布局收尾）
- 报告提交位于构建代码之后；报告提交只更新本报告证据，不改变构建代码。最终文档 HEAD 以推送后的提交为准。
- 已推送：`origin/feature/native-renderer`
- 未修改 `main`，未 force push
- 工作树另有用户已有未跟踪移交/验收文档，未纳入本次代码/报告提交：`HANDOFF-*`、`REWORK-*`、`docs/native-request-acceptance-report.md`

## 最终 CI / IPA / 截图证据

- Actions Run：`33986018201`，`completed / success`
- Workflow：https://github.com/lylywayr/deepseek-harness-ios/actions/runs/33986018201
- 成功 jobs：unsigned IPA 构建与 `Native UI screenshots 390x844`；Swift XCTest、Release archive、IPA verify 全部通过。
- 截图目录：[最终 Native UI 390×844 截图](minis://attachments/native-ui-390x844-33986018201/)
- 截图文件：`connection`、`conversation`、`sidebar`、`settings`、`directory`、`approval`、`question`、`trajectory`，共 8 张；PNG 原始尺寸均为 1206×2622（iPhone 16 Simulator，内容区域 390×844pt）。逐张视觉检查确认：夹具卡片/按钮不再纵向拉伸，connection 无文字重叠，conversation 的模型/权限控件无重叠，8 个场景均无裁切或异常遮挡。
- IPA：[最终未签名 IPA](minis://attachments/native-rework-33986018201/DeepSeekHarness-unsigned.ipa)
- IPA 文件大小：304145 bytes
- IPA SHA-256：`4e3bbef3c23b6ed0f10d5af20f3f1adaf0e0a8c5aa67cc92f9297a4a4727cce4`
- 独立 `verify_ipa.py`：`bundleIdentifier=com.example.DeepSeekHarness`、`minimumOSVersion=15.0`、`arm64`、`unsigned=true`、`forbiddenMarkers=0`；扫描禁止 fixture marker 与真实内网地址均未命中。
- IPA 中未发现 `_CodeSignature` 或 `embedded.mobileprovision`。

## 仍需明确的门禁

- 当前 8 张截图是确定性 Native-only fixture 的 Simulator 产物；已检查截图非空白且场景之间存在可见差异，但它不等于所有真实服务数据态都已逐项复现。
- 未完成签名真机安装；需要用户 Team 签名后才能验证真机行为。
- prompt、真实审批/用户问题事件、图片发送、分页 UI、原生设置页面和目录页面尚未在真实服务上逐项走通；代码、模拟器截图和结构测试不替代真实事件联调。
- Native manifest/action 是可选声明式协议，不代表官方 Harness 或现有插件已实现。

## 关键限制

本报告不把代码提交、静态检查、绿色构建或确定性截图夹具等同于 Gate 1–5 全部完成。当前已具备可审计的代码/测试/CI/IPA/Simulator screenshot 证据，但签名真机和若干真实业务事件仍是明确遗留项。
