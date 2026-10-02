# Troubleshooting

[简体中文](troubleshooting.md) · [Home](../README.en.md)

| Symptom | First action |
| --- | --- |
| Download will not open | Read the [notarization limitation](installation.en.md), verify source/checksum; do not disable system protection globally |
| No Dock icon | Look for **◧** in the menu bar |
| Codex not found | Choose the actual executable, not a chat window; see [path examples](installation.en.md#choose-codex) |
| Authorized but unbound | Permission and host choice are separate; focus Codex, then choose Bind to Codex window |
| System setting enabled but Mirror says unauthorized | Quit Mirror, confirm the app/version/location matches the permission entry, then reopen setup and Check again |
| References disappear | Host following may hide the current group; return to the host or open/restore through ◧ |
| Conversation missing | Use the same local Codex installation, search titles and load more; web-only cloud conversations are not local history |
| Refresh fails | Old content stays. Transient failures retry up to three times; after the45-second budget, check the CLI path and retry once if needed |
| Malformed response or rejection | Retrying cannot fix incompatibility; report Mirror/CLI versions and error type without private data |
| Selected text cannot be located | The host may not expose a selection or matching may be ambiguous; use manual selection and Find |
| Image placeholder | Choose the image explicitly; attachment paths are not opened automatically |
| Permission lost after update | Ad-hoc signatures can change; keep a stable install location and verify the matching permission entry |

Do not delete unknown apps or permission entries. First verify the path, then handle only the corresponding old Mirror entry; source code, installers and Codex history do not need deletion.

For persistent read failures, include Mirror, macOS and Codex CLI versions, initial read vs refresh, exact error and reproduction steps. Exclude conversation bodies and IDs. Keep existing content and continue work in Codex while investigating.
