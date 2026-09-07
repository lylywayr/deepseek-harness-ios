## 最新收口记录（continuation=20, 2026-09-07）

- Run 34096457897，headSha=a1f3689，两个 Job 均 completed/success：Native Pocket UI screenshots matrix、Build iOS device IPA。
- 证据目录：/var/minis/attachments/apple-conversation-run-34096457897/；28 张 PNG：390x844 12 张，430x932 16 张；尺寸分别 1170x2532 与 1290x2796；manifest 与 PNG 逐项一致，28/28 唯一。
- 视觉抽查通过项：390 light、430 light、430 dark 会话图结构正常，header/四模式/config summary/消息流/底部 composer 可见，无明显裁切、遮挡、重叠；390 keyboard 输入区布局和无遮挡/不重叠观察结果；430 keyboard 有真实系统 QWERTY 键盘；390 没有完整键盘按键，属于模拟器渲染差异。
- 键盘完整按键不再是阻塞项，390/430差异与模拟器边界。
- 当前 reasoning 实现准确描述：模型目录返回 reasoning efforts；Pocket UI 的“推理”按钮通过 session/selectModel 发送 reasoningEffort；Runtime 解析 chunkrow/reasoning-chunks、assistant/chunk 中的 reasoning chunk，聚合到 live:reasoning、系统项 subtitle=“思考中”；过程/轨迹模式可呈现这些事件；默认 compact transcript 会过滤普通 system 项；这只是服务端事件的原生显示，不是设备端生成或保证完整 chain-of-thought；真实 endpoint 的 reasoning 事件尚未独立联调；不要夸大为完整思考面板。
- 清楚保留未验证边界：真实 endpoint、签名真机、真实服务端 reasoning 事件/完整联调、iPhone17 Pro Max/iOS27 等。