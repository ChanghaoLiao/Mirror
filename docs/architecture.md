# Architecture decision — 2026-09-26

macOS 14+ / Swift / AppKit. Zero third-party runtime dependencies. Native text layout avoids a browser engine, GPU worker, Node runtime and a second Agent client. macOS itself still composites windows; “no GPU” means no application GPU workload, not disabling the OS compositor.

Codex is the first vertical slice. The installed 0.159.0 CLI successfully served `initialize`, `thread/list` and `thread/read` and `thread/turns/list`. Use one shared stdio App Server and an allowlist of read-only methods. Prefer paginated full turns; do not resume/fork/start threads or invoke models. The desktop control proxy has no socket on this installation. CLI path discovery stays inside the adapter.

Core owns provider contract, immutable shared conversations, independent value-type reference state, semantic anchors, visibility decisions and atomic JSON storage. AppKit owns rendering, window lifecycle and native events. AX observers identify a concrete host window (permission required). Workspace activation also accepts its own Mirror windows. Host window tokens are live AX identities; restart uses a unique title match or explicit rebind, never the first arbitrary window.

No official API exposes the desktop viewport/current message. Manual conversation choice and explicit conversation/message deep links are supported. Selected-text anchoring is a best-effort AX adapter capability and fails visibly when unavailable. Never infer the active conversation from the most recently updated thread.

Native reading uses paragraph blocks. Anchors contain message ID, block index and character offset; layout restores that character after resize. Code and plain native table grids have their own horizontal scrollers. Each view owns layout and selection, while the source conversation is shared. Remote images are not fetched automatically.

Sources: [Codex App Server](https://learn.chatgpt.com/docs/app-server), installed CLI-generated JSON schemas, [Apple AXObserver](https://developer.apple.com/documentation/applicationservices/axobserver), [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace).


## Hardening revision — 2026-09-27

The transport is an actor: framing and JSON parsing no longer run on the main actor. Each read has a cancellable continuation and deadline, tagged with a connection generation so an old process cannot disconnect a replacement. Codex remains the owner of its history; Mirror does not send a cancellation mutation to the host. Dropped read replies are ignored locally.

ConversationStore coalesces waiters and partial snapshots. The final waiter leaving cancels the provider task; UUID generations prevent late cache publication. Only complete snapshots enter the cache. Active owners pin shared data and receive refreshed snapshots; each view restores its own anchor. Inactive data is bounded by entry and source-byte budgets.

The reader stores lightweight block geometry, with estimated heights for blocks not yet measured. Native NSTextViews are created around the viewport and released outside a two-viewport buffer; measured heights are kept. Reflow and jumps keep a message/block/character anchor fixed while heights settle. Selected image previews are retained per reference and are never automatically reread from attachment paths.

WorkspacePhase names active-host, owned-reference, inactive, minimized, closed, unavailable and restoring states. Permission loss preserves live binding identity while disabling host-following; explicit Mirror reading remains available for the current group. A closed bound host is not silently replaced by another identical-titled window during that runtime. Screen geometry is clamped on restoration and screen changes.
