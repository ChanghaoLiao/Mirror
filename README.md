# Mirror

**把 AI 对话里的参考内容，留在工作旁边。**

[English](README.en.md) · [下载 v0.2.1](https://github.com/ChanghaoLiao/Mirror/releases/tag/v0.2.1) · [使用指南](docs/usage.md) · [问题反馈](https://github.com/ChanghaoLiao/Mirror/issues)

![同一对话的需求和发布清单分别留在两个原生窗口里](docs/screenshots/multiwindow-light.png)

你在 Codex 中继续工作，Mirror 把之前的需求、解释或检查清单放到独立参考窗口里。复制一个窗口，就能同时阅读同一段对话的另一处内容。每个窗口记住自己的阅读位置、字号和大小。

Mirror 使用 Swift 和 AppKit，是原生 macOS 工具。它只读取已有的本地 Codex 对话，不发送消息、不生成回答，也不会创建或复制 Agent 任务。

> **首个公开预览版 · v0.2.1**
> 下载包适用于 **Apple Silicon（M 系列芯片）、macOS 14 或更新版本**。安装包采用临时签名，**尚未进行 Apple 公证**；macOS 可能阻止首次打开。请先阅读[安装说明](docs/installation.md)。下载版不需要 Xcode；从源码构建需要完整 Xcode 和 Swift 6 工具链。

## 它解决什么问题

长对话里，往上找需求、往下看实现，再回去找结论，很容易打断思路。Mirror 让这些内容各有一个固定位置：

- 一个窗口保留需求，另一个查看实现或检查清单；也可以分别查看不同会话。
- 窗口独立滚动、切换和关闭；对话数据共享。
- 刷新时继续阅读旧内容，完整更新成功后再替换，保持你当时正在看的位置。

所有截图来自实际运行的原生窗口，使用明确标注的虚构演示内容。多窗口图片的背景仅用于排布展示；未公开真实对话、学习材料或桌面信息。

## 五分钟开始使用

1. 从 [Release](https://github.com/ChanghaoLiao/Mirror/releases/tag/v0.2.1) 下载 `Mirror-0.2.1-macos-arm64.zip`，解压后把 `Mirror.app` 放到固定位置，例如“应用程序”。
2. 打开 Mirror。菜单栏显示 **◧**，首次启动会显示“初始设置与权限”。
3. **连接本机 Codex**是找到已安装的 `codex` 可执行文件，用它读取本地历史，不是登录新账号或连接云端。自动查找失败时，[手动选择 Codex](docs/installation.md#选择-codex)。
4. 可以选择“先只读使用”，无需辅助功能权限。需要窗口跟随时，在“系统设置 → 隐私与安全性 → 辅助功能”中开启 **Mirror**。
5. 从 **◧ → 打开参考窗口**，或按 **⇧⌘M**。点击“切换会话”，选择想看的对话。
6. 按 **⌘D** 复制参考窗口，滚到另一处。继续在 Codex 中提问和工作。

**绑定**是告诉 Mirror“这些参考窗口要跟着哪个 Codex 窗口”。授权后，先点击目标 Codex 窗口，再从 **◧ → 绑定 Codex 窗口**。**未绑定不等于没有权限**，也不妨碍手动选择和阅读。

## 主要操作

| 想做什么 | 操作 |
| --- | --- |
| 打开参考窗口 | 菜单栏 ◧，或 ⇧⌘M |
| 换一段对话 | “切换会话”；支持搜索标题和加载更多 |
| 同时看两处内容 | ⌘D，或 ••• → 复制参考窗口 |
| 找正文里的文字 | ⌘F；Return 跳到下一个匹配，清除返回之前的位置 |
| 读取最新历史 | ⌘R；保留旧内容，后台更新，临时连接故障自动重试 |
| 复制内容 | 选中文字后 ⌘C；或 ••• → 复制当前完整消息 |
| 调整字号 | ••• → 放大字号 / 缩小字号，仅影响当前窗口 |
| 暂时收起 | ••• → 隐藏参考窗口；◧ → 恢复隐藏的参考窗口 |
| 关闭当前参考 | ⌘W；其他窗口继续保留 |
| 外观和语言 | ••• → 外观与语言；跟随系统 / 浅色 / 深色，中文 / English |
| 重新配置 | ◧ → 设置与权限 / 选择 Codex 可执行文件 |

查找和会话面板覆盖正文，不会挤窄阅读区域。Escape 或点击面板外侧返回阅读。使用原生标题栏和窗口边缘来移动、调整大小。菜单栏还有“从所选文字打开”，详见[使用指南](docs/usage.md)。

## 看看实际界面

| 会话内查找 | 外观与语言 |
| --- | --- |
| ![搜索演示对话中的发布内容](docs/screenshots/find.png) | ![系统、浅色、深色和中英文设置](docs/screenshots/preferences.png) |

| 会话选择 | 首次权限引导 |
| --- | --- |
| ![按标题选择已有会话](docs/screenshots/conversations.png) | ![Codex 位置、窗口跟随权限和跟随窗口说明](docs/screenshots/setup.png) |

[查看深色多窗口截图](docs/screenshots/multiwindow-dark.png)。截图里的权限状态为演示状态，不代表这台电脑的实际授权。

## 隐私和运行方式

- 通过本机 Codex CLI 的官方 App Server 读取历史，只允许初始化、列出和读取会话。
- Mirror 没有遥测、上传服务、模型调用或内置账号；启动本地 App Server 时关闭其 analytics。Codex 自身的账号、配置及行为仍由 Codex 管理。
- 对话正文只保存在内存中，不由 Mirror 缓存到磁盘。窗口位置、会话 ID、阅读位置和宿主标题等元数据保存在本地。
- 不自动读取附件路径、不下载远程图片。预览图片需要你在系统文件选择器中明确选择。
- 普通阅读不需要屏幕录制、完整磁盘访问或 API Key。辅助功能仅用于识别、跟随 Codex 窗口和尽力读取所选文字。

详细范围见[隐私说明](docs/privacy.md)；授权与绑定排查见[常见问题](docs/troubleshooting.md)。

## 当前支持范围

目前支持 **本地 Codex 历史**。真实读取和刷新验证使用 Codex CLI **0.159.0**、Apple Silicon、macOS 26.4.1。最低部署版本是 macOS 14；尚未完整验证每个系统、CLI 版本和窗口组合。

- 显示历史快照，手动刷新；当前回答的流式变化不会实时镜像。
- 没有官方“当前屏幕可见消息”接口。“从所选文字打开”是尽力而为的辅助功能能力；也支持手动选择和明确 ID 的链接。
- 基础 Markdown、代码和表格可阅读；复杂嵌套 Markdown、语法高亮和自动图片加载有限或未实现。
- 超大单个文本块仍可能影响布局，全文查找也可能影响响应时间。
- 宿主窗口改名、同名窗口或部分全屏/Spaces 组合可能需要重新绑定；完整真实宿主切换流程仍需进一步平台验证。
- 暂不支持 Windows、Linux、Claude Code、Cursor、OpenCode，也没有自动更新或正式公证。

## 可靠性验证

v0.2.1 修复了大分片响应的接收顺序和断连恢复。断连或超时最多三次尝试，间隔 250/750ms，完整读取总限时45秒；取消立即停止，格式错误或请求拒绝不会盲目重试。

**29 项单元测试通过**，覆盖大于5MiB的中文分片、断连、超时、取消和并发；原生窗口回归覆盖独立阅读、查找、关闭释放、恢复、首次引导和后台刷新。同一条真实历史连续 **20次完整读取＋20次刷新**成功。记录仅含耗时和条目数量，不含标题、ID或正文。

[验证记录与边界](docs/validation.md) · [读取/刷新技术说明](docs/reliability/README.md) · [架构](docs/architecture.md)

## 从源码构建

需要 macOS、完整 Xcode（含 XCTest）和 Swift 6 工具链。没有第三方运行时依赖；管道测试的 Python 3 仅用于开发夹具。

```sh
git clone https://github.com/ChanghaoLiao/Mirror.git
cd Mirror
bash scripts/swift.sh test -Xswiftc -warnings-as-errors
bash scripts/build.sh
open dist/Mirror.app
```

输出是 `dist/Mirror.app` 和 `dist/Mirror.zip`。查看[贡献指南](CONTRIBUTING.md)了解演示运行和回归检查。

## 反馈与许可

请提交 [Issue](https://github.com/ChanghaoLiao/Mirror/issues)，附版本、复现步骤和脱敏截图。请勿粘贴真实对话、账号信息或状态文件。安全问题请按[安全说明](SECURITY.md)私下报告。

由 [ChanghaoLiao](https://github.com/ChanghaoLiao) 维护，采用 [MIT License](LICENSE)。Mirror 是独立项目，与 OpenAI 不存在官方隶属或背书关系。
