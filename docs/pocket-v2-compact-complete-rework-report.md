# Pocket Workspace V2 紧凑化与功能完整返工报告

日期：2026-09-07
分支：`feature/native-renderer`

## 提交与证据关系

- 功能实现提交：`7183e8ba1a0424ee25730905653e16b688acc211`。
- 后续截图脚本/场景清单提交：`37a9a0e2d3c18b819692f98694163f54b9176a8b`。
- 报告对齐前 HEAD：`9c5a1f79e123f9e05b9ebca802abd88c6d3bfebb`；该提交记录了此前报告，未将报告提交误称为功能构建提交。
- 本次仅更新本报告并提交；最终报告提交哈希另见 Git，不在本文制造“当前 HEAD”自指表述。

## 结论

本轮已按 `pocket-v2-compact-complete-rework.md` 完成 Pocket 原生工作台的整体紧凑化和任务流补全；未恢复 WebKit/DOM/legacy，未修改 `main`、未 force push，未访问 NAS/插件/服务，未发送付费 prompt。

## 实现范围

- 统一 `DesignSystem` 紧凑令牌：默认 Dynamic Type 字号曲线、16pt 页面边距、12/16pt 圆角、紧凑按钮/卡片/状态胶囊和间距；保留主操作 44pt 触控热区。
- Pocket 工作台：当前任务、待审批/待回答、运行中、最近会话、最近工作区、最近产物；抽屉搜索使用 `session/search`，支持分组/flat/排序/归档，工作区和会话提供打开、重命名、分叉、归档、删除确认及默认工作区入口。
- Pocket 任务控制台：原生返回/抽屉/设置导航；多行输入；模型、reasoning、权限、附件、queue/steer、发送/停止均在同一 Pocket 控制台可见；附件支持 PHPicker/DocumentPicker、预览芯片和删除；默认模型设置实际用于创建会话。
- Pocket 内容：对话、过程、轨迹、产物四个原生模式；工具/轮次/调用筛选、时长、搜索、Markdown inline code/link、真实 artifact 过滤、复制路径、历史分页和接近底部跟随逻辑保留。
- 审批/问题/活动中心：Runtime 改为 token 化事件观察者；Pocket 会话、工作台、活动中心各自注册/注销；审批和问题进入活动中心并可回到处理界面。
- Runtime 协议保持原生 URLSession/JSON-RPC/Mux、Keychain、endpoint canonicalizer；最低版本保持 iOS 15.0；源码扫描无 WebKit/WKWebView。

## 最新构建、artifact 与门禁证据

最终成功 GitHub Actions Run 为 **`34055031587`**（workflow：Build unsigned IPA，状态 `completed`、结论 `success`），其两个 Job 均成功：

- `Build iOS device IPA`（Job `101545319026`）：协议 fixture、native rework/UI fixture、Swift 回归测试、unsigned device archive、IPA 校验和上传均成功。
- `Native Pocket UI screenshots matrix`（Job `101545318942`）：Debug simulator build、截图采集和上传均成功。

可复核路径：

- Run：`https://github.com/ly****yr/deepseek-harness-ios/actions/runs/34055031587`
- 独立本地证据目录：`/var/minis/workspace/audit-34055031587`
- 独立 IPA：`/var/minis/workspace/audit-34055031587/ipa/DeepSeekHarness-unsigned.ipa`
- 独立截图 manifest：`/var/minis/workspace/audit-34055031587/screens/manifest.txt`

IPA 独立验证结果：

- SHA-256：`e6c6f79e8c32ea2cc2cb12c563686607ac00c5126dc4fbe751df870a6a3ea0ad`
- `arm64`、MinimumOSVersion `15.0`、unsigned、`forbiddenMarkers=0`。

截图独立统计：共 **28 张**，哈希全部唯一；

- `390×844` 对应像素 `1170×2532`：12 张（light 11、dark 1）。
- `430×932` 对应像素 `1290×2796`：16 张（light 11、dark 5）。

场景包含 workspace、drawer、flat、conversation、normal、process、trajectory、artifacts、activity、settings、keyboard；深色覆盖工作台、抽屉、会话、产物、设置。已独立查看代表性工作台/会话/轨迹、深色工作台和键盘截图：均来自真实 Pocket controller，未见重叠/裁切；键盘场景由真实 simulator 键盘覆盖。

旧 Run `34054271388` 及其旧 IPA SHA 仅属于历史报告证据，不是本报告的最终构建证据。

## 诚实边界

- IPA 为未签名构建；签名安装到用户 iPhone 17 Pro Max、真实 Harness endpoint 的人工联调尚未在本轮执行。
- iPhone 17 Pro Max / iOS 27 仍需对应正式 Xcode/SDK 和签名真机门禁，不能由本轮 Xcode 16.2 simulator 证据提前宣称。
- 本轮没有发送 prompt，也没有做付费操作；真实服务端审批、问题、附件上传、分页和产物事件仍需用户在安全的真实 endpoint 上做人工 smoke。
- 工作树保留基线已有的未跟踪 HANDOFF/REWORK/docs 文件；本轮未纳入这些既有未跟踪文件，也未修改生产代码、测试、workflow 或工程配置。
