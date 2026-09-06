# Pocket Workspace V2 紧凑化与功能完整返工报告

日期：2026-09-06
分支：`feature/native-renderer`
最终功能提交：`7183e8ba1a0424ee25730905653e16b688acc211`（其后截图脚本证据提交 `37a9a0e2d3c18b819692f98694163f54b9176a8b`）

## 结论

本轮已按 `pocket-v2-compact-complete-rework.md` 完成 Pocket 原生工作台的整体紧凑化和任务流补全；未恢复 WebKit/DOM/legacy，未修改 `main`、未 force push，未访问 NAS/插件/服务，未发送付费 prompt。

## 实现范围

- 统一 `DesignSystem` 紧凑令牌：默认 Dynamic Type 字号曲线、16pt 页面边距、12/16pt 圆角、紧凑按钮/卡片/状态胶囊和间距；保留主操作 44pt 触控热区。
- Pocket 工作台：当前任务、待审批/待回答、运行中、最近会话、最近工作区、最近产物；抽屉搜索使用 `session/search`，支持分组/flat/排序/归档，工作区和会话提供打开、重命名、分叉、归档、删除确认及默认工作区入口。
- Pocket 任务控制台：原生返回/抽屉/设置导航；多行输入；模型、reasoning、权限、附件、queue/steer、发送/停止均在同一 Pocket 控制台可见；附件支持 PHPicker/DocumentPicker、预览芯片和删除；默认模型设置实际用于创建会话。
- Pocket 内容：对话、过程、轨迹、产物四个原生模式；工具/轮次/调用筛选、时长、搜索、Markdown inline code/link、真实 artifact 过滤、复制路径、历史分页和接近底部跟随逻辑保留。
- 审批/问题/活动中心：Runtime 改为 token 化事件观察者；Pocket 会话、工作台、活动中心各自注册/注销；审批和问题进入活动中心并可回到处理界面。
- Runtime 协议保持原生 URLSession/JSON-RPC/Mux、Keychain、endpoint canonicalizer；最低版本保持 iOS 15.0；源码扫描无 WebKit/WKWebView。

## 测试与门禁

- Python：`python3 -m unittest discover -s Tests -p 'test_*.py' -v` —— 16 项通过。
- Python 原生/协议门禁：`verify_native_rework.py`、`verify_native_ui_fixture.py` 通过；新增 Pocket 事件观察者、轨迹/任务能力测试。
- GitHub Actions Run `34054271388`：两个 Job 均成功。
  - Build iOS device IPA：Swift XCTest、Release device archive、IPA gate、artifact upload 全成功。
  - Native Pocket UI screenshots matrix：Debug simulator build、截图采集、artifact upload 全成功。
- IPA：`/var/minis/attachments/pocket-run-34054271388/ipa/DeepSeekHarness-unsigned.ipa`
  - SHA-256：`fa438b33c86629b9be9df63740795d7a982905a2dec2323d03b5d28e55b6d88d`
  - `arm64`、`iOS 15.0`、unsigned、`forbiddenMarkers=0`。
- 截图：`/var/minis/attachments/pocket-run-34054271388/ui/`
  - 390×844 light：11 张 Pocket 原生场景，全部 1170×2532。
  - 430×932 light：11 张 Pocket 原生场景，全部 1290×2796。
  - 390×844 dark：workspace，1170×2532。
  - 430×932 dark：workspace/drawer/conversation/artifacts/settings，全部 1290×2796。
  - 总计 28 张 PNG，28 个 SHA-256 均唯一。
  - 场景包含 workspace、drawer、flat、conversation、normal、process、trajectory、artifacts、activity、settings、keyboard；深色覆盖工作台、抽屉、会话、产物、设置。
  - 已独立查看 390 工作台/会话/轨迹、430 深色工作台和键盘截图：均来自真实 Pocket controller，未见重叠/裁切；键盘场景由真实 simulator 键盘覆盖。

## 诚实边界

- IPA 为未签名构建；签名安装到用户 iPhone 17 Pro Max、真实 Harness endpoint 的人工联调尚未在本轮执行。
- iPhone 17 Pro Max / iOS 27 仍需对应正式 Xcode/SDK 和签名真机门禁，不能由本轮 Xcode 16.2 simulator 证据提前宣称。
- 本轮没有发送 prompt，也没有做付费操作；真实服务端审批、问题、附件上传、分页和产物事件仍需用户在安全的真实 endpoint 上做人工 smoke。
- 工作树保留基线已有的未跟踪 HANDOFF/REWORK/docs 文件；本轮代码和测试修改已提交并推送，未纳入这些既有未跟踪文件。
