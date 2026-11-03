#!/usr/bin/env python3
"""Build a standalone skill/function toolkit. No upload, install or model calls."""
import hashlib
import json
import re
import stat
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugins/mirror"
VERSION = "1.0.0"
FILES = (
    "skills/mirror/SKILL.md", "skills/mirror/agents/openai.yaml",
    "skills/mirror/scripts/mirror.sh", "skills/mirror/scripts/mirror.js",
    "skills/mirror/scripts/install.sh", "skills/mirror/scripts/release.conf",
    "skills/mirror/scripts/functions.py", "skills/mirror/references/commands.md",
    "skills/mirror/scripts/register.sh",
    "skills/mirror/scripts/install-preview.sh", "skills/mirror/scripts/preview.conf",
    "skills/mirror/references/function-calling.md", "skills/mirror/references/function-tools.json",
    "skills/mirror-setup/SKILL.md", "skills/mirror-setup/agents/openai.yaml", "LICENSE",
)


def package():
    payload = {}
    for name in FILES:
        path = PLUGIN / name
        if path.is_symlink() or not path.is_file():
            raise SystemExit("Missing or symbolic toolkit file: " + name)
        payload[name] = path.read_bytes()
    payload["README.md"] = """# Mirror · Agent Toolkit 1.0.0

把 Codex 的历史参考留在工作旁边。独立的本地 Agent 小技能与 Function Calling 工具，不需要官方插件目录。

**配套测试版**：小技能包可按固定校验值从GitHub下载桌面端；也可选择包含Mirror.app的完整包。当前桌面端为ad-hoc签名测试版，未通过Apple公证，首次打开须由本人在macOS中确认。

## 交给你的 Agent

把这个文件夹交给具备 Mac 本机执行能力的 Agent，发送：

> 请阅读这个文件夹里的 skills/mirror/SKILL.md 和需要时的 skills/mirror-setup/SKILL.md，检查我本机的 Mirror 状态。保留我的人工操作优先权，不新建多余窗口。准备好后，按我的要求把指定 Codex 历史放在旁边。

请用各文件的实际绝对路径。Agent确认宿主使用的技能目录后，可执行 `bash <本包>/skills/mirror/scripts/register.sh --target <宿主技能目录的绝对路径>`，一次安装两项技能。相同版本重复运行直接复用；存在不同版本时停止，不覆盖。让宿主重新发现技能，部分宿主需要重开会话。这个ZIP本身不会自动注册工具；无需让用户亲自输入终端命令。

## 条件

Apple Silicon、macOS 14+、单独安装的 Mirror 桌面端1.0.0+，以及本机 Codex 历史。技能的 shell 路径仅需系统自带工具。已有桌面端直接复用。本包不包含桌面应用、桌面端源码或用户对话；技能和适配器脚本源文件随包提供。测试版安装器校验固定SHA256和应用CDHash；正式安装器继续要求Developer ID与Apple公证，互不降级。

普通云端 ChatGPT 无本机执行器时无法控制 Mac。控制方可以是其他本机 Agent，读取数据仍是 Codex 历史；不宣称所有宿主均已端到端认证。

## 给接入开发者

- 入口：skills/mirror/SKILL.md。
- 函数文档：skills/mirror/references/function-calling.md。
- 15个严格函数schema：skills/mirror/references/function-tools.json。
- 调用适配器：skills/mirror/scripts/functions.py。需要Python 3.9+，无pip依赖。
- `python3 <adapter> --tools` 只导出schema；`python3 <adapter> mirror_status` 从stdin读取JSON参数，例如 {"launch":false,"request_id":null}。
- 先status，再用真实ID和最新revision执行一次操作。人退出时不重开；冲突或暂停时停止；不确定结果不盲目重试。

Mirror执行这些操作不调用大模型，也不需要API Key。宿主Agent的推理、技能上下文与回执仍可能消耗Token。独立项目，非OpenAI官方产品；本包未发布至官方目录。

English: Local skills and strict function-call schemas for read-only Mirror references. A local Mac executor and separately installed Mirror 1.0.0+ are required. The controller may be another Agent; conversation data remains Codex-only. No embedded model calls or hosted service. Host reasoning and tool context can still consume tokens. See the English function-calling reference above.
""".encode()
    payload["开始使用.txt"] = """Mirror 使用步骤

1. 解压整个文件夹，不要只拷贝SKILL.md。
2. 将文件夹交给能操作你这台Mac的Agent。
3. 发这句话：

请帮我配置并使用这个文件夹中的Mirror。先读README.md和skills/mirror-setup/SKILL.md，检查有没有已安装的兼容桌面端；如果需要长期安装技能，请按当前宿主确认技能目录，使用随包register.sh一次安装两项技能。不要覆盖已有不同版本，不要为了测试打开我的私人对话。准备好后告诉我实际状态。

已有Mirror：技能安装不需要API Key、Node或Python。部分宿主需要重新发现技能或重开会话。
未安装Mirror：让Agent按mirror-setup技能下载固定GitHub测试版，或在完整包内执行setup.sh安装配套Mirror.app。安装器会校验文件。当前测试版未Apple公证，macOS首次打开确认必须你亲手完成；随后再检查Mirror状态。不要关闭系统保护或自行编译。

只支持M系列Mac、macOS 14+，历史来源仍是本机Codex。普通云端ChatGPT无法直接控制电脑。需要跟随窗口时，macOS辅助功能权限须由你亲手授权；普通阅读可先只读使用。
""".encode()
    for name, data in payload.items():
        text = data.decode("utf-8")
        if re.search(r"/Users/|/private/var/|/var/folders/|gh[op]_[A-Za-z0-9]{20}|sk-[A-Za-z0-9]{20}", text):
            raise SystemExit("Private data marker: " + name)
        if name.endswith("SKILL.md"):
            for target in re.findall(r"\]\(([^)]+)\)", text):
                if "://" not in target:
                    resolved = (PLUGIN / name).parent.joinpath(target).resolve()
                    if not resolved.is_relative_to(PLUGIN) or resolved.relative_to(PLUGIN).as_posix() not in FILES:
                        raise SystemExit("Broken skill reference: " + target)
    schemas = json.loads(payload["skills/mirror/references/function-tools.json"])
    if len(schemas) != 15 or len({t["name"] for t in schemas}) != 15:
        raise SystemExit("Expected all 15 native tool functions")
    manifest = {"name": "mirror-agent-toolkit", "version": VERSION, "desktopMinimum": "1.0.0", "kind": "local-skills-and-function-calling", "modelCalls": False, "hostedService": False, "officialListing": False, "file_sha256": {name: hashlib.sha256(data).hexdigest() for name, data in payload.items()}}
    payload["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    output = ROOT / "dist" / f"Mirror-Agent-Toolkit-{VERSION}.zip"
    output.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in sorted(payload.items()):
            entry = zipfile.ZipInfo("Mirror-Agent-Toolkit/" + name, date_time=(2026, 11, 2, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | (0o755 if name.endswith((".sh", ".py")) else 0o644)) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, data)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None or len(archive.namelist()) != len(payload):
            raise SystemExit("Toolkit archive verification failed")
        for name, data in payload.items():
            if archive.read("Mirror-Agent-Toolkit/" + name) != data:
                raise SystemExit("Archive source mismatch")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".zip.sha256").write_text(f"{digest}  {output.name}\n")
    print(json.dumps({"file": output.name, "files": len(payload), "bytes": output.stat().st_size, "sha256": digest, "published": False}))


if __name__ == "__main__":
    package()
