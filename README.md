# DeepSeek Harness iOS

Open-source, native-first iOS client for a self-hosted DeepSeek Harness instance.

> 中文说明在下方。This is an independent community client, not an official DeepSeek product.

## Current scope

The visible app shell is UIKit-native: connection setup, session rail, sidebar, workspace/session lists, conversation, trajectory, logs, directory selection, settings, model/permission controls, attachments, approvals, and declared Native UI plugin surfaces. Networking is also native (`URLSession` JSON-RPC plus `URLSessionWebSocketTask` Remote Mux); no WebView is used for communication or presentation.

The client does not install plugins on iOS. A server may expose versioned `dsh-native-ui` manifests. Declared surfaces are rendered from a constrained native component tree and actions are sent back through the native transport. Unsupported or legacy-only surfaces show a native “not available” explanation; this branch does not open plugin webpages or project arbitrary DOM into native UI.

## What is implemented

- iOS 15+, arm64 device target and unsigned IPA workflow.
- Configurable HTTP/HTTPS Harness endpoint; optional access token is stored in Keychain and never displayed.
- Native JSON-RPC envelope/response correlation and structured remote errors.
- Native Remote Mux subscriptions for workspace, session control, event approvals, and the selected session; bounded reconnect and old-session cancellation.
- Session creation, selection, rename, fork, archive, history paging, live messages, stop, model catalog/model selection, permission command, image attachments, tool approvals, workspace management, and directory browsing.
- Native plugin manifest refresh, constrained renderer, action dispatch, and explicit unsupported-surface state.
- Dependency-free protocol regression fixtures under `Tests/`.

## What is deliberately not claimed

The current repository is not a substitute for a signed-device acceptance run. The real Harness endpoint was not contacted during this close-out, per the task boundary. Endpoint-specific authentication, server capability availability, native manifest availability, user-question variants, and behavior on a signed physical device remain acceptance items. The app only exposes capabilities actually returned by the service; it does not fabricate plugin, expert, market, service-control, or settings pages. A local sidebar filter may narrow the already loaded session list, but it is not a claim that the server-side search Remote is available.

## Verification boundary

Production `HarnessWire.swift` is part of the app Sources build phase and is also compiled into the Swift XCTest target. The tests cover the reserved `session/list` request wrapper, request-bearing Remotes, session paging/follow, RPC correlation and structured errors, Remote Mux frames, and event results. Python fixtures remain dependency-free for Alpine smoke checks. Xcode/Swift execution and the unsigned device archive are evidenced only by the relevant GitHub Actions run; iSH has no Xcode.

The repository does not claim a real endpoint smoke test, signed-device installation, 390×844 native screenshot, or server-provided Native UI manifest unless the completion report records such evidence. See [native completion report](docs/native-completion-report.md).

Open `DeepSeekHarness.xcodeproj` in Xcode, or run **Actions → Build unsigned IPA → Run workflow**. The artifact is intentionally unsigned and must be re-signed with the user's own Apple account and provisioning setup before installation. See [self-signing notes](docs/self-signing.md).

## Security

HTTP is retained only for private LAN deployments and sends credentials, messages, and files without transport encryption. Prefer HTTPS or a private encrypted network. Do not publish private URLs, tokens, cookies, certificates, provisioning profiles, or personal logs. See [SECURITY.md](SECURITY.md).

## 中文说明

这是面向自托管 DeepSeek Harness 的原生优先 iOS 客户端，不是官方 DeepSeek 产品。所有用户可见界面和通信均由原生 UIKit/URLSession 实现，不使用 WKWebView、DOM 投影或网页兼容路径。服务端插件仍安装在 Harness 服务端；iOS 只消费明确声明的 Native UI 清单，无法原生表达的插件界面会显示诚实的原生不可用说明，不会打开插件网页。

插件市场、专家、Agent 预设、服务控制等仅由已停用插件提供的入口不会被伪装为基础版能力。模型、权限、会话、工作区和运行状态只有在真实 Remote 返回后才显示；未联调能力会明确写出“未声明/未验证”，不会用演示数据填充。

详见 [原生完成报告](docs/native-completion-report.md)、[基础版 UI 盘点](docs/mobile-ui-inventory.md) 和 [项目方向](docs/PROJECT.md)。

## License

Released under the [MIT License](LICENSE). DeepSeek、Harness 及相关名称归其各自权利人所有。本项目不代表与其存在官方隶属或背书关系。
