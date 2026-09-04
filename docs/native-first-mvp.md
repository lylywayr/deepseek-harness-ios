# Native-first MVP

本分支是一个纯原生 UIKit/URLSession 实现：用户可见界面不依赖网页，网络层也不通过隐藏 WebView 获取鉴权或调用服务。

## Native UI manifest

服务器可选地返回版本化 `dsh-native-ui` manifest。客户端只渲染协议允许的原生组件树（文本、按钮、输入、开关、列表、容器和明确的 action），并将 action 通过原生 `api/native-ui/action` 发送回服务端。清单为空、协议不支持或 surface 使用 legacy/web 类型时，客户端显示原生不可用说明，不会打开网页。

## Harness Remote

`HarnessRuntime` 使用 URLSession JSON-RPC envelope，并通过 `/api/remote.mux` 的 `URLSessionWebSocketTask` 订阅 workspace、session control、selected session 和 `$events`。RPC response 会校验 HTTP、`server-response`、`rpcId`、`result.ok` 和结构化错误；会话切换取消旧 follow，断线采用有界延迟重连。访问令牌在 Keychain 中保存。

## 已实现边界

已实现基础会话、工作区、目录选择、对话、轨迹、日志、模型、权限、图片附件、审批和清单声明的 Native UI surface。插件不会安装到 iOS；插件市场、专家、服务控制、任意 DOM/Canvas/Web Worker 等不属于当前基础版原生能力。未由真实服务返回的能力不会用演示数据填充。

## 当前限制

本次收尾按任务要求没有访问真实 Harness endpoint、NAS 或插件，因此真实部署上的鉴权方式、服务端目录 capability、Native manifest 和事件变体没有在本轮联调。Xcode/Actions 构建和脱敏协议 fixtures 是可复现证据；签名后真机交互仍需验收者执行。
