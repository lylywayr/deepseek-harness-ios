# 本地自签说明

## 直接用 Xcode

1. 在 macOS 上用 Xcode 打开 `DeepSeekHarness.xcodeproj`。
2. 在 Target → Signing & Capabilities 中填写自己的 Bundle Identifier，并选择自己的 Team。
3. 连接设备，选择真实 iPhone/iPad 作为运行目标，执行 Build/Archive。

## 对 Actions 产物重签

Actions 产物名为 `DeepSeekHarness-unsigned.ipa`，不含证书和 provisioning profile，不能直接安装。使用自己的签名工具重签时，请让工具按自己的 Bundle ID、Team ID、设备和 entitlements 重新签署应用及其嵌入内容。

不要把 `.p12`、`.mobileprovision`、Apple 私钥、设备 UDID 清单或服务端凭据提交到仓库。

不同签名方式的有效期、设备限制和安装流程由 Apple 账号及所用工具决定，本项目不承诺特定签名工具的行为。
