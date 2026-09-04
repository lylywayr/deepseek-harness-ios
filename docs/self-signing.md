# 自签名与安装

GitHub Actions 生成的是面向 iOS 设备的未签名 IPA。它不包含证书、provisioning profile 或用户凭据，不能直接安装。

1. 下载 `DeepSeekHarness-unsigned.ipa`。
2. 使用自己的 Apple Team、Bundle ID、设备 UDID 和 provisioning setup 重新签名。
3. 让签名工具同时重新签署 App 及嵌入内容，然后再安装到设备。
4. 首次启动后，在原生连接页填写 Harness 的 HTTP/HTTPS 地址；访问令牌可选并仅保存到本机 Keychain。

HTTP 只适用于可信私有 LAN；公网或跨网络部署请使用 HTTPS 或 VPN。项目不会默认跳过 TLS 校验，也不会把 token 写入 URL、UserDefaults、日志或 IPA。

真实 Harness endpoint、服务端 capability、Native manifest、签名安装和真机行为需要使用者在自己的环境中复核；本仓库的完成报告不会把这些未知项写成已验证。
