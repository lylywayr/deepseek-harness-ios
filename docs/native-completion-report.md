# DeepSeek Harness iOS Native-first 完成报告

## 本次返工结论

`feature/native-renderer` 已完成协议返工的代码与 CI 交付链：生产 `HarnessRuntime` 使用集中式 `HarnessWire` 构造 Gateway envelope，`HarnessWire.swift` 已进入 App Sources，Swift XCTest 测试文件已进入工程的测试目标配置；Python fixture 也已修正，不再断言错误的空 `session/list` 参数。

本报告不把绿色构建等同于真实服务功能验收。目标服务真实 endpoint、签名真机和 390×844 原生截图的状态只在下方有证据时才视为完成。

## 代码范围

- `session/list`：`payload.args` 为 `{ "_request": {} }`。
- 请求型会话/工作区 Remote：请求对象位于 `payload.args.request`。
- `session/page`：使用 `address.kind/sessionId`、`throughSeq`，可选 `beforeSeq`/`maxMessages`。
- `session/follow`：仅经 `/api/remote.mux` 的 `open`，使用 `args.request`；unary 调用仍走 `/api/<endpoint>`。
- 目录列表/创建：使用官方顶层 `path`/`name`；listing 按 `path`、`home`、`crumbs`、`entries`、`truncated` 解码。
- RPC response：校验 `server-response`、rpcId、`result.ok`；失败必须包含结构化 `error.code` 和 `error.message`。
- Mux open/cancel/server item/end/error 与 `$events/result` 均由生产 helper 构造/解析；实时流仍使用原生 `URLSessionWebSocketTask`。
- UIKit 可见 UI 不使用网页渲染；Native UI 仅是可选、服务端明确声明的 `dsh-native-ui/1` 清单，不宣称官方 Harness 默认提供。

## 已执行验证

### 本地 iSH（已执行）

```text
python3 -m unittest discover -s Tests -p 'test_*.py' -v
```

预期/实际：Python 协议回归测试通过（含修正后的 `_request`、请求型 `request`、RPC 关联/结构化错误、Mux、目录、审批和图片块断言）。

```text
git diff --check
```

实际：通过。

本地没有 Xcode、swiftc 或 XCTest 运行器，因此没有把 Swift 编译/测试声称为本地通过。

### CI 执行路径

工程配置包含：

- App target 的 `HarnessWire.swift` PBXFileReference、PBXBuildFile、源码组和 Sources build phase；
- Swift XCTest 源文件引用、XCTest framework、测试产物和测试 target 配置；
- `build-ipa.yml` 在 archive 前执行 Python 测试，并在 archive 后执行 `scripts/verify_ipa.py`。

Swift 测试是否可执行、目标配置是否被 Xcode 接受，以本次 Actions 日志为最终证据；若 workflow 仅成功 archive 而未执行 XCTest，则不把它写成 Swift XCTest 已通过。

### 禁止路径门禁

活跃 Swift 源码保持 UIKit/URLSession 路线；没有恢复网页渲染、DOM 投影或网页兼容路径。旧移交/验收文档中的关键词仅作为历史验收记录，不属于活跃 target。

## 功能边界与诚实化

- 侧栏可对已加载 `session/list` 结果做原生本地筛选；这不冒充服务端 `session/search`，后者在此前部署证据中为 disabled。
- 未有真实协议证据的完整排序/分组/归档显示选项、服务端 settings 编辑、完整 Markdown/代码高亮/链接复制、用户问题变体、普通文件浏览，不伪装为完成。
- 目录 picker 采用官方 listing 字段，不假设 entry 有 `isDirectory`。
- 插件入口只消费声明式 Native manifest；没有清单时显示空态或不可用说明，不安装插件、不打开网页。

## 本次最终 CI / IPA（待本次 Actions 成功后回填）

- Commit：待提交后回填
- Actions run：待 dispatch 后回填
- Workflow URL：待 dispatch 后回填
- Artifact URL：待下载后回填
- IPA 文件：待下载后回填
- SHA-256：待下载后回填
- Bundle ID：`com.example.DeepSeekHarness`
- MinimumOSVersion：`15.0`
- 架构：`arm64` device archive
- 签名：unsigned
- IPA 门禁：`scripts/verify_ipa.py` 应通过；最终结果待本次 artifact 验证

## 未验证风险

1. 本次返工没有访问 NAS、目标 Harness endpoint 或服务端插件；因此真实鉴权、只读 `session/list` 返回、模型 catalog、真实 WebSocket follow/control/events、分页、发送/停止、目录 capability、审批和 Native manifest 仍需真实环境复核。
2. 未进行签名安装、真机交互和 390×844 原生 App 截图采集；unsigned IPA 不能直接作为安装成功证据。
3. Swift XCTest 在 CI 中的最终通过状态必须以本次 workflow 日志核对；本地无法代替该证据。
4. Native manifest/action 是本客户端可选协议，不等于官方 Harness 或任一现有插件已实现该协议。

## 验收复核项

- [ ] 确认分支仍为 `feature/native-renderer`，未修改 `main`、未 force push。
- [ ] 检查 Actions 日志是否实际执行 Swift XCTest，而不只执行 Python fixture。
- [ ] 检查最终 IPA 的 Bundle ID、iOS 15、arm64、unsigned 与 `verify_ipa.py` 输出。
- [ ] 在用户自己的授权环境进行非破坏性真实 endpoint smoke test。
- [ ] 复核 WebSocket `session/follow` 及 control/events 帧的真实返回。
- [ ] 使用用户自己的 Team 签名，在 390×844 真机/模拟器采集原生截图。
- [ ] 仅在服务明确返回 `dsh-native-ui/1` manifest 时复核插件原生入口。
