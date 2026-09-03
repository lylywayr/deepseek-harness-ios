# DeepSeek Harness iOS

Open-source, native-first iOS client for a self-hosted DeepSeek Harness instance.

> 中文说明在下方。This is an independent community client, not an official DeepSeek product.

## Product direction

The app is **native-first**: the visible shell, navigation, sidebar, chat surface, settings and plugin surfaces are rendered with UIKit/SwiftUI controls. It does not require installing any iOS UI plugin.

Existing Harness plugins remain server-side. The client uses a three-step compatibility strategy:

1. **Native UI manifest** — if a server adapter provides a versioned `dsh-native-ui` tree, the app renders it natively and dynamically.
2. **Automatic projection** — the adapter can inspect existing `dsh.client` Web UI and project common DOM controls into the same native intermediate representation, without requiring every plugin author to change code.
3. **Per-surface fallback** — unsupported or browser-specific parts remain available through the legacy Web compatibility surface instead of blanking the whole app.

This is deliberately incremental. The conversion engine improves from reproducible unsupported-component fixtures. It does not claim that arbitrary Canvas, Monaco, custom CSS engines, Web Workers or browser-only behavior is already equivalent to native UI.

## What users get

- iOS 15.0 or later; arm64 iPhone/iPad.
- Configurable `http://` and `https://` Harness endpoint.
- Native app frame, sidebar, plugin center, settings entry and initial chat surface.
- Dynamic native plugin surfaces, buttons, forms and actions when a manifest is available.
- Automatic best-effort projection of legacy `dsh.client` surfaces.
- A compatibility path for unsupported legacy plugin UI.
- No plugin installation, model bundle, analytics SDK or third-party account service on the device.
- GitHub Actions workflow for a device-oriented unsigned IPA; users sign with their own account and tools.

## Current MVP status

The `feature/native-renderer` branch contains the Native-first MVP and has a successful GitHub macOS/Xcode build. It currently proves the native surface protocol, renderer, hidden legacy adapter, per-surface fallback and dynamic manifest refresh. The official Harness Session/Remote contract still needs to be wired into the native chat and action transport before this should be called feature-complete.

The `main` branch remains the earlier WebView preview until the Native-first branch is reviewed and promoted.

## Requirements

- iOS 15.0 or later.
- A reachable self-hosted/private DeepSeek Harness instance.
- Xcode on macOS for local builds, or the included GitHub Actions workflow.
- A valid signing method of your choice for installation. The repository never includes signing material.

## Quick start

1. Open `DeepSeekHarness.xcodeproj` in Xcode, or run the manual GitHub Actions workflow.
2. Sign the resulting app/IPA with your own Apple account and provisioning setup.
3. Configure your Harness endpoint in the app.
4. Prefer HTTPS or a private encrypted network for remote access.

## Build an unsigned IPA

Open **Actions → Build unsigned IPA → Run workflow**. The workflow uses a GitHub-hosted macOS runner and uploads `DeepSeekHarness-unsigned.ipa`. The artifact is intentionally unsigned and cannot be installed until it is re-signed.

## Security and privacy

HTTP is enabled for private LAN deployments but sends credentials, cookies, messages and files in plaintext. Do not expose it to the public Internet. Prefer HTTPS or a VPN/Tailscale-style private network. Do not submit private URLs, cookies, tokens, certificates, provisioning profiles or personal logs in issues and pull requests.

See [Security](SECURITY.md), [contributing](CONTRIBUTING.md), [self-signing notes](docs/self-signing.md), and the [Native-first MVP notes](docs/native-first-mvp.md).

## 中文说明

这是一个面向自托管 DeepSeek Harness 的 **原生优先 iOS 客户端**，不是官方 DeepSeek 产品。

可见的 App 主界面使用 UIKit/SwiftUI 原生控件绘制，包括：

- 原生导航和侧边栏；
- 原生聊天页面；
- 原生设置、模型、附件和插件入口；
- 插件动态新增的按钮、页面、表单和侧边栏入口；
- 对暂时无法转换的插件界面按页面或子树降级到兼容层。

插件仍然安装在 Harness 服务端，iPhone 不安装任何 UI 插件。对于已有数十万插件，自动适配器会尝试加载现有 `dsh.client` Web UI，将常见 DOM 控件投影成原生中间表示，再由 iOS 原生渲染器绘制。发现一个失败案例后，可以补充适配规则和回归样例，逐步提高覆盖率。

兼容层会继续保留一段时间，用于 Canvas、复杂富文本编辑器、浏览器专用 API、自定义复杂 CSS 等暂时无法可靠原生化的内容。目标是让原生成为默认路径，而不是承诺任意网页行为立即百分百等价于 SwiftUI。

## License

Released under the [MIT License](LICENSE). DeepSeek、Harness 及相关名称归其各自权利人所有。本项目不代表与其存在官方隶属或背书关系。
