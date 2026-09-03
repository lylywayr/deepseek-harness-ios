# DeepSeek Harness iOS

A small, open-source iOS client shell for a self-hosted or privately deployed DeepSeek Harness service.

> 中文说明在下方。This project is an independent client and is not an official DeepSeek product.

## What it does

- Loads an existing DeepSeek Harness web interface inside a native iOS shell.
- Supports configurable `http://` and `https://` service addresses.
- Keeps the Harness web session in the standard `WKWebsiteDataStore`.
- Provides native navigation controls, network status feedback, downloads and sharing.
- Leaves models, plugins, skills, conversations, streaming and server-side execution to Harness.
- Produces an unsigned, device-oriented IPA from GitHub Actions; signing is left to the owner.

This repository does **not** contain the Harness server, models, plugins, skills, credentials or any service endpoint.

## Requirements

- iOS 15.0 or later
- arm64 iPhone or iPad
- Xcode on macOS for local builds, or the included GitHub Actions workflow
- A reachable DeepSeek Harness instance

## Quick start

1. Open `DeepSeekHarness.xcodeproj` in Xcode.
2. Set your own Bundle Identifier and Team if you want to sign locally.
3. Build and run on an iOS 15+ device.
4. Enter the Harness address on first launch, for example:

   - `http://192.168.31.250:PORT`
   - `https://harness.example.com`

The address is stored locally on the device. Cookies and web session data are kept by the system WebKit data store.

## Build an unsigned IPA with GitHub Actions

Open **Actions → Build unsigned IPA → Run workflow**. The workflow runs on a GitHub-hosted macOS runner, builds the device target with the iPhoneOS SDK, and uploads `DeepSeekHarness-unsigned.ipa` as an artifact.

The artifact is intentionally unsigned. It does not include an Apple certificate, provisioning profile or developer secret. Re-sign it with your own preferred tool before installing it. An unsigned IPA cannot be installed directly.

The workflow is designed for personal builds and is not a promise of App Store distribution compatibility.

## Security and privacy

- HTTP is enabled because private LAN deployments may not have TLS. HTTP sends login data, cookies, messages and files in plaintext; do not expose it to the public Internet.
- Prefer HTTPS, Tailscale/VPN or another private encrypted network for remote access.
- Never commit Harness URLs containing credentials, tokens, certificates or provisioning profiles.
- This client has no analytics, advertising SDK, bundled model or third-party account service.
- Clearing the web session from Settings removes WebKit website data on the device; it does not delete server-side conversations or files.

See [Security](SECURITY.md) and [self-signing notes](docs/self-signing.md).

## Scope and limitations

This is a client shell, not a replacement for the Harness server. Actual compatibility depends on the Harness web build and its reverse proxy. File upload uses the WebKit/iOS file picker when the page requests a file; download behavior depends on the response type and server headers. Background execution is not promised: the server may continue a task while iOS suspends the app, and the app can refresh state when reopened.

The project intentionally starts with a WebView-first architecture. Native screens can be added later where the real Harness UI needs a better mobile experience.

## 中文说明

这是一个面向自托管或私有部署 DeepSeek Harness 的个人 iOS 客户端壳。它复用现有 Harness Web/API，不在手机上运行 Harness 服务，也不重新实现模型、Plugins、Skills、会话和服务端任务。

首版目标：

- iOS 15.0+
- 可编辑 Harness 服务地址
- 同时支持 HTTP 与 HTTPS
- 保留 WebKit Cookie 和网页会话
- 支持网页中的流式输出、WebSocket/SSE、文件上传下载（以服务端和 WebKit 实际能力为准）
- 原生返回、前进、刷新、网络状态和分享入口
- GitHub macOS Runner 构建未签名 arm64 IPA

HTTP 只是为了兼容家庭局域网等私有环境。公网访问请使用 HTTPS 或 VPN/组网，不要把带登录信息的 Harness 直接暴露在普通 HTTP 上。

## Contributing

Issues and pull requests are welcome. Please do not include private server addresses, logs containing cookies, tokens, certificates or user data. Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

Released under the [MIT License](LICENSE). DeepSeek, Harness and related names remain the property of their respective owners. This repository does not claim affiliation with them.
