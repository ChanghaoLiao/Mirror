#!/usr/bin/env python3
"""Package the pinned desktop plus skills into one reproducible public preview ZIP."""
import hashlib
import json
import stat
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESKTOP = ROOT / "dist/Mirror-1.0.0-build10.zip"
TOOLKIT = ROOT / "dist/Mirror-Agent-Toolkit-1.0.0.zip"
OUTPUT = ROOT / "dist/Mirror-Complete-1.0.0-preview.1-macos-arm64.zip"


def package():
    pins = {}
    for line in (ROOT / "plugins/mirror/skills/mirror/scripts/preview.conf").read_text().splitlines():
        if line.startswith("MIRROR_"):
            key, value = line.split("=", 1)
            pins[key] = value.strip("'")
    if hashlib.sha256(DESKTOP.read_bytes()).hexdigest() != pins["MIRROR_PREVIEW_SHA256"]:
        raise SystemExit("Desktop archive does not match preview pins")
    files = {}
    with zipfile.ZipFile(TOOLKIT) as source:
        if source.testzip() is not None:
            raise SystemExit("Invalid toolkit archive")
        for entry in source.infolist():
            name = entry.filename.removeprefix("Mirror-Agent-Toolkit/")
            if not name.endswith("/"):
                files[name] = (source.read(entry), entry.external_attr)
    files.pop("manifest.json", None)  # Complete package has its own hashes below.
    with zipfile.ZipFile(DESKTOP) as source:
        if source.testzip() is not None:
            raise SystemExit("Invalid desktop archive")
        for entry in source.infolist():
            name = entry.filename
            if not name.startswith("Mirror.app/") or ".." in Path(name).parts:
                raise SystemExit("Unexpected desktop entry")
            if not name.endswith("/"):
                files[name] = (source.read(entry), entry.external_attr)
    setup = '''#!/bin/bash
set -euo pipefail
root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
helper="$root/skills/mirror/scripts/mirror.sh"
reply="$(/bin/bash "$helper" status 2>/dev/null)" && { printf '%s\\n' "$reply"; exit 0; }
case "$reply" in
  *'"status":"app_not_found"'*) exec /bin/bash "$root/skills/mirror/scripts/install-preview.sh" --bundle "$root/Mirror.app" "$@";;
  *) printf '%s\\n' "$reply"; exit 1;;
esac
'''
    files["setup.sh"] = (setup.encode(), (stat.S_IFREG | 0o755) << 16)
    readme = """# Mirror 完整测试版

这里同时包含桌面程序、两项Agent技能和Function Calling适配器，不需要另外下载桌面端，不需要编译。

## 普通用户

把Mirror.app拖到“应用程序”后打开，按界面选择本机Codex。只读阅读可以先使用；需要窗口跟随时，由本人授权辅助功能。

本测试版未通过Apple公证。第一次打开可能被macOS拦截；是否允许打开由你本人决定。请参考Apple说明：https://support.apple.com/en-us/102445 。不要关闭Gatekeeper，不要删除quarantine或复制网络上的绕过命令。电脑由单位管理且不允许未公证应用时，不要绕过管理员限制。

## 交给本机Agent

把整个文件夹交给Agent，说：

> 请读取这个文件夹的skills/mirror-setup/SKILL.md，执行根目录setup.sh，安装配套Mirror，再按当前宿主的技能目录注册两项技能。不覆盖已有不同版本。系统首次打开和辅助功能权限由我亲手确认，准备好后检查真实状态。

setup.sh复用已运行或已安装的兼容版；缺少桌面端时校验并安装包内Mirror.app到用户Applications。注册技能使用skills/mirror/scripts/register.sh，位置由宿主决定。它不修改全局模型或API配置。

## 支持范围

Apple Silicon、macOS 14+、本机Codex历史。控制方需要能在你的Mac上运行本地命令；普通云端ChatGPT不能直接操作电脑。小技能包可从同一GitHub Release下载固定桌面ZIP，使用同一套校验和首次打开流程。

Mirror执行层无模型调用；宿主Agent的推理和工具上下文仍可能消耗Token。桌面1.0.0 build10；本完整发行版1.0.0-preview.1。独立项目，非OpenAI官方产品。功能调用只改变阅读窗口，不改写Codex历史。

English: Complete macOS preview containing Mirror.app, skills and local function tools. Apple Silicon/macOS14+ required. This is ad-hoc signed and NOT Apple notarized. The user must complete macOS first-open approval; no security setting is bypassed. Read-only reference source remains local Codex history.
"""
    files["README.md"] = (readme.encode(), (stat.S_IFREG | 0o644) << 16)
    manifest = {"version": "1.0.0-preview.1", "desktop": "1.0.0", "build": "10", "notarized": False, "sha256": {name: hashlib.sha256(data).hexdigest() for name, (data, _) in files.items()}}
    files["complete-manifest.json"] = ((json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode(), (stat.S_IFREG | 0o644) << 16)
    with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, (data, mode) in sorted(files.items()):
            entry = zipfile.ZipInfo("Mirror/" + name, date_time=(2026, 11, 3, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = mode
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    with zipfile.ZipFile(OUTPUT) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Complete ZIP integrity failed")
        for name, (data, _) in files.items():
            if archive.read("Mirror/" + name) != data:
                raise SystemExit("Archive mismatch")
    digest = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
    OUTPUT.with_suffix(".zip.sha256").write_text(f"{digest}  {OUTPUT.name}\n")
    print(json.dumps({"file": OUTPUT.name, "files": len(files), "bytes": OUTPUT.stat().st_size, "sha256": digest, "notarized": False}))


if __name__ == "__main__":
    package()
