# Native-first MVP

本分支是纯原生 UIKit/URLSession 客户端：用户可见界面和网络层都不依赖网页。

## Harness Gateway 映射

`HarnessRuntime` 使用 `URLSession` 发送 JSON-RPC：请求 envelope 为 `client-request`，响应校验 `server-response`、`rpcId`、`result.ok` 和结构化错误。已核实的参数规则集中在生产 `HarnessWire`：

- `session/list`：`payload.args` 必须是 `{ "_request": {} }`，不能是空对象。
- `session/create`、`session/prompt`、`session/cancel`、`session/selectModel`、`session/page` 及会话/工作区请求型操作：请求对象放在 `payload.args.request`。
- `directoryPicker/list` 和 `directoryPicker/createDirectory`：按官方目录 Remote 使用顶层 `path`/`name`。
- unary Remote 使用 `/api/<endpoint>`；`workspace/follow`、`session/control`、`session/follow`、`$events` 通过 `/api/remote.mux` 的 `open`/`item`/`end`/`error` 帧。`$events` 的 ready 帧提供 `clientId` 与 host，审批回复使用 `$events/result` 的 `clientId`、`eventId`、`outcome`。

## 已实现边界

基础会话、工作区、目录选择、对话、轨迹、日志、模型、权限、图片附件、审批和声明式 Native UI surface 已有原生实现。会话侧栏支持基于已加载 `session/list` 的本地筛选。未把当前部署不可用或尚未声明的搜索、插件市场、专家、服务控制、服务端设置和普通文件能力伪装成已完成。

Native UI 是可选的 `dsh-native-ui/1` 协议，不代表官方 Harness 已默认提供。插件不会安装到 iOS；不支持的组件只显示原生诊断卡片。

## 验证边界

Python fixtures 与 `HarnessWireTests.swift` 覆盖生产 wire builder/parser。后者和设备 archive 由 GitHub Actions 执行；iSH 没有 Xcode。真实 endpoint 只读 smoke test、签名真机交互、390×844 原生截图和目标服务 Native manifest 能力，必须以报告中的实际证据为准。
