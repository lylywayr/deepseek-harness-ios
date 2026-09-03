# DeepSeek Harness iOS — Native-first MVP

这一条主线已经从“网页客户端壳”切换为 **原生主界面 + 自动原生适配 + 兼容层兜底**。

## 当前已实现

- 可见主界面使用 UIKit 原生窗口、导航栏、侧边栏、插件中心和聊天壳。
- iOS 不安装 Harness UI 插件，也不执行插件原生代码。
- `NativeUIManifest` / `NativeUINode` / `NativeUIActionRequest` 定义版本化的原生中间表示。
- `NativeUIRenderer` 将文本、按钮、输入框、开关、容器、列表、分组等节点绘制为 UIKit 控件。
- `NativeUITransport` 预留 `/api/native-ui/manifest` 和 `/api/native-ui/action` 服务端协议。
- `AutoNativeAdapter` 在隐藏兼容运行时中加载现有 Harness Web 客户端，读取 DOM/可访问标签并投影为 Native UI 树。
- 未支持节点按子树生成兼容模式卡片，不会让整页无提示白屏；点击后进入旧 Web 插件页面。
- 清单更新会刷新原生侧边栏和插件中心，不需要重新打包 IPA。
- GitHub Actions 已验证可构建 iOS 15+ arm64 未签名 IPA。

## 重要边界

目前 Harness 官方插件客户端是 React/TSX Web UI。自动 DOM 投影是渐进式兼容机制，不等于任意 CSS、Canvas、富文本编辑器、Web Worker 或浏览器专用 API 都能立即变成原生控件。失败样本应转化为适配器规则和回归 fixture，逐步扩大原生覆盖率。

兼容层仍然保留，但只负责 Legacy Web Surface，不负责 App 主界面。后续应先把官方 Harness 的真实 Session/Remote 契约接入 Native Transport，再逐步替换当前聊天壳和自动投影中的占位行为。

## 分支与验证

- `main`：此前已验证的 WebView 预览版本。
- `feature/native-renderer`：Native-first MVP。
- 构建工作流：`.github/workflows/build-ipa.yml`。
