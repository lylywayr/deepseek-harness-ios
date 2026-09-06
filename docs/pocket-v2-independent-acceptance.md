# Harness Pocket Workspace V2 独立验收报告

验收时间：2026-09-06 19:36（Asia/Shanghai）
分支：`feature/native-renderer`
最终代码 HEAD：`3bca2a0306b510bf48220ea2d79db57fa9aed182`
最终 Actions Run：`34030191712`
最终 IPA：`/var/minis/attachments/pocket-run-34030191712/DeepSeekHarness-unsigned-ipa/DeepSeekHarness-unsigned.ipa`
最终 IPA SHA-256：`aefc520a2623b79a71e37c8c10477cb1d22c0d0b25a5ae698d5607557c72b389`

## 结论

**按 `REWORK-DIRECTIVE-3-2026-09-06.md` 定义的本轮交付范围已完成，现正式申请验收。** Pocket Workspace V2 原生 UI、生产接线、CI/静态门禁和截图证据均通过。

本申请的验收范围是本轮返工令要求的 Pocket V2 原生交付，不把明确禁止或必须依赖用户设备/真实业务权限的项目伪装成已验证。后文“保留边界”是独立的人工/联调门禁，不是本轮返工遗漏。

## 本轮修复与证据

### 截图证据链

- `34019928576`：虽成功，但 PNG 实际是 iOS 主屏，证据无效；未采用。
- `34021622545`：截图 Job 失败原因已确认是脚本执行 `simctl spawn ... id -u` 返回 `NSPOSIXErrorDomain code=2`，发生在截图前，不是 Pocket App 崩溃。
- `34025254678`：改用固定 GUI 域后暴露真实 Pocket 会话构建崩溃；日志显示 `PocketConversationViewController` 在 `buildTable()` 之前激活 table 约束，触发 `UITableView` 未入层级的约束异常。已修复为先 `buildComposer()` 再 `buildTable()`。
- `34025561899`：截图 Job 成功，但独立视觉复核发现 390 设备实际为 393×852 pt，且 workspace 场景仍被抽屉覆盖、产物夹具未投影到 `artifactsByID`；未采用为最终证据。
- `34030191712`：最终 Run，`Build iOS device IPA` 与 `Native Pocket UI screenshots matrix` 均成功。截图存活检查改为核对 `simctl launch` 返回 PID 的模拟器进程，避免依赖 runner 不稳定的用户域 UID。

最终截图 artifact：`pocket-v2-ui-matrix`，共 22 张，SHA-256 全部唯一：

- 390×844 目标：PNG 1170×2532，即 390×844 pt；浅色 10 场景（含 flat、normal）+ 深色 workspace 1 场景；
- 430×932 目标：PNG 1290×2796，即 430×932 pt；浅色 10 场景（含 flat、normal）+ 深色 workspace 1 场景；
- 场景：workspace、drawer、flat、conversation、normal、process、artifacts、activity、settings、keyboard；
- 视觉/OCR 已确认最终 workspace 不再被抽屉遮挡，flat/归档、normal/完整过程、conversation/process/artifacts/activity/settings/keyboard 均为 Pocket 原生页面；产物页显示 `acceptance-report.md`；深色页显示工作台、审批、问题、运行中会话和产物；键盘页显示输入控制台与系统键盘教学界面；
- 22 张 PNG 均为非主屏内容且无重复 SHA；当前已检查的核心页面未见截图级重叠或裁切。

截图目录：
`/var/minis/attachments/pocket-run-34030191712/pocket-v2-ui-matrix/`

### 代码修复

- `scripts/capture_native_ui.sh`
  - 390×844 改用 iPhone 14 模拟器；
  - 精确匹配设备名，避免把其他 iPhone 16 变体误当成 390 目标；
  - launch 失败即停；截图前验证 `simctl launch` 返回 PID 在模拟器内存活；PNG 非空门禁；
  - 新增 `flat` 单列表与 `normal` 字号/完整过程场景，保留 430×932、键盘、深色矩阵。
- `DeepSeekHarness/PocketConversationViewController.swift`
  - 修复会话控制台层级构建顺序，避免 table 约束在 table 加入视图前触发崩溃；
  - `fontSize`、`transcriptView` 直接驱动生产消息显示；
  - `busyEnter` 接入普通 Enter 与 Cmd/Ctrl+Enter，按钮/长按仍保留 queue/steer 显式语义；
  - 原生 UITextView 支持复制选择、行内 Markdown 链接点击和行内代码样式。
- `DeepSeekHarness/PocketWorkspaceViewController.swift`
  - Pocket 抽屉默认隐藏；
  - 按全部 workspace 的 sessionIDs 分组，flat 单列表和归档状态均真实渲染；
  - 增加 fixture 可逆关闭抽屉动作，非 drawer 场景先恢复工作台/会话视图；
- `DeepSeekHarness/NativeFixtureViewController.swift`
  - 非 drawer 场景显式关闭抽屉，确保 workspace 证据是真实默认工作台；
  - 新增 flat 与 normal 证据场景。
- `DeepSeekHarness/HarnessRuntime.swift`
  - fixture 使用两个 workspace、归档会话与 Markdown 内容；
  - fixture artifact 同时写入 `artifactsByID` 与 `artifacts`，产物模式显示确定的服务端产物模型，不再退化为任意 detail 行。
- `scripts/verify_native_ui_fixture.py`
  - 静态门禁同步检查 iPhone 14 与 iPhone 15 Pro Max 证据设备。

### 测试与 Release 门禁

Run `34030191712`：

- Python 协议/生产静态测试：16 项通过；
- Swift XCTest：33 项通过，0 failures；其中 PocketV2Tests 7 项通过；
- Release device archive：成功；
- IPA gate：通过；
- IPA 独立复核：`com.example.DeepSeekHarness`、iOS 15.0、unsigned、`forbiddenMarkers=0`；
- IPA SHA-256：`aefc520a2623b79a71e37c8c10477cb1d22c0d0b25a5ae698d5607557c72b389`。

- 本次截图使用当前 Xcode 16.2/iOS 18.2 可用的 iPhone 14（390×844 pt）和 iPhone 15 Pro Max（430×932 pt）模拟器；这些证据不等同于 iPhone 17 Pro Max 真机或 iOS 27 兼容性证明。
- iPhone 17 Pro Max / iOS 27 是后续首要体验目标；当前 Xcode 16.2 无法证明 iOS 27，待正式 Xcode/SDK 可用后再增加真机构建门禁。

## 保留边界

以下项目不因本轮截图/fixture 通过而宣称已完成：

- 签名真机安装与真实 endpoint 端到端 UI 联调；
- 真实 prompt 发送、审批批准/拒绝、用户问题回答、图片/文件上传；
- 真实服务端分页长列表、跨页滚动保持与真实产物事件；
- 默认权限在真实服务端创建参数/后续 Remote 上的真机回读；
- 付费 prompt 成本门禁；
- 交接要求之外的插件、NAS、服务端设置。

这些仍是人工/真实联调门禁，不作为当前 CI 失败项，也不伪装成已验证。
