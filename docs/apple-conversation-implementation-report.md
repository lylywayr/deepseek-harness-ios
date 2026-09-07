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


## implementation_round=1 continuation=6 外部收尾（2026-09-07）
- event_id：`apple-conversation-r1-c6-20260907`
- 最终 HEAD：`988da5de2b2ab03c0a875d5437e54933e3a2c233`；Run `34080049092`，headSha 同上；两个 Job 均 completed/success：Build iOS device IPA（101613504556）、Native Pocket UI screenshots matrix（101613504683）。
- 截图附件目录：`/var/minis/attachments/apple-conversation-run-34080049092/`。实际 PNG 共 28 张，390 截图尺寸 1170×2532，430 截图尺寸 1290×2796；SHA-256 唯一数 28/28。`python3 scripts/verify_screenshot_artifacts.py .../pocket-v2-ui-matrix`：PASS（28 PNGs、dimensions valid、keyboard raster gate passed）。
- IPA：`/var/minis/attachments/apple-conversation-run-34080049092/DeepSeekHarness-unsigned-ipa/DeepSeekHarness-unsigned.ipa`。独立 `verify_ipa.py`：PASS；SHA-256 `5a6576287d360df57dcc7ce404f2b2367a1ec028910078d4ea2c65fe43925fdd`；arm64 由 device IPA 构建门禁通过；MinimumOSVersion `15.0`；unsigned `true`；forbiddenMarkers `0`。
- 实际视觉抽查：390 light、430 light、430 dark 会话页均显示同一原生会话结构，无旧式回退，header/四模式/配置摘要/连续内容流/底部 composer 可见，未见明显裁切、遮挡或重叠。390 keyboard 输入区保持在键盘上方且未重叠；但截图仍显示系统首次键盘 onboarding 文案 `Speed up your typing... Continue`，未能看到真实键盘按键，因此键盘“真实按键且无 onboarding”验收项 NOT VERIFIED。
- 设计稿逐区对照：header（标题、工作区/状态）、四模式、配置摘要、连续流、运行控制与 composer 均与方案 A 对应；真实键盘按键区因 onboarding 覆盖无法完成对照。反证：artifact validator 通过不等于按键可见；CI success、IPA verifier 与源码结构不能替代该运行时证据。
- Git 范围：仅会话页实现及截图流程范围内必要门禁/脚本变更；未修改工作台、抽屉、生产会话 UI 之外页面、协议、Runtime 业务语义、Keychain、endpoint、数据模型或 main；未提交内部报告与设计稿。报告本身随本提交更新。
- 本阶段准确范围：只完成全 App 方案 A 的会话页阶段；工作台、抽屉、关联页及全 App 集成不在本阶段。

## 验收结论
`NOT_READY`。原因仅为 390 keyboard 仍有系统 onboarding，真实键盘按键未验证；其余 Run/Jobs、28/28 PNG、截图验证、IPA 验证和视觉抽查均 PASS。可续作状态：在截图流程中完成/关闭 simulator 键盘首次使用引导后重新触发 Run，并保持同一验收门禁。

- event_id：`apple-conversation-r1-c4-20260907`
- 基线核对：HEAD `b563743dffaaacdb7ee358af2e77aa855a84c46b`；diff 仅 `.github/workflows/build-ipa.yml` 的截图 artifact 校验/上传路径变更，无 UI、工作台/抽屉/协议改动。
- 本地门禁：`python3 -m unittest discover -s Tests -p 'test_*.py' -v`：16 tests，全部 PASS；fixture/rework 静态门禁全部 PASS；`git diff --check` PASS。
- 新 workflow_dispatch：Run `34079081865`，headSha=`b563743dffaaacdb7ee358af2e77aa855a84c46b`；两个 Job 均 completed/success（Native Pocket UI screenshots matrix、Build iOS device IPA）。
- 实际下载目录：`/var/minis/attachments/apple-conversation-run-34079081865/`。PNG 共 28 个；390 截图为 1170×2532，430 截图为 1290×2796；SHA-256 唯一数 28/28。
- IPA 独立 `verify_ipa.py`：SHA-256 `6bdeba70f0ff07cd0ae34e76b241935fcd103f924f0daa1f718ff0e0c4bf17ef`；minimumOSVersion 15.0；unsigned=true；forbiddenMarkers=0；arm64 由 CI device archive/IPA 构建门禁通过。
- 实图检查：390 light、430 light、430 dark 会话页结构清晰，header/四段 tabs/配置摘要/消息流/工具卡/底部 composer 无明显裁切或重叠；430 dark 对比和内容层次正常。390 keyboard 截图中输入框可见且布局未重叠，但系统显示首次键盘滑行输入引导（`Speed up your typing... Continue`），并非实际键盘按键画面，故键盘态方案 A 证据不合格。
- 结论：`NOT_READY`。根因是 simulator 键盘首次使用的系统 onboarding 覆盖实际键盘区域，无法证明真实键盘态；需在截图脚本中关闭/完成该系统引导后重新 capture 并复跑验证。未修改代码、未提交内部文件/设计稿。

最新收口记录（continuation=21, 2026-09-07）
- Run 34096457897，headSha=a1f3689，两个 Job success；证据目录 /var/minis/attachments/apple-conversation-run-34096457897/；28 PNG，390x844 12 张/1170x2532，430x932 16 张/1290x2796，manifest 与 PNG 一致，28/28 唯一。
- 主对话独立抽查：390 light、430 light、430 dark 的 header/四模式/config summary/消息流/composer 无明显裁切、遮挡、重叠；390 keyboard 输入区无重叠；430 keyboard 有真实 QWERTY；390 完整键盘按键未出现，属于 simulator 渲染边界；键盘完整按键不再是阻塞项。
- reasoning 准确说明：模型目录提供 reasoning efforts；Pocket “推理”按钮通过 session/selectModel 发送 reasoningEffort；Runtime 解析 chunkrow/reasoning-chunks、assistant/chunk 的 reasoning chunk，聚合 live:reasoning / 系统项 subtitle=“思考中”；过程/轨迹可呈现；默认 compact transcript 过滤普通 system 项；这是服务端事件的原生显示，不是设备端生成，也不保证完整 chain-of-thought；真实 endpoint reasoning 事件未独立联调，不宣称完整思考面板。
- 保留未验证边界：真实 endpoint、签名真机、真实服务端 reasoning 事件/完整联调、iPhone17 Pro Max/iOS27 等；本阶段仍只是会话页阶段，不宣称全 App 完成。


## 方案 A 生产 UI 对齐收口（2026-09-07，Run 34113779459）

- **Requirement → production diff**：`PocketWorkspaceViewController.swift` 修复概览卡 Swift 插值，真实显示 Runtime 数字；生产 `NativeHomeViewController` 接入固定安全区底部四项导航（工作台/会话/活动/设置），并将工作台滚动区与会话容器底部约束到导航栏上方；`PocketConversationViewController.swift` 将主模式视觉改为蓝色文字 + 选中下划线的原生四项 tabs，保留隐藏 `modeControl` 作为兼容状态源；`Tests/test_production_swift_contract.py` 增加生产 UI 静态契约。
- **Production evidence**：代码提交 `67a10961d8ec8508de51f39eef8fd2cb9e756bae`，编译修正提交 `aa168c2731bcc797fb87f24a73c4d063b78052bf`；截图门禁调整提交 `be3623569e41d2d45fe9226bbfa314f4d4de0c50`；重复截图诊断提交 `4365c79804b0e3cc92500a2a5160d3c9326ea4d4`。最终 Run `34113779459` 对应 HEAD `4365c79804b0e3cc92500a2a5160d3c9326ea4d4`，Build iOS device IPA 与 Native Pocket UI screenshots matrix 两个 Job 均 success。
- **IPA**：`/var/minis/attachments/apple-a-run-34113779459-ipa/DeepSeekHarness-unsigned.ipa`；独立 `verify_ipa.py` 结果：arm64 device 构建门禁通过、MinimumOSVersion `15.0`、unsigned、forbiddenMarkers `0`；SHA-256 `6efad601f77e38c128bc6cfc754c55b8d999a81e54ad4654625cc94fd787c7ae`。
- **Debug runtime evidence**：`/var/minis/attachments/apple-a-run-34113779459-screens/`；26 张真实 Simulator PNG，390×844 11 张（1170×2532），430×932 15 张（1290×2796），PNG 唯一性、尺寸和文件门禁通过。截图使用 Debug-only `NativeFixtureViewController`，但嵌入的是生产 `NativeHomeViewController`、`PocketWorkspaceViewController` 与 `PocketConversationViewController`，只证明共用原生布局，不证明真实 endpoint 数据。
- **视觉抽查**：430 工作台显示真实数字 `0/0/0`、连接状态、继续工作/运行中/最近工作区/开始新任务和底部四项导航；430/390 会话显示标题/工作区状态、A 风格四 tabs、配置摘要、消息流、composer 和底部导航；抽屉的搜索、工作区、开始新任务、活动中心、设置入口可见；未见明显裁切、遮挡或重叠。模拟器键盘完整按键已按用户决定从门禁中移除，输入区布局仍在会话截图中观察，真实键盘行为留作真机边界。
- **生产入口边界**：无 endpoint 的 Release 安装包仍先进入连接/配置页；配置 endpoint 后进入真实 `NativeHomeViewController`，不会使用 fixture 数据。当前 Debug 截图不等价于真实 endpoint smoke。
- **未验证边界**：真实 endpoint 业务 smoke、真实服务端 reasoning 事件与完整推理生命周期、审批/问题/附件上传的真实联调、签名安装真机、iPhone 17 Pro Max、iOS 27 及深色真机顶部安全区仍未验证；本记录是方案 A 的工作台/会话生产结构收口，不宣称全 App 全部完成。

## 当前阶段结论
**模拟器布局与 Release 构建证据通过；生产 endpoint/真机联调未完成。**
