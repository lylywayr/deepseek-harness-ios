# DeepSeek Harness iOS 原生完成报告

## 结论

`feature/native-renderer` 当前交付的是一个原生优先、无 WebView 的 iOS 客户端分支。可见 UI 和通信均为原生 UIKit/URLSession；服务端插件不安装到 iOS。无法由 Native UI manifest 表达的 surface 只显示原生不可用说明，不会打开网页。

本报告严格区分“代码已实现”“本地可复现验证”和“本轮未联调”。本轮按任务硬约束没有访问 NAS、真实 Harness endpoint 或插件，因此不声称真实部署 smoke test 或真机通过。

## 架构

```text
UIKit App
  ├─ SetupViewController / AppState
  ├─ NativeHomeViewController
  │   ├─ rail + sidebar + workspace/session actions
  │   ├─ PolishedConversationViewController
  │   └─ HarnessDirectoryPickerViewController
  ├─ HarnessRuntime (@MainActor)
  │   ├─ HarnessClient: URLSession JSON-RPC
  │   ├─ Keychain credential store
  │   └─ Remote Mux: URLSessionWebSocketTask /api/remote.mux
  └─ NativeUITransport + NativeUIRenderer
      └─ declared manifest component tree only
```

## 能力矩阵

| 能力域 | 结果 | 证据/限制 |
|---|---|---|
| 连接与凭据 | 已实现 | HTTP/HTTPS；令牌写入 Keychain；真实鉴权未联调 |
| JSON-RPC | 已实现 | envelope、HTTP、rpcId、ok/error 校验；fixtures 通过 |
| Remote Mux | 已实现 | workspace/session/control/events/follow、取消、重连路径；真实流未联调 |
| 会话 | 已实现 | 创建、切换、重命名、分叉、归档、分页、发送、停止 |
| 工作区 | 已实现 | 添加、重命名、移除、目录浏览；官方 listing 字段已建模 |
| 对话/轨迹/日志 | 已实现 | 原生 UIKit、常见事件合并、详情和日志；完整事件变体未联调 |
| 模型/权限 | 已实现 | 读取 catalog、选择模型、权限命令；服务选项未联调 |
| 图片附件 | 已实现 | 原生选择、预览和 prompt 图片块；服务上限未联调 |
| 审批 | 已实现 | `$events` ready.clientId 与 result 关联；真实事件未联调 |
| Native UI 插件 | 已实现 | manifest/action/constrained renderer；服务端是否声明未验证 |
| 设置 | 已实现边界 | 本地说明、连接和凭据状态；未伪造服务端 settings |

## 官方 Remote 对照

- `session/list`、`session/modelCatalog`
- `session/create`、`session/rename`、`session/fork`
- `session/prompt`、`session/cancel`、`session/selectModel`、`session/page`、`session/follow`
- `workspace/follow`、`workspace/create`、`workspace/rename`、`workspace/delete`、`workspace/archiveSession`
- `directoryPicker/list`、`directoryPicker/createDirectory`（参数为顶层 `path`/`name`，不是 `request` 包装）
- `session/control`
- `$events`、`$events/result`
- Native UI：`/api/native-ui/manifest`、`/api/native-ui/action`（是否由目标服务提供未验证）

## 已移除与禁止路径

- 活跃 target 中无 `WebKit`、`WKWebView`、`evaluateJavaScript`、DOM adapter 或 `HarnessWebView`。
- legacy/web surface 不再打开网页；只显示原生不可用卡片。
- 删除/清理了旧设置草稿中的演示 provider、专家数量、插件市场、服务控制和“待接入”式假交互。
- 未写入真实 endpoint、session/workspace ID、Cookie、令牌、NAS 路径或签名材料。

## 可复现验证

```sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
# 10 tests, OK

git diff --check
# 通过

find DeepSeekHarness -type f -name '*.swift' -print0 \
  | xargs -0 grep -nE \
  'WKWebView|evaluateJavaScript|AutoNativeAdapter|HarnessViewController|openLegacy|window\\.__harnessNative|dom-projection'
# 无命中
```

`Tests/` 为无依赖 Python 协议 fixture，覆盖 RPC envelope/correlation、结构化错误、Remote Mux 帧、ready/clientId、目录 listing、session page cursor、图片块和 HTTP 分类。Xcode/IPA 门禁由 GitHub Actions 执行。

## GitHub Actions 与 IPA

最终 Run、artifact、IPA SHA-256、Info.plist、架构和 macOS `otool -L` 结果在构建成功后补入本节；若该报告随提交先进入仓库，不能把旧基线产物冒充最终产物。

## 未实现/限制

1. 本轮未访问真实 Harness endpoint，故 endpoint 鉴权、服务 capability、真实目录返回、流式事件变体和 Native manifest 可用性未验证。
2. 未进行签名后真机安装和 390×844 原生截图采集；需要验收者使用自己的 Team/Provisioning 复核。
3. 服务端 settings Remote、普通文件附件、用户问题变体和完整 Markdown/富文本语义未在本轮 endpoint 联调；客户端不显示未经声明的入口。

## 安全

HTTP 仅用于私有 LAN，生产或公网应使用 HTTPS/VPN。访问令牌只写入 Keychain，日志、UserDefaults、源码和报告不保存秘密。IPA 为未签名产物，安装前必须由用户自行签名。
