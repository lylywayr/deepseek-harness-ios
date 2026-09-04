# 移动端基础版 UI 盘点

范围：已停用全部服务端插件后的 Harness 基础版。旧版插件提供的专家、Agent 预设、插件市场、服务控制等不列入基础版主导航。

| 入口 | 基础版是否存在 | 默认/空/加载/错误态 | 官方 Remote / endpoint | iOS 实现 | 状态 |
|---|---|---|---|---|---|
| 首次连接 | 是 | 未配置、连接中、401/403、网络失败 | 根地址；后续 `/api/*` | `SetupViewController`, `AppState` | 原生实现；真实地址未联调 |
| 新建会话 | 是 | 默认工作区或空工作区 | `session/create` | `NativeHomeViewController`, `HarnessRuntime` | 原生实现；真实 endpoint 未联调 |
| 搜索会话 | 是 | 侧栏搜索、无结果、取消 | 基于已加载 `session/list` 数据 | 侧栏 | 原生筛选；官方内容搜索边界未验证 |
| 视图选项 | 是 | 当前侧栏排序/过滤入口 | 本机偏好/已加载列表 | 侧栏 | 基础排序与状态显示；完整官方选项未验证 |
| 添加工作区 | 是 | 目录列表、空目录、失败 | `directoryPicker/list`, `createDirectory`; `workspace/create` | `HarnessDirectoryPickerViewController` | 按官方 listing 字段实现；真实 capability 未联调 |
| 工作区菜单 | 是 | 重命名、移除确认 | `workspace/rename`, `workspace/delete` | 侧栏 + Runtime | 原生实现；真实 endpoint 未联调 |
| 会话菜单 | 是 | 重命名、分叉、归档确认 | `session/rename`, `session/fork`, `workspace/archiveSession` | 侧栏 + Runtime | 原生实现；真实 endpoint 未联调 |
| 会话顶栏 | 是 | 会话标题、模型、权限、运行状态 | `session/control` projections | 对话控制器 | 原生实现；事件变体未完整联调 |
| 对话/轨迹 | 是 | 空态、加载、流式、错误 | `session/follow`, `session/page` | `PolishedConversationViewController` | 原生实现；真实 endpoint 未联调 |
| 文本发送/停止 | 是 | 空输入禁用、生成中停止 | `session/prompt`, `session/cancel` | 对话编辑器 | 原生实现；真实 endpoint 未联调 |
| 模型选择 | 是 | provider/model 列表、失败 | `session/modelCatalog`, `session/selectModel` | 对话菜单 | 原生实现；真实 catalog 未联调 |
| 权限选择 | 是 | 当前值、失败 | `commands/execute` | 对话菜单 | 原生命令实现；权限选项边界未验证 |
| 图片附件 | 是（若服务接受） | 预览、移除、发送失败 | `session/attachment` / prompt images | 对话编辑器 | 原生实现；上限和服务能力未联调 |
| 普通文件附件 | 未确认 | 不在基础菜单中虚构 | 需真实基础协议声明 | 无 | 未验证，不暴露入口 |
| 工具调用/结果 | 是 | 运行中、结果、错误 | `session/follow` 事件 | 对话/轨迹详情 | 已解析常见事件；完整变体未联调 |
| 工具审批 | 是（事件触发时） | ready、审批、允许/拒绝 | `$events`, `$events/result` | 原生 alert | clientId 关联已实现；真实事件未联调 |
| Session 日志 | 是 | 空/有内容/可复制 | 已加载真实事件 | 日志页 | 原生实现；真实事件未联调 |
| 设置 | 是 | endpoint、Keychain 状态、本机显示说明 | 本地偏好；服务端 settings 未声明 | `HarnessSettingsCenterViewController` | 不显示演示值；服务端设置未联调 |
| 插件中心 | 动态 | 无 Native manifest 时诚实空态 | `api/native-ui/manifest` | `NativePluginCenterViewController` | 仅声明 Native UI；插件停用基线无入口 |

## 不属于基础版的旧入口

专家、Agent 预设、插件市场、服务控制、通用文件浏览器和任意插件 DOM/网页兼容页面来自旧插件或未验证扩展。本分支不把它们放入基础版导航，不创建假数据，也不打开插件网页。

## 证据与限制

本清单依据当前分支已有真实采集记录、官方源码类型和插件停用后的信息架构整理。按本轮任务边界，没有重新访问 NAS、插件或真实 endpoint；所有“未联调/未验证”均保持明确标注。
