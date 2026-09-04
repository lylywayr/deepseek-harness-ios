# 项目方向

## 目标

为自托管 DeepSeek Harness 提供一个原生优先 iOS 客户端。可见界面使用 UIKit/SwiftUI，通信使用 `URLSession` 的 JSON-RPC 与 `URLSessionWebSocketTask` 的 Remote Mux。当前分支不使用 WKWebView、DOM 投影或网页兼容路径。

## 基础版范围

插件停用后的基础 Harness 只应显示真实返回的会话、工作区、模型、权限、对话、轨迹、日志和目录选择能力。插件市场、专家、Agent 预设、服务控制等此前由停用插件提供的页面不属于基础版主导航；只有服务端返回明确的 Native UI manifest 时，才动态出现对应原生 surface。

## 运行结构

```text
UIKit App
  ├─ MainViewController / SetupViewController
  ├─ NativeHomeViewController
  │   ├─ rail + sidebar
  │   ├─ PolishedConversationViewController
  │   └─ HarnessDirectoryPickerViewController
  ├─ HarnessRuntime (@MainActor state coordinator)
  │   └─ HarnessClient (URLSession + JSON-RPC)
  │       └─ URLSessionWebSocketTask (/api/remote.mux)
  └─ NativeUITransport / NativeUIRenderer (declared manifest only)
```

## 真实协议对照

| 能力 | Remote / endpoint | 原生实现 | 状态 |
|---|---|---|---|
| 会话列表 | `session/list` | `HarnessRuntime.refresh` | 已实现，未在本轮访问真实 endpoint |
| 会话历史 | `session/follow`, `session/page` | follow + cursor 合并 | 已实现，未在本轮访问真实 endpoint |
| 会话操作 | `session/create`, `rename`, `fork`, `prompt`, `cancel`, `selectModel` | Runtime actions | 已实现，未在本轮访问真实 endpoint |
| 工作区 | `workspace/follow`, `create`, `rename`, `delete`, `archiveSession` | Runtime/sidebar | 已实现，未在本轮访问真实 endpoint |
| 目录 | `directoryPicker/list`, `createDirectory` | `HarnessDirectoryPickerViewController` | 按官方 `path/home/crumbs/entries` 建模；未在本轮访问真实 endpoint |
| 实时控制 | `session/control` | jobs/queues/projections | 已实现，未在本轮访问真实 endpoint |
| 工具审批 | `$events` + `$events/result` | ready clientId 关联 | 已实现，未在本轮访问真实 endpoint |
| Native UI | `api/native-ui/manifest`, `api/native-ui/action` | constrained renderer | 已实现；服务端是否提供该清单未验证 |

## 安全边界

服务地址只接受 HTTP/HTTPS，访问令牌使用 Keychain 保存，用户界面只显示是否已配置。HTTP 仅适用于私有 LAN；不要将其暴露到公网。未提供真实 endpoint、session、workspace、token、Cookie 或演示 provider 数据。

## 验证

协议回归测试：

```sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
```

Xcode device archive 由 `.github/workflows/build-ipa.yml` 执行。签名、真机安装、真实 endpoint 交互和 Native manifest 可用性需要验收者另行复核。
