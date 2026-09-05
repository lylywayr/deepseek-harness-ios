# 项目方向

## 目标与硬边界

为自托管 DeepSeek Harness 提供一个原生优先 iOS 客户端。活跃 target 使用 UIKit、URLSession JSON-RPC 和 URLSessionWebSocketTask Remote Mux；不恢复网页渲染、DOM 投影或 legacy 页面路径。服务端插件不安装到 iOS。

## 能力对照

| 能力 | 协议/入口 | 当前状态 |
|---|---|---|
| 会话列表/历史 | `session/list`、`session/follow`、`session/page` | 原生实现；列表 wrapper 与分页 cursor 已由 HarnessWire 约束 |
| 会话操作 | create/rename/fork/prompt/cancel/selectModel | 原生实现；请求型参数使用 `args.request` |
| 工作区 | follow/create/rename/delete/archiveSession | 原生实现；真实部署行为待 smoke test |
| 目录 | directoryPicker/list/createDirectory | 原生 picker；使用官方 `path/home/crumbs/entries` 字段 |
| 实时状态/审批 | session/control、`$events`、`$events/result` | 原生 Mux；真实事件变体待联调 |
| 对话/轨迹/日志 | follow/page records | 原生 UIKit；常见事件已解析，富文本语义未完整验证 |
| 模型/权限/图片 | modelCatalog/selectModel、commands/execute、prompt images | 原生入口；服务能力和上限待联调 |
| Native UI | 可选 `dsh-native-ui/1` manifest/action | 受限原生 renderer；不是官方默认能力声明 |
| 设置 | 本机连接与本机显示说明 | 未伪造服务端 settings；真实 settings Remote 尚未接入 |

## 参数契约

生产 `HarnessWire.swift` 已进入 App Sources，且由 Swift XCTest target 引用：`session/list` 使用 `args._request`；请求型调用使用 `args.request`；`session/follow` 只能经 `/api/remote.mux`，unary 调用走 `/api/<endpoint>`。这些形状由 `Tests/HarnessWireTests.swift` 覆盖。

## 不伪造的入口

本地侧栏筛选只过滤已加载的 session/list 数据，不宣称服务端 `session/search` 可用。完整视图选项（排序、分组、归档显示）、服务端可编辑设置、完整 Markdown/代码块/链接/复制、用户问题变体、普通文件浏览及目标服务的 Native manifest，当前没有足够真实 endpoint 证据，界面不填充演示数据。

## 验证

```sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
git diff --check
```

Swift 生产 wire 测试、Xcode device archive 与 IPA 门禁由 GitHub Actions 执行；本机 iSH 没有 Xcode。真实 endpoint、签名真机、390×844 原生截图和目标服务 Native manifest 是否存在，见 `docs/native-completion-report.md` 的事实记录。
