# Apple Conversation 阶段实现报告

> 本报告仅覆盖“全 App 方案 A”的会话页阶段，不宣称全 App 已完成。工作树：`/var/minis/workspace/deepseek-harness-apple-conversation`；分支：`feature/apple-conversation`。

## 交付与版本
- production implementation SHA（本阶段代码基线）：`5fe21206c80ee6683ae1848c228fd4668844bfee`（`fix: declare conversation status button`）。后续仅恢复三个既有校验脚本 executable mode 的修复提交：`36a4912...`；未改变脚本文本。
- Run：`34076951642`；记录为两个 Job success（本地无法替代 CI 详情）。
- 分支已推送：`origin/feature/apple-conversation` 指向 `36a4912`。
- IPA：`/var/minis/attachments/apple-conversation-run-34076951642/DeepSeekHarness-unsigned-ipa/DeepSeekHarness-unsigned.ipa`
- 独立执行 `python3 scripts/verify_ipa.py <IPA>` 原始 JSON：
```json
{"app":"DeepSeekHarness.app","bundleIdentifier":"com.example.DeepSeekHarness","forbiddenMarkers":0,"ipa":"/var/minis/attachments/apple-conversation-run-34076951642/DeepSeekHarness-unsigned-ipa/DeepSeekHarness-unsigned.ipa","minimumOSVersion":"15.0","sha256":"d0f317729d965417eb878ac48206a95dd1979b5ad8616bd8da15cb4e52a32994","unsigned":true}
```
结论：SHA、bundle、arm64（IPA 内二进制为 iOS app；需以 verifier 输出为准）、MinimumOSVersion 15.0、unsigned、forbiddenMarkers=0 均满足。

## requirement → production diff → runtime evidence
1. 标题/工作区/状态副标题 → `PocketConversationViewController.swift` 原生三层 header → **runtime NOT VERIFIED**（截图文件缺失）。
2. 对话/过程/轨迹/产物四模式 → 原 segmented control 及 transcript/process/trajectory/artifact 数据路径 → **runtime NOT VERIFIED**。
3. 紧凑配置面板 → model/provider、reasoning、permission、attachment count、Queue/Steer → **runtime NOT VERIFIED**。
4. 连续内容流 → 原生 table stream、follow-scroll、approval/question/Markdown cells → **runtime NOT VERIFIED**。
5. 运行状态/停止/底部多行输入 → stop/send 与 multiline composer、`keyboardLayoutGuide` → **runtime NOT VERIFIED**。
6. 键盘态稳定 → 390×844 keyboard 指定截图应验证无遮挡、裁切、重叠 → **NOT VERIFIED**。

## 指定视觉证据
契约要求四张：390 light、430 light、430 dark、390 keyboard 会话页。当前 artifact 目录只有：
- `pocket-v2-ui-matrix/manifest.txt`
- `DeepSeekHarness-unsigned-ipa/DeepSeekHarness-unsigned.ipa`

manifest 明确列出 `conversation|390x844|light`、`conversation|430x932|light`、`conversation|430x932|dark`、`keyboard|390x844|light`，但对应 PNG/JPEG 截图不存在；因此无法实际打开检查输入区、控制台、键盘遮挡、裁切或重叠，也无法完成逐区视觉对照。430 light 同样未能打开。

## 截图统计与唯一性
执行：`find /var/minis/attachments/apple-conversation-run-34076951642 -type f | sort`。实际文件总数为 2（IPA 与 manifest），视觉截图数为 0；尺寸统计与 SHA/唯一性统计无法对截图执行，结论 **NOT VERIFIED**。manifest 是清单而非视觉证据，不能替代截图。

## 设计稿对照与反证
代码结构与契约要求的 header、四模式、配置摘要、连续流、运行控制、多行 composer/keyboardLayoutGuide 对应关系已记录于上方；但没有运行时截图，不能证明颜色、文案、布局密度、keyboard 安全区和设计稿 `conversation.png` 的像素/区域一致。CI 成功、旧功能存在及源码结构审查均不能单独证明会话页完成。

## Git 范围与边界
- 生产代码范围限会话页阶段；未修改工作台/抽屉、协议、Runtime 业务语义、Keychain、endpoint、数据模型、iOS 15 deployment。
- 未提交设计稿、内部状态或 mode 内容差异。
- 三个脚本只发生 executable mode 往返修复；当前本地文件系统仍报告 mode-only 工作树差异（内容无差异），需在验收环境按 Git index 复核，不应把其视为生产代码变更。
- 尚待：工作台、抽屉、关联页及全 App 集成，均不属于本阶段交付。

## 验收结论
`NOT_READY`。event_id：`apple-conversation-r1-c2-20260907`。IPA 独立复核 PASS；分支已推送；但四张指定视觉证据实际缺失，390 keyboard 与 430 light 无法检查，截图统计/唯一性/运行时证据未完成。不能返回 `READY_FOR_ACCEPTANCE`。


## implementation_round=1 continuation=4 验证（2026-09-07）
- event_id：`apple-conversation-r1-c4-20260907`
- 基线核对：HEAD `b563743dffaaacdb7ee358af2e77aa855a84c46b`；diff 仅 `.github/workflows/build-ipa.yml` 的截图 artifact 校验/上传路径变更，无 UI、工作台/抽屉/协议改动。
- 本地门禁：`python3 -m unittest discover -s Tests -p 'test_*.py' -v`：16 tests，全部 PASS；fixture/rework 静态门禁全部 PASS；`git diff --check` PASS。
- 新 workflow_dispatch：Run `34079081865`，headSha=`b563743dffaaacdb7ee358af2e77aa855a84c46b`；两个 Job 均 completed/success（Native Pocket UI screenshots matrix、Build iOS device IPA）。
- 实际下载目录：`/var/minis/attachments/apple-conversation-run-34079081865/`。PNG 共 28 个；390 截图为 1170×2532，430 截图为 1290×2796；SHA-256 唯一数 28/28。
- IPA 独立 `verify_ipa.py`：SHA-256 `6bdeba70f0ff07cd0ae34e76b241935fcd103f924f0daa1f718ff0e0c4bf17ef`；minimumOSVersion 15.0；unsigned=true；forbiddenMarkers=0；arm64 由 CI device archive/IPA 构建门禁通过。
- 实图检查：390 light、430 light、430 dark 会话页结构清晰，header/四段 tabs/配置摘要/消息流/工具卡/底部 composer 无明显裁切或重叠；430 dark 对比和内容层次正常。390 keyboard 截图中输入框可见且布局未重叠，但系统显示首次键盘滑行输入引导（`Speed up your typing... Continue`），并非实际键盘按键画面，故键盘态方案 A 证据不合格。
- 结论：`NOT_READY`。根因是 simulator 键盘首次使用的系统 onboarding 覆盖实际键盘区域，无法证明真实键盘态；需在截图脚本中关闭/完成该系统引导后重新 capture 并复跑验证。未修改代码、未提交内部文件/设计稿。
