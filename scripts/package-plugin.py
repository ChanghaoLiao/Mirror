#!/usr/bin/env python3
"""Validate and package the explicit public Mirror plugin file set. No publishing."""
import hashlib
import json
import plistlib
import re
import stat
import struct
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugins" / "mirror"
FILES = (
    "plugin.json", ".codex-plugin/plugin.json", "LICENSE", "README.md",
    "assets/icon.svg", "assets/multiwindow-light.png", "assets/find.png",
    "skills/mirror/SKILL.md", "skills/mirror/agents/openai.yaml",
    "skills/mirror/scripts/mirror.sh", "skills/mirror/scripts/mirror.js",
    "skills/mirror/scripts/install.sh", "skills/mirror/scripts/release.conf",
    "skills/mirror/scripts/functions.py",
    "skills/mirror/scripts/register.sh",
    "skills/mirror/scripts/install-preview.sh", "skills/mirror/scripts/preview.conf",
    "skills/mirror/references/commands.md",
    "skills/mirror/references/function-calling.md", "skills/mirror/references/function-tools.json",
    "skills/mirror-setup/SKILL.md", "skills/mirror-setup/agents/openai.yaml",
)


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def package():
    actual = {p.relative_to(PLUGIN).as_posix() for p in PLUGIN.rglob("*") if p.is_file()}
    require(actual == set(FILES), f"Unexpected or missing plugin files: {sorted(actual ^ set(FILES))}")
    require(not any(p.is_symlink() for p in PLUGIN.rglob("*")), "Symlinks are not allowed in the plugin")
    manifest = json.loads((PLUGIN / "plugin.json").read_text())
    compat = json.loads((PLUGIN / ".codex-plugin/plugin.json").read_text())
    app_version = plistlib.loads((ROOT / "scripts" / "Info.plist").read_bytes())["CFBundleShortVersionString"]
    require(manifest["name"] == "mirror", "Unexpected plugin identity")
    require(re.fullmatch(r"\d+\.\d+\.\d+", manifest["version"]), "Use a release version")
    require(manifest["version"] == app_version, "Desktop and plugin versions must match")
    require(manifest["$schema"] == "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json", "Wrong schema")
    extension = manifest["extensions"]["com.openai"]
    require(set(extension) == {"interface", "onboardingSkill", "publication"}, "Unexpected plugin components")
    interface = extension["interface"]
    for key in ("name", "version", "description", "author", "homepage", "repository", "license", "keywords"):
        require(compat[key] == manifest[key], f"Compatibility identity mismatch: {key}")
    require(compat["interface"] == interface, "Compatibility listing mismatch")
    require(compat["skills"] == "./skills/", "Missing skills entrypoint")
    require(compat["extensions"]["com.openai"] == {k: extension[k] for k in ("onboardingSkill", "publication")}, "Compatibility metadata mismatch")
    for key, limit in (("displayName", 30), ("shortDescription", 30), ("longDescription", 4000), ("developerName", 80)):
        require(isinstance(interface[key], str) and 0 < len(interface[key]) <= limit, f"Invalid listing field: {key}")
    require(len(interface["defaultPrompt"]) <= 3 and all(0 < len(p) <= 128 for p in interface["defaultPrompt"]), "Invalid prompts")
    for key in ("websiteURL", "supportURL", "privacyPolicyURL"):
        require(interface[key].startswith("https://github.com/ChanghaoLiao/Mirror"), f"Unexpected public URL: {key}")
    references = [interface["logo"], interface["composerIcon"], extension["onboardingSkill"], *interface["screenshots"]]
    require(all(p.startswith("./") and p[2:] in FILES for p in references), "A referenced asset is missing")
    svg = ET.fromstring((PLUGIN / "assets/icon.svg").read_bytes())
    require(svg.attrib.get("viewBox") == "0 0 512 512", "Icon must have a square viewBox")
    for name in ("assets/multiwindow-light.png", "assets/find.png"):
        data = (PLUGIN / name).read_bytes()
        require(data[:8] == b"\x89PNG\r\n\x1a\n", "Invalid screenshot")
        width, height = struct.unpack(">II", data[16:24])
        require(0 < width <= 4096 and 0 < height <= 4096 and len(data) <= 5 * 1024 * 1024, "Oversized screenshot")
    for name in FILES:
        if name.endswith(".png"):
            continue
        text = (PLUGIN / name).read_text()
        require(not re.search(r"/Users/|/private/var/|/var/folders/|gh[op]_[A-Za-z0-9]{20}|sk-[A-Za-z0-9]{20}", text), f"Private data marker in {name}")
    for name in ("mirror", "mirror-setup"):
        text = (PLUGIN / "skills" / name / "SKILL.md").read_text()
        require(text.startswith("---\n") and f"\nname: {name}\n" in text and "\ndescription: " in text, f"Invalid skill {name}")
        for target in re.findall(r"\]\(([^)]+)\)", text):
            if "://" not in target:
                resolved = (PLUGIN / "skills" / name / target).resolve()
                require(resolved.is_relative_to(PLUGIN) and resolved.is_file(), f"Broken skill reference: {target}")
    output = ROOT / "dist" / f"Mirror-OpenAI-plugin-{manifest['version']}.zip"
    output.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in sorted(FILES):
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 1, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if name.endswith(".sh") else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, (PLUGIN / name).read_bytes())
    with zipfile.ZipFile(output) as archive:
        require(archive.testzip() is None and set(archive.namelist()) == set(FILES), "ZIP integrity failed")
        for name in FILES:
            require(archive.read(name) == (PLUGIN / name).read_bytes(), "ZIP source mismatch")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".sha256").write_text(f"{digest}  {output.name}\n")
    record = {"plugin_version": manifest["version"], "files": len(FILES), "bytes": output.stat().st_size,
              "sha256": digest, "publication_status": "prepared_not_uploaded",
              "file_sha256": {name: hashlib.sha256((PLUGIN / name).read_bytes()).hexdigest() for name in FILES}}
    (ROOT / ".build").mkdir(exist_ok=True)
    (ROOT / ".build/plugin-package-manifest.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({k: record[k] for k in ("plugin_version", "files", "bytes", "sha256", "publication_status")}))


if __name__ == "__main__":
    package()
