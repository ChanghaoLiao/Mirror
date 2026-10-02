# User guide

[简体中文](usage.md) · [Home](../README.en.md)

## Three concepts

A **conversation** is existing Codex history. A **reference window** is an independent view of it. **Binding** associates a group of references with a specific Codex window. Duplicating a reference never duplicates a conversation or asks the AI to answer again.

Manual reading works while unbound. For following, grant Accessibility, focus the target Codex window and choose **Bind to Codex window**. Renamed or ambiguous duplicate host titles can require rebinding after restart.

## Workflow

1. Choose **◧ → Open Reference** or press **⇧⌘M**.
2. Click **Conversations**, search a title and select it. Use **Load more conversations** when another page exists. Automatic selection only attempts a unique exact host-title match, never a most-recently-updated guess.
3. Scroll to the useful section and press **⌘D**. The new reference starts at that position; afterward it scrolls, changes fonts and selects conversations independently.
4. Move and resize using native window controls. Restart restores geometry, fonts and semantic text anchors, not stored conversation bodies.
5. Press **⌘R** or **••• → Refresh conversation**. Existing content remains readable until a complete update succeeds, retaining the position you are reading at commit time.

The first read progressively displays pages and marks incomplete history. A failed/cancelled first read may leave a partial result; refresh to retry. Failed or cancelled updates preserve a previous complete snapshot. Transient disconnects/timeouts recover automatically; malformed responses/rejections are explicit. Repeated clicks are coalesced.

## Find, copy and images

**⌘F** searches loaded text. Return or **Next** advances; **Clear** returns to the pre-search position. It does not modify source content. Conversation title search is a separate control.

Select text and press **⌘C**. **Copy complete message** copies the focused/current message with source Markdown, not the entire conversation. Code and table grids have horizontal scrolling. Images start as placeholders; **Choose image to preview…** only opens the explicitly selected file, never automatically follows attachment paths.

## Every menu

| Menu | Controls |
| --- | --- |
| Conversations toolbar | Title search, selection, load more |
| Find toolbar | Text search, next, clear |
| ••• | Duplicate, refresh, copy message, smaller/larger text, hide, appearance/language, setup/permissions, close, back to reading |
| ◧ menu bar | Open, open at selected text, restore hidden, bind host, setup, choose Codex, appearance/language, about, quit |

Escape dismisses panels and returns keyboard focus to the trigger; clicking outside also dismisses them. Font size is11–26 per reference. Appearance/language is global; language changes labels, not conversation text.

**Hide** retains a reference and its position; **Restore hidden references** restores the current group. **⌘W** closes only this reference. Other windows stay open. Restart restores references retained in local view state.

## Following and selected text

Bound reference groups change visibility with host focus/minimization. Clicking a member reference keeps its group visible. Following is unavailable without permission or a binding. Some full-screen/Spaces combinations need further validation.

**Open at selected text** attempts Accessibility selected-text lookup within the associated history. Missing or ambiguous selections produce feedback. It is not an official currently-visible-message integration.

Developers can open an explicit-ID read-only link:

```sh
open 'mirror://open?conversation=THREAD_ID&message=TURN_ID%2FITEM_ID'
```

Use actual provider IDs with URL encoding; message is optional. It does not send a message or start/fork an Agent task. Do not share real deep links publicly, as they reveal conversation identifiers.
