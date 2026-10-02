# 安装与首次配置

[English](installation.en.md) · [返回首页](../README.md)

## 下载版

要求 Apple Silicon（M系列芯片）和 macOS14或更新版本。下载版不需要 Xcode、Node、Python或 API Key，但需要已安装的 Codex 和它的本地历史。

1. 打开 [v0.2.1 Release](https://github.com/ChanghaoLiao/Mirror/releases/tag/v0.2.1)。
2. 下载 `Mirror-0.2.1-macos-arm64.zip` 和 `SHA256SUMS.txt`，保存到同一个文件夹。
3. 可在该文件夹的终端校验：`shasum -a 256 -c SHA256SUMS.txt`。结果应为 `OK`。这验证下载文件一致性，不代表 Apple 公证。
4. 解压 ZIP，把 `Mirror.app` 移到固定位置，例如“应用程序”，然后打开。不要在多个文件夹之间来回移动已经授权的应用。
5. Mirror 是菜单栏应用，寻找右上方 **◧** 图标。

## macOS 阻止打开时

这个公开预览包采用临时签名，**没有 Developer ID 签名或 Apple 公证**。通过解压、签名校验和本机启动测试，不等于通过了另一台电脑的 Gatekeeper 检查。

确认文件确实来自本仓库，且你愿意信任它之后，可按 [Apple 官方说明](https://support.apple.com/en-us/102445)查看“系统设置 → 隐私与安全性”是否提供“仍要打开”。系统拒绝提供该选项时，请从源码构建或暂缓使用。不要关闭全局 Gatekeeper，也不要忽略“包含恶意软件”或“应用已损坏”的提示；请报告具体提示。

## 选择 Codex

“连接本机 Codex”选择的是名为 **codex** 的可执行文件，不是某个聊天窗口、对话文件或 API Key。Mirror 启动一个本地只读 App Server 来读取已有历史。

安装目录会随 Codex 版本变化，自动查找不保证覆盖所有打包结构。点击“选择 Codex…”；文件选择器里可以按 **⇧⌘G** 输入完整路径。某些桌面版本的示例：

```text
/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
```

旧打包结构可能在 `ChatGPT.app/Contents/Resources/codex` 或 `Codex.app/Contents/Resources/codex`；独立安装也可能位于 `/opt/homebrew/bin/codex` 或 `/usr/local/bin/codex`。请选择你电脑上实际存在的可执行文件。示例路径不代表必须安装名为 ChatGPT 的宿主。

开发时可用 `MIRROR_CODEX_PATH` 指定路径。选择完成后刷新参考窗口重连。当前验证的 CLI 版本为0.159.0。

## 权限与绑定

| 配置 | 用途 | 是否必须 |
| --- | --- | --- |
| Codex 可执行文件 | 读取本地历史 | 是，演示模式除外 |
| Mirror 辅助功能 | 识别、跟随宿主窗口及所选文字 | 否，手动阅读不需要 |
| 绑定 Codex 窗口 | 确定一组参考要跟随哪个窗口 | 仅窗口跟随需要 |

需要跟随时，在“系统设置 → 隐私与安全性 → 辅助功能”里开启 **Mirror**，返回设置引导重新检查，然后点击一次 Codex 窗口，选择 **◧ → 绑定 Codex 窗口**。此处不是给 Figma、浏览器或其他同名安装包授权。

开发版重编译或更新改变临时签名后，macOS可能要求重新授权；如果系统列表有多个 Mirror，先核实应用位置。[权限排查](troubleshooting.md)说明如何处理。普通阅读不需要屏幕录制或完整磁盘访问。

## 源码构建与更新

完整 Xcode、Swift6 工具链和 macOS：运行 `bash scripts/build.sh`。测试还需要 Python3 夹具。完整命令见[贡献指南](../CONTRIBUTING.md)。

没有自动更新。更新前退出 Mirror，将新版本放回原位置；本地窗口状态保留，必要时重新授权。卸载时退出并删除应用；可选择清理[隐私说明](privacy.md)里的 Mirror 状态文件，这不会删除 Codex 历史。
