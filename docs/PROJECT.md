# DeepSeek Harness iOS — 项目方向

## 目标

为自托管 DeepSeek Harness 提供一个 **Native-first** iOS 客户端：可见主界面使用 UIKit/SwiftUI 原生绘制；现有服务端插件无需安装到 iOS；插件 UI 通过自动适配器尽量转换为原生；转换失败时按页面或子树进入兼容层。

## 已确定约束

- 面向个人自用，也欢迎其他用户自行部署和构建。
- 不上架 App Store，不依赖 TestFlight。
- GitHub Actions 使用 macOS Runner 构建设备版未签名 IPA。
- 最低支持 iOS 15.0，目标架构 arm64。
- 支持 HTTP 与 HTTPS；公网部署推荐 HTTPS 或 VPN/组网。
- 不提交任何账号、Token、证书、私有地址或签名材料。
- MIT License。
- 不要求现有 Harness 插件作者逐个适配。

## Native-first 架构

- `NativeUIProtocol.swift`：版本化 Native UI IR、manifest、action 和 transport。
- `NativeUIRenderer.swift`：把通用节点转换为 UIKit 控件。
- `AutoNativeAdapter.swift`：在隐藏兼容运行时读取既有 `dsh.client` 页面，并尝试投影常见 DOM 控件。
- `NativeMainViewController.swift`：原生窗口、侧边栏、插件中心和聊天壳。
- `NativeUIViews.swift`：动态插件 surface 与诊断界面。
- `MainViewController.swift`：Legacy Web 兼容层，仅在必要时打开。

## 动态插件策略

插件仍由 Harness 服务端安装和运行。App 通过清单动态发现插件 surface、按钮、页面和设置；点击事件回到服务端。自动投影优先覆盖常见文本、按钮、输入、开关、容器、列表和插槽入口。未知组件生成明确的兼容卡片，不静默白屏。

当前 `NativeUITransport` 预留 `/api/native-ui/manifest` 与 `/api/native-ui/action`，并保留自动适配路径；接下来需要依据官方 Harness 的真实 Session/Remote 契约接入服务端适配器，而不是假设现有部署已经提供这两个路径。

## 分支与验证

- `main`：已验证的 WebView 预览版本。
- `feature/native-renderer`：Native-first MVP。
- 构建工作流：`.github/workflows/build-ipa.yml`。
