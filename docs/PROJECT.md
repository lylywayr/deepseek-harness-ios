# DeepSeek Harness iOS — 项目方向

## 目标

为自托管 DeepSeek Harness 提供一个轻量 iOS 客户端壳，优先复用现有 Harness Web/API，避免在 iOS 端重复实现服务端能力。

## 已确定约束

- 面向个人自用，也欢迎其他用户自行部署和构建。
- 不上架 App Store，不依赖 TestFlight。
- GitHub Actions 使用 macOS Runner 构建设备版未签名 IPA。
- 最低支持 iOS 15.0，目标架构 arm64。
- 支持 HTTP 与 HTTPS；公网部署推荐 HTTPS 或 VPN/组网。
- 不提交任何账号、Token、证书、私有地址或签名材料。
- MIT License。

## 首版边界

- SwiftUI 外壳与 WKWebView。
- 可编辑服务地址，并进行 scheme 校验。
- 持久化 WebKit 会话。
- 原生导航、刷新、网络状态、下载/分享辅助。
- 后台任务不由客户端承诺；服务端任务可继续，回到前台后刷新状态。

## 暂不包含

- Harness 服务端实现。
- 推送通知、多账号、多服务器管理。
- 原生重写全部 Harness 页面。
- 第三方分析、广告或模型 SDK。
