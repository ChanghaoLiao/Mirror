# Contributing

Report reproducible bugs with version, macOS/CLI versions and redacted screenshots. Never attach real chats, account credentials or state databases. Mirror is a native read-only reference tool; keep deterministic operations local and preserve human-priority revisions.

Use full Xcode and Swift6. Run `bash scripts/swift.sh test -Xswiftc -warnings-as-errors`, `bash tests-plugin/run.sh`, and `python3 scripts/test-build.py`. Build with `bash scripts/build.sh`. Signed production packaging remains `scripts/release-macos.sh` and requires your own Developer ID and notary profile.

Standalone packaging: `python3 scripts/package-agent.py`. Complete packaging additionally requires the exact pinned desktop archive in dist; never substitute a fresh ad-hoc build without updating and verifying its pins. Do not commit private state, build caches or conversations.
