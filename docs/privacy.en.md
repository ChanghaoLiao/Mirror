# Privacy and local data

[简体中文](privacy.md) · [Home](../README.en.md)

Mirror has no telemetry, upload service, built-in account or model calls. It starts the local Codex App Server with analytics disabled and only allows initialization, listing and reading history. Codex owns its account, configuration, history and networking; this is not a guarantee about all Codex behavior.

## Stored data

Conversation bodies stay in memory and are shared by source ID, without a Mirror disk cache. Inactive snapshots are limited to 8 entries and 32MiB of source text; active sources are excluded. Closing the relevant references or quitting Mirror releases this in-memory content. This is not a total process memory limit.

`~/Library/Application Support/Mirror/state.json` holds window geometry, font settings, conversation IDs, message/character anchors, workspace metadata and host titles. These identifiers can reveal which histories you viewed. **Do not upload the file to an issue.** Metadata remains until the user closes the corresponding references, resets state, or uninstalls and removes the file; Mirror keeps no cloud copy. Writes are atomic with mode 0600; corrupt/unsupported files are preserved and saving stops for that run.

Appearance/language, the selected Codex path and first-run completion are kept in macOS UserDefaults until the user resets preferences or removes the local data. Image previews remain in the reference's memory, without stored preview copies. Closing references releases unneeded data.

Mirror does not send conversations, the metadata above, or usage analytics to the maintainer, advertisers, data brokers or other third parties. Links explicitly clicked by the user are handled by the system browser. Content a user submits to GitHub Issues is processed by GitHub under its own policies.

## Permissions and attachments

Optional Accessibility exposes host window identities/titles and best-effort selected text for binding, visibility and navigation. The user grants permission; manual reading works without it.

Mirror does not automatically probe paths in text, open attachments or fetch remote images. Normal reading needs no Screen Recording or Full Disk Access. Links you click are opened by the system.

## Feedback and removal

Use synthetic data or sufficiently redacted screenshots, checking titles, selections, menus, file paths and desktop backgrounds. Do not include accounts, credentials, real deep links or raw Codex history.

Quit Mirror before removing its `state.json` to reset references or deleting the app to uninstall. Neither deletes Codex history. UserDefaults preferences and the onboarding marker may remain. Report security issues privately through [SECURITY.md](../SECURITY.md).
