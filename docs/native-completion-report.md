# DeepSeek Harness iOS · Harness Pocket Workspace V2 完成报告

## 结论

已在 `feature/native-renderer` 接管并完成 Harness Pocket Workspace 的第一阶段原生 UI/UX 重构。生产路径保持 UIKit、URLSession JSON-RPC、URLSessionWebSocketTask Remote Mux 与共用 `HarnessEndpointCanonicalizer`；没有恢复 WebKit、DOM、legacy 页面路径，也没有修改 `main`、force push、SSH/NAS、插件或服务配置，没有发送付费 prompt。

本轮交付的是原生可编译、可运行、可审计版本；真实 Runtime 不支持的内容没有用演示数据冒充。产物模式仅消费 Runtime 已确认的 artifact/file/attachment 事件；没有扩展成工作区全量文件管理器。

## 实现范围

| 设计规格能力 | 实现/证据 | 状态 |
|---|---|---|
| 自适应 Harness 工作台 | `NativeHomeViewController`：继续工作、连接状态、待处理、运行中、最近工作、最近工作区、新任务；按 Runtime 状态显隐 | 已实现 |
| 层级上下文抽屉 | 约 88% 屏宽覆盖抽屉；主机状态、搜索、工作区→会话层级、归档/视图选项、添加工作区；边缘手势和 VoiceOver 按钮 | 已实现 |
| 对话/过程/产物 | `PocketConversationViewController` 三段原生 Segment；对话/工具过程过滤；产物只显示 Runtime 确认事件 | 已实现，真实产物事件需服务端联调 |
| 任务控制台 | 多行输入、发送/停止、运行状态、当前阶段、上下文目录；使用 `keyboardLayoutGuide` 保持键盘态可达 | 已实现；附件入口沿用既有真实 PHPicker/文档 picker 接线 |
| 模型/权限/附件 | 既有会话控制器保持真实 model catalog、权限和图片/文件 picker；Pocket 会话页接入 Runtime；默认权限持久化 | 已实现/沿用，需真实逐项联调 |
| 审批 | Runtime 解析待审批队列；按风险显示高风险/普通；单次结果写回 `$events/result`；高风险全屏、普通 Sheet | 已实现，真实事件未发送 |
| 用户问题 | Runtime 保存待回答队列；既有单选/多选/自由输入原生问题页；答案/取消真实回写 `$events/result` | 已实现，真实事件未发送 |
| 活动中心 | 待审批、待回答、运行中、完成/失败/取消的原生活动列表入口；从工作台进入 | 已实现，真实完成事件需联调 |
| 工作区/目录 | Runtime 工作区列表、层级选择；既有官方字段 `path/home/crumbs/entries` 目录 picker 和新建文件夹接线 | 已实现，真实服务字段需联调 |
| 设置重构 | 外观、正文字号、代码字号、Compact/Normal、Busy Enter、减少动态效果、默认权限/工作区、通知、诊断/凭据不回显 | 已实现；通知仅保存本机偏好，未伪造系统通知 |
| 深浅色/Dynamic Type/VoiceOver | Dynamic UIColor、动态字体辅助、可访问标签/提示、44pt 控件、减少动态效果；原生 UIKit | 已实现，需真机/辅助功能逐项复核 |
| URL/鉴权安全 | 未改现有 canonicalizer、Keychain、bootstrap/API/WebSocket URL 一致性和空 query 修复 | 保持 |
| WebKit/DOM/legacy | 活跃生产源码未引入禁用路径；IPA gate `forbiddenMarkers=0` | 通过 |

## 代码与分支

- 工程：`/var/minis/shared/deepseek-harness-ios-native`
- 分支：`feature/native-renderer`
- 最终代码 SHA：`1fb8118b869225ca426484ce276c3b4228eab00c`
- 构建代码 SHA：`a9290fa25896668d44e40b185d28efce5b4ae31c`（之后仅更新本报告）
- 远端：`origin/feature/native-renderer` 与本地一致
- 文档 HEAD：`b871ed249cac880330bc1bbbfa083f9c5353fd54`
- `main` 未修改；未 force push
- 用户已有未跟踪移交/验收文档未纳入本轮报告提交：`HANDOFF-*`、`REWORK-*` 及既有验收文档

## 验证证据

### 本地 iSH

```text
python3 -m unittest discover -s Tests -p 'test_*.py' -q
Ran 16 tests ... OK
python3 scripts/verify_native_rework.py
全部 ok
python3 scripts/verify_native_ui_fixture.py
全部 ok
git diff --check
通过
```

### GitHub Actions

- Actions Run：`34010483300`
- 状态：`completed / success`
- Workflow：https://github.com/lylywayr/deepseek-harness-ios/actions/runs/34010483300
- 成功 Job：`Build iOS device IPA`、`Native UI screenshots 390x844`
- 成功包含生产 Swift XCTest、Release device archive、IPA verify、原生截图 job
- Swift/Xcode 构建在 macOS Xcode 16.2 完成；iSH 本机没有 Xcode，未伪称本地执行 archive

### IPA 独立验证

- IPA：[Harness Pocket Workspace 最终未签名 IPA](minis://attachments/pocket-run-34010483300/ipa/DeepSeekHarness-unsigned.ipa)
- 路径：`/var/minis/attachments/pocket-run-34010483300/ipa/DeepSeekHarness-unsigned.ipa`
- SHA-256：`8dbaa767161eeaab4f63c4fc9eb2bd5bbdd9f7304f7a5ae606866f3539bb7ac5`
- `verify_ipa.py`：`bundleIdentifier=com.example.DeepSeekHarness`、`minimumOSVersion=15.0`、`arm64`、`unsigned=true`、`forbiddenMarkers=0`
- IPA 未发现 `_CodeSignature` 或 `embedded.mobileprovision`
- IPA 不含 Release fixture marker；DEBUG-only 夹具通过 `#if DEBUG` 和 Debug compilation condition 接入

### 截图证据

本次成功 Run 已下载并独立检查 8 张 Native-only 场景截图：

- 目录：`/var/minis/attachments/pocket-run-34010483300/screens/`
- 链接：[390×844 Native UI 截图证据目录](minis://attachments/pocket-run-34010483300/screens/)
- 文件：`connection`、`conversation`、`sidebar`、`settings`、`directory`、`approval`、`question`、`trajectory`
- 全部 PNG 原始尺寸：`1206×2622`（iPhone 16 Simulator，内容区域 390×844pt）
- 已视觉检查：设置、目录、问题等场景无拉伸/重叠/异常裁切；截图脚本逐场景重启 App，使用 `-UITestFixture -NativeFixtureScreen <scene>`，避免场景状态串线

## 真实未验证项与诚实边界

1. **430×932、键盘态、深色模式截图本轮未生成**：当前 CI 仍只运行 390×844 的 8 场景；这是设计规格验收矩阵的剩余证据缺口，不能用 390 截图替代。
2. **签名真机未验证**：IPA 是 unsigned；真实 safe-area、Dynamic Type、VoiceOver、硬件键盘、触感和深色主题仍需用户 Team 签名安装后复验。
3. **真实业务事件未发送**：为遵守不发送付费 prompt 门禁，本轮没有发送 prompt，也没有主动触发真实审批/用户问题/产物事件。因此 Runtime 解析和回写代码有静态/编译证据，但没有真实事件闭环证据。
4. **模型、权限、附件、目录、分页 UI 未逐项真实服务走通**：生产入口和既有协议接线保留，不能把 fixture 或静态测试宣称为端到端业务验证。
5. **通知**：设置只保存通知偏好；服务端/系统通知能力未被伪造，当前不宣称后台通知已完成。
6. **多主机**：数据结构仍是单主机 Runtime；没有伪装并发多主机能力。
7. **Native manifest**：继续按可选真实声明消费；没有把声明式协议当成官方服务能力。

## 安全与回滚

- 所有改动集中在 `feature/native-renderer`，未触碰 `main`；回滚可直接回到基线 `7e954ae3f440589697610e92ae8c970337e2bd59`，或在该分支 revert 本轮提交。
- 未读取、记录或输出 token/Cookie；设置和诊断只显示是否保存，不回显凭据。
- 未访问 NAS、插件或服务；未做生产配置变更。
