---
name: mirror-setup
description: Check Mirror desktop prerequisites and help with first-run setup when the user installs or configures the Mirror plugin on a Mac.
---

# Set up Mirror

For a downloaded toolkit, read its SKILL.md directly for immediate use. For persistent discovery, determine the host's supported skill directory, then run `bash <absolute-register-path> --target <absolute-skill-directory>` using `../mirror/scripts/register.sh`. It installs both skills, reuses identical copies and refuses to overwrite different ones. Do not guess a host's directory. `registered` confirms file installation, not host discovery or desktop readiness; reload host skills where needed, then check desktop status below. An already managed plugin does not need another skill installation.

The skill and desktop app are separate. Agent controls require **Mirror 1.0.0+**, local command execution on the user's Mac, Apple Silicon and macOS 14+. The controller can be a compatible local Agent; the conversation source remains Codex. No API key, Node, Python or Xcode is needed for the shell skill route. The optional function-call adapter requires Python 3.9+.

Run `bash <absolute-helper-path> status`, resolving `../mirror/scripts/mirror.sh` relative to this file. It identifies one running Mirror app, otherwise checks the two Applications folders. Pass an already known app path with `--app`; do not search unrelated folders, remove copies or reinstall just to resolve ambiguity. Status starts a compatible app in the background without making a blank reference, then reports actual native state. It never grants macOS permissions or reads conversation bodies.

If no local execution tool exists, explain that this workflow needs a local Agent runner on the user's Mac and Codex for its history source. Do not request credentials or create a remote relay.

For a missing app, use the supplied installation lane; never ask the user to build source code:

- For a full bundle with a sibling `Mirror.app`, run the bundle root `setup.sh`. It verifies and installs that pinned app locally without downloading it again.
- For a small toolkit, source `../mirror/scripts/preview.conf` only as trusted package configuration. If `MIRROR_PREVIEW_AVAILABLE=true`, run `bash <absolute-preview-installer>` resolving `../mirror/scripts/install-preview.sh`. It downloads the fixed GitHub preview and verifies SHA256, bundle/version/build and the exact sealed CDHash before installing. This is explicitly an ad-hoc signed, not Apple-notarized preview, not a signed production release.
- Otherwise run the existing `../mirror/scripts/install.sh` production installer. Its Developer ID and notarization requirements remain unchanged. If neither lane is published, report `release_unavailable`; do not alter pins or use another download.

The user's request to use Mirror authorizes this first-run installation. For `replacement_confirmation_required`, show the existing app and ask before passing `--replace`; both lanes preserve a backup. For `quit_mirror_required`, stop and have the user quit normally. Never create another copy to evade a running app. Do not overwrite another location without an agreed migration.

A preview installer returns `manual_open_required`, not `ready`. Explain that the app is installed and let the human complete the macOS first-open decision; do not repeat downloads or treat this as missing Accessibility. The agent cannot click through that decision. Then run helper status and continue the original request. See [Apple's first-open guidance](https://support.apple.com/en-us/102445). Do not remove quarantine, disable Gatekeeper, use sudo or reset permission databases. The preview installer preserves or adds quarantine; it never silently skips the first-open review.

On download, checksum, signature, archive, installation or release availability errors, report the actual status and stop. Keep the existing app. Do not remove another installer's lock. Production releases still require Developer ID and notarization; the explicitly labeled preview is a separate distribution channel.

For `setup_required`, help with the existing setup window; do not repeatedly open references:

- **Connect Codex** selects the local executable named `codex`, not a chat window or an API key. Use an existing verified path; prefer working automatic discovery.
- **Continue read-only** supports reading without Accessibility. Ordinary reading does not need Screen Recording or Full Disk Access.
- To follow a Codex host, the human enables Mirror in **System Settings → Privacy & Security → Accessibility**. After that, the Agent can run `bind` with a current revision. If there are several possible hosts, the human can select the intended Codex window and use Mirror's binding menu. Missing binding is not proof that permission is absent.
- **Pause Agent control** in Mirror gives the human exclusive control until they manually resume it. The Agent cannot resume itself. Manual interactions invalidate earlier Agent revisions.

On `restart_required`, explain that the running process needs to be reopened before its new command service can work. Do not terminate it or install a second copy. Return the actual state and only the user's necessary next step. Once ready, follow [Mirror references](../mirror/SKILL.md).
