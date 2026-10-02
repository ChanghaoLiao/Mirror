# Installation and setup

[简体中文](installation.md) · [Home](../README.en.md)

## Download

Requires Apple Silicon and macOS 14 or later. The app does not require Xcode, Node, Python or an API key to run. You do need an installed Codex executable and local history.

1. Open the [v0.2.1 Release](https://github.com/ChanghaoLiao/Mirror/releases/tag/v0.2.1).
2. Download `Mirror-0.2.1-macos-arm64.zip` and `SHA256SUMS.txt` into the same directory.
3. Optionally run `shasum -a 256 -c SHA256SUMS.txt` there. Expect `OK`. This checks file consistency, not notarization.
4. Extract the ZIP and move `Mirror.app` to a stable location such as Applications before opening or granting permissions.
5. Mirror is a menu-bar app; look for **◧**.

## If macOS blocks launch

This preview is ad-hoc signed, **without Developer ID signing or Apple notarization**. Local extraction, signature checks and launch tests do not certify another computer's Gatekeeper behavior.

After verifying the source and deciding to trust it, follow [Apple's official instructions](https://support.apple.com/en-us/102445) to see whether System Settings → Privacy & Security offers **Open Anyway**. If it does not, build from source or defer installation. Do not disable Gatekeeper globally or ignore malware/damaged-app warnings; report the exact message instead.

## Choose Codex

**Connect Codex** selects an executable named **codex**, not a chat window, conversation file or API key. Mirror starts a local read-only App Server for existing history.

Paths vary by version and packaging, so discovery may not find every installation. Click **Choose Codex…**, then **⇧⌘G** in the file picker to enter an actual executable path. One desktop packaging example is:

```text
/Applications/ChatGPT.app/Contents/Resources/codex-cli/Codex CLI.app/Contents/MacOS/codex
```

Older packages may use `ChatGPT.app/Contents/Resources/codex` or `Codex.app/Contents/Resources/codex`; standalone installs may use `/opt/homebrew/bin/codex` or `/usr/local/bin/codex`. Choose the executable that exists on your machine. The example does not require a host named ChatGPT.

Developers can override with `MIRROR_CODEX_PATH`. After choosing the file, refresh to reconnect. The currently verified CLI version is0.159.0.

## Permissions and binding

| Setting | Purpose | Required? |
| --- | --- | --- |
| Codex executable | Read local history | Yes, except demo mode |
| Mirror Accessibility | Identify/follow host windows and selected text | Optional for manual reading |
| Codex window binding | Identify the window a reference group follows | Only for host following |

Enable **Mirror** in System Settings → Privacy & Security → Accessibility, return to setup, then focus a Codex window and choose **◧ → Bind to Codex window**. This permission is for the installed Mirror app, not Figma, a browser or an installer.

Updating/rebuilding an ad-hoc signed app can require authorization again. Check the app's location before handling duplicate permission entries; see [troubleshooting](troubleshooting.en.md). Normal reading requires neither Screen Recording nor Full Disk Access.

## Source, updates and removal

Source builds require full Xcode, Swift 6 and macOS; run `bash scripts/build.sh`. Tests also use Python 3 fixtures. Full commands are in [Contributing](../CONTRIBUTING.md).

There is no auto-updater. Quit Mirror before replacing it in the same location; local view state remains, but permissions may need renewal. To uninstall, quit and remove the app. Optionally remove Mirror's state described in [Privacy](privacy.en.md); this does not delete Codex history.
