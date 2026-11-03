# Mirror · Agent Tools

Keep a local Codex conversation beside your work in a separate, read-only window. The Agent can open it, find a passage, refresh, arrange it and bind it to a Codex host window. You can always take over with the desktop controls.

This package contains two skills: **Mirror references** and **Set up Mirror**, plus an optional strict function-call adapter. It is an independent project by Changhao Liao, not an OpenAI product or endorsement. A standalone toolkit is also available without a plugin manifest or official marketplace requirement.

Mirror operations run deterministic local code without calling a model. The host Agent can still consume tokens for reasoning, skill instructions and tool results. No Mirror API key or hosted service is introduced. The shell route needs only macOS tools; the optional function route needs Python 3.9+ with no third-party dependencies. See [function calling](skills/mirror/references/function-calling.md) and [schemas](skills/mirror/references/function-tools.json).

## Requirements

- An Agent with local command execution on your Mac; the conversation source remains Codex history. Other controlling hosts may need integration and are not all independently certified.
- Apple Silicon, macOS 14+, and the separately installed **Mirror 1.0.0+** desktop app.
- Local Codex history and a working Codex executable selected in Mirror.

Plugin 1.0.0 requires the native command service in Mirror 1.0.0 or later. On first use the Agent can download and install the fixed public desktop release into your Applications folder, then start it. The installer checks a pinned SHA256, Developer ID identity and Apple notarization; replacing an existing app requires your confirmation and preserves a backup. Until that signed public release is available, installation reports `release_unavailable`. Ordinary reading needs no Accessibility permission; following a host window does. macOS permission grants remain a human action.

## Use

Ask “Keep this conversation beside my work,” “Find the product plan in that reference,” or “Refresh and move the Mirror window to the right.” The Agent first reads a live state snapshot, then sends the requested operation with its revision. Opening the same conversation reuses its existing reference by default. A new independent copy is created only when requested.

The native controls cover opening, duplicating, closing, hiding/showing, refresh/cancel, find, copying the current message, font size, geometry and host binding. Loading and binding are reported separately: an open window can still be loading or waiting for a host. Binding follows a Codex **window**, not an individual chat route inside that window. Conversation lookup by title uses the host's available history tools; this plugin is not an independent history search service.

Human interactions invalidate earlier Agent commands. Mirror's menu can pause Agent control; only the human can resume it. A stale or paused command is rejected rather than overwriting the human's choice. After a timeout the Agent inspects the current state instead of repeating an operation blindly.

## Local data

Helpers use only macOS tools and the exact verified Mirror app executable. Command requests travel locally as JSON; responses contain window metadata and conversation/message IDs, not conversation bodies. Copying puts the selected message on the local clipboard only when requested. The plugin never writes Codex history, starts AI tasks, grants OS permissions or exports history. It has no hosted service and cannot operate a Mac from a cloud-only session. The host's history lookup tools follow that host's own privacy settings.

Screenshots use synthetic content in the real native UI. They illustrate the companion app and do not imply plugin directory approval.

[Project](https://github.com/ChanghaoLiao/Mirror) · [Privacy](https://github.com/ChanghaoLiao/Mirror/blob/main/docs/privacy.en.md) · [Support](https://github.com/ChanghaoLiao/Mirror/issues)

MIT license; see LICENSE.

## 中文

在具备本机执行能力的 Agent 中说“把这个 Codex 对话放在旁边”，Agent 可以打开或复用 Mirror 窗口，并操作查找、刷新、取消读取、复制当前消息、字号、位置、显隐和绑定。默认复用同一对话已有的窗口，避免重复打开。

**人操作优先。** 你点击修改后，Agent 之前拿到的旧状态就不能覆盖你的选择；你也可以在 Mirror 菜单暂停 Agent，只有你能恢复。系统权限仍需你亲手授权。绑定关联的是 Codex 窗口，不是窗口内某个聊天标签。

插件 1.0.0 需要 Mirror 桌面版 **1.0.0+**、M 系列 Mac、macOS 14+ 和本机 Codex。首次使用时 Agent 可下载、校验、安装并启动正式桌面版；替换旧版需确认，并保留备份。正式签名包未公开时会准确提示暂不可用。打开成功、内容加载完成、绑定成功会分别检查。没有云端服务，不改写 Codex 对话，不自动授予系统权限；普通云端 ChatGPT 无法控制 Mac。
