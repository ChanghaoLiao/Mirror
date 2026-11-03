# Native command reference

Use `bash <absolute-helper-path> COMMAND`. All commands support `--app /absolute/path/Mirror.app` and optional `--request-id UUID`. Supported desktop version: 1.0.0+. The plugin does not silently upgrade or replace the app.

| Command | Required arguments | Result / purpose |
|---|---|---|
| `status`, `list` | None | Live revision, Agent enabled state, Accessibility state and reference-window metadata. Starts Mirror in the background if needed; use `--launch false` for follow-up checks so a human quit is respected. |
| `open` | `--conversation ID --revision N` | Reuses the unique reference for this conversation, or creates one; automatically attempts host binding. Optional `--message TURN_ID/ITEM_ID`, `--window UUID`, or `--new true`. |
| `duplicate` | `--window UUID --revision N` | Creates one independent copy when requested. |
| `close` | `--window UUID --revision N` | Closes only that Mirror reference. |
| `hide`, `show` | `--window UUID --revision N` | Hides or restores the reference. |
| `refresh` | `--window UUID --revision N` | Starts an update while preserving the existing reading content. |
| `cancel` | `--window UUID --revision N` | Cancels this window's current reading request. |
| `copy` | `--window UUID --revision N` | Copies the current message to the local clipboard; response contains no message body. |
| `find` | `--window UUID --query TEXT --revision N` | Finds text in the reference. An empty query clears find. |
| `font` | `--window UUID --font-size NUMBER --revision N` | Sets font size from 11 through 26. |
| `frame` | `--window UUID --frame JSON --revision N` | Positions/sizes the reference; JSON contains finite numeric `x`, `y`, `width`, `height`; minimum size 280 × 260, maximum dimensions 100000 and coordinates within ±100000. Native app clamps to usable screen geometry. |
| `bind`, `unbind` | `--window UUID --revision N` | Binds to the detected Codex host or stops following it. No OS permission prompt is triggered by Agent commands. |

Example geometry argument: `' {"x":40,"y":60,"width":500,"height":700} '`. Coordinates are macOS screen coordinates with an origin at the bottom left. Use observed screen geometry rather than assuming a display size. A frame mutation alone does not establish host binding.

Conversation IDs use ASCII letters, digits, `_`, `-` and `.` (maximum 256 bytes); message IDs are two such components joined by `/` (maximum 512 bytes total). `..` is rejected in either ID. Find text supports Unicode up to 4096 UTF-8 bytes and excludes native Unicode control characters.

A response has `ok`, `status`, `revision` and `windows`; transport failures may have no snapshot. Window records include `id`, `conversationID`, `messageID`, `collapsed`, `bound`, `fontSize`, `frame`, `loading` and `contentStatus`. Optional top-level fields include `windowID`, `binding`, `loading`, `agentEnabled`, `accessibilityGranted`, `appVersion` and `message`. The helper adds `requestID` for identifying an uncertain result. A missing field is unknown, not false.

Read `status` and `binding` separately: a reference can open successfully while host binding is unavailable. `contentStatus: loaded` indicates native reading completion, not independent confirmation of every semantic statement in the conversation. Do not invent a success meaning for an unfamiliar result.

- `app_not_running` after a follow-up check: stop; do not relaunch to continue the old request. If the target window disappears from a snapshot, treat the pending operation as ended and never recreate it unless the user asks again.
- `revision_conflict`: a human or another operation changed state; stop the pending action and reconcile it with the user's intent.
- `agent_paused`: human control disabled Agent changes. Only a human can enable them again.
- `ambiguous_window`: pick from confirmed returned IDs, or clarify which reference the user means. Do not pick an arbitrary one.
- Missing/ambiguous host or Accessibility: keep the usable reference open and report the specific missing prerequisite. Binding is to a window, not a chat tab.
- `setup_required`: show the setup instructions; normal reading needs a working local Codex executable. Do not claim installation checks prove setup.
- `upgrade_required`: this desktop app predates Agent controls; no change or launch was attempted.
- `restart_required`: a running app has no command service. Ask the user to reopen that exact app; don't kill it, overwrite it or spawn another copy.
- `startup_pending`: first launch has not made the service available. Check for a native first-launch prompt before trying status again.
- `timeout`: outcome may be uncertain. Inspect state; do not resend a mutation under a fresh request ID.

Only read-only startup checks are automatically retried. The native client has a five-second deadline. The helper allows 6.5 seconds for the process and limits response JSON to 64 KiB. Requests go through the exact verified app executable via JSON stdin; there is no arbitrary shell-command endpoint. Temporary response buffers use a private directory and are removed after the call.
