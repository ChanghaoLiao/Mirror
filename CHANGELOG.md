# 更新日志 / Changelog

## 0.2.1 — 2026-10-01

首个公开预览版。此前的开发构建没有作为公开版本发布。

- 原生 macOS 只读 Codex 历史参考窗口；同源共享内容，独立阅读。
- 会话搜索、全文查找、复制、字号调整、隐藏恢复和本地窗口状态恢复。
- 中文/英文界面，系统/浅色/深色外观。
- 首次引导区分 Codex 位置、辅助功能权限和绑定；支持先只读使用。
- 有序拼接大分片消息，隔离旧连接事件，修复 EOF 与最后响应的竞争。
- 断连/超时自动恢复，最多三次尝试，完整读取限时45秒。
- 刷新保留内容，完整成功后在当前阅读位置替换；请求合并、独立取消。
- 中英文资料、虚构数据的原生截图、macOS CI 和 Apple Silicon 下载包。

安装包临时签名，尚未公证。没有实时流式镜像、自动更新或其他 Agent 适配。完整宿主切换及部分全屏/Spaces 行为仍需进一步验证。见[验证记录](docs/validation.md)。

## English

First public preview; earlier builds were internal development versions.

- Native read-only Codex reference windows with shared data and independent reading state.
- Conversation selection, Find, copy, font controls, hide/restore and local recovery.
- Chinese/English UI, system/light/dark appearance and optional Accessibility setup.
- Ordered large-response framing, connection-generation isolation and response/EOF handling.
- Up to three attempts for transient failures and a 45-second history deadline.
- Atomic background refresh, current-position preservation, request coalescing and independent cancellation.
- Bilingual documentation, native synthetic-data screenshots, macOS CI and an Apple Silicon download.

Ad-hoc signed, not notarized. Streaming, auto-update and other Agent providers are not included. Full host-following and some full-screen/Spaces behavior require further validation.
