# 贡献指南 / Contributing

小范围、可验证的改动最容易审阅。需要 macOS、完整 Xcode、Swift 6 工具链和 Python 3（仅管道测试夹具）。

```sh
bash scripts/swift.sh test -Xswiftc -warnings-as-errors
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
bash scripts/build.sh
```

修正格式可运行 `xcrun swift-format format --in-place --recursive Sources Tests Package.swift`。

## 演示与原生回归

在登录的 macOS 图形会话中运行。独立状态和偏好避免覆盖日常配置：

```sh
MIRROR_PREFS_SUITE=local.mirror.dev.demo MIRROR_STATE_PATH="$PWD/.build/dev-demo.json" \
  dist/Mirror.app/Contents/MacOS/Mirror --demo

MIRROR_PREFS_SUITE=local.mirror.dev.verify MIRROR_STATE_PATH="$PWD/.build/dev-ui.json" \
  dist/Mirror.app/Contents/MacOS/Mirror --verify-ui

MIRROR_PREFS_SUITE=local.mirror.dev.verify MIRROR_STATE_PATH="$PWD/.build/dev-ui.json" \
  dist/Mirror.app/Contents/MacOS/Mirror --verify-recovery

MIRROR_PREFS_SUITE=local.mirror.dev.verify MIRROR_STATE_PATH="$PWD/.build/dev-refresh.json" \
  dist/Mirror.app/Contents/MacOS/Mirror --verify-refresh

MIRROR_PREFS_SUITE=local.mirror.dev.verify MIRROR_STATE_PATH="$PWD/.build/dev-ocean.json" \
  dist/Mirror.app/Contents/MacOS/Mirror --verify-ocean

MIRROR_PREFS_SUITE=local.mirror.dev.verify MIRROR_STATE_PATH="$PWD/.build/dev-setup.json" \
  dist/Mirror.app/Contents/MacOS/Mirror --verify-setup
```

夹具不能替代真实 Codex 或系统授权验收。真实只读读取使用 `--verify-adapter` / `--verify-reliability`，需要有效的本机 Codex 路径。不要上传包含真实数据的调试输出。

`bash scripts/capture-release.sh` 单独编译生产 AppKit 类，用虚构数据创建真实窗口，默认输出到 `.build/release-captures/images`，不打开 Codex 历史。OS 截图需要启动它的应用有屏幕录制权限；这仅为开发截图需要，普通 Mirror 阅读不需要。

## 改动约定

- 保持只读 allowlist，不启动、恢复、复制 Agent 任务或调用模型。
- 共享源数据与独立视图状态分离；不让一个窗口控制其他窗口的生命周期。
- 保留现有按钮、快捷键、阅读锚点、中英文和浅深色状态。
- 不自动打开附件、下载远程图片或增加磁盘正文缓存。
- PR 说明具体问题、最终行为、验证方式及未覆盖的范围。区分夹具结果与真实平台验收。
- Issue 和截图只使用虚构或已脱敏数据。

提交 PR 表示愿意按本项目 MIT 许可提供贡献。

## English

Keep changes small and explain the problem, resulting behavior and validation. Full Xcode, Swift 6 and Python 3 for pipeline fixtures are required. Run the test, lint and build commands above. Native regressions require a logged-in macOS graphical session; isolate state and preferences.

Preserve read-only methods, shared sources with independent views, all controls, keyboard access, reading anchors and both themes/languages. Do not introduce Agent task mutations, model calls, automatic attachment access, remote image downloads or disk conversation caches. Distinguish fixtures from real Codex and OS permission validation. Use synthetic or redacted data in issues. Contributions are provided under MIT.
