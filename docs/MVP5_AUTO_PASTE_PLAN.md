# MVP5: auto-paste — plan and implementation notes

Originally written as a design/readiness doc, before any auto-paste code existed, for the next
feature on [ROADMAP.md](ROADMAP.md): paste the transcription result directly into whichever app
was focused before the Fn + Espacio shortcut was pressed, instead of requiring a manual "Copiar" +
⌘V. All 8 phases below shipped (see [CHANGELOG.md](CHANGELOG.md) for the phase-by-phase history);
this doc keeps the original open questions and the decisions made in answering them, then adds what
was actually built, the manual QA checklist, and known limitations.

## What already existed to build on

MVP4/MVP4.5 had already put most of the non-paste-specific plumbing in place:

- **Global shortcut with a stable entry point.** Every record/stop action already funnels through
  `handlePrimaryDictationAction(source:)` regardless of trigger (button, hotkey, menu bar). Auto-paste
  only needed a new step *after* a successful transcription, not a new trigger path.
- **Background-first focus model.** `WindowActivationServicing`/`LiveWindowActivationService` and the
  decision to never activate Scribe's window from the hotkey (see [DECISIONS.md](DECISIONS.md)) mean
  the previously-focused app is, in the common case, still focused when transcription finishes —
  auto-paste doesn't have to fight Scribe's own window for focus the way it would have before MVP4.
- **Accessibility permission already required and modeled.** `HotkeyStatus`
  (`.unknown`/`.active`/`.accessibilityPermissionRequired`/`.failed`) and its recovery UI
  (`HotkeyStatusView`) already gate the hotkey on the same Accessibility permission that synthetic
  keystrokes need — no new permission prompt/flow to design, just a second consumer of a permission
  the user has likely already granted.
- **`ClipboardService`/`ClipboardServicing`.** Auto-paste still needed the clipboard as the
  mechanism, so this wasn't replaced, just extended.
- **Typed error model.** `AppError`/`AppErrorCategory` already separates category from message;
  auto-paste ended up with its own typed result (`AutoPasteResult`) in the same spirit rather than
  routing through `AppError`, since a failed/skipped paste is never treated as an app-level error
  (see "Failure behavior" below).

## Open questions and the decisions made

1. **How to actually insert text into another app.** Two real options on macOS, both needing the
   Accessibility permission Scribe already requests: synthesize ⌘V via `CGEvent`/`CGEventPost`, or
   insert text directly via the Accessibility API (`AXUIElementSetAttributeValue`). **Decision:**
   shipped the `CGEvent` ⌘V approach as planned — simpler, works nearly everywhere, matches what
   "Copiar" + manual ⌘V already did. Direct AX text insertion was not built; it remains a possible
   later refinement, not a blocker.
2. **Whether paste even makes sense for the target app/field.** Secure input fields actively block
   synthetic keystrokes and programmatic AX text insertion by design. **Decision:** detect this via
   `kAXSecureTextFieldSubrole` on the system-wide focused element and skip silently — no retry, no
   error. Confirmed limitation: toolkits that don't expose a subrole (notably some Electron apps)
   aren't detected this way.
3. **A restore point for the clipboard.** The `CGEvent` approach has to put the transcript on the
   clipboard, overwriting the user's previous contents. **Decision:** restore the previous clipboard
   contents automatically after pasting (the safer option), guarded by the pasteboard's
   `changeCount` so a newer copy made during the restore delay isn't clobbered.
4. **What happens if the user has switched apps by the time transcription finishes.** Transcription
   is async and can take several seconds. **Decision:** remember and reactivate the *originally*
   captured target app before pasting into it, rather than pasting into whatever is currently
   focused. This is a deliberate, narrow exception to the background-first design used everywhere
   else in the app — see "Known limitations" below, since it does steal focus back in that specific
   case.
5. **A way to fail visibly but non-intrusively.** **Decision:** no modal dialog, ever. The floating
   overlay's "Listo" becomes "Pegado" on success; a short status line in the menu bar's menu covers
   failures worth mentioning. See "Failure behavior" below for exactly which outcomes surface a
   message.
6. **Whether "Copiar" stays as a fallback/parallel action, not a replacement.** **Decision:** yes —
   manual copy keeps working exactly as before regardless of auto-paste's success/failure; auto-paste
   is purely additive.

## Implementation as shipped

- **`AutoPasteServicing`** (`Scribe/AutoPasteService.swift`): `captureTarget() -> AutoPasteTarget?`
  and `paste(text:target:) async -> AutoPasteResult`. `LiveAutoPasteService` is the real
  implementation, with every system effect (Accessibility check, secure-field check, pasteboard
  read/write, target reactivation, keystroke synthesis) behind an injectable closure so unit tests
  never touch real system state; `FakeAutoPasteService` (in `ScribeTests/TestDoubles.swift`) is the
  test double.
- **`AutoPasteTarget`**: pid + bundle identifier + localized name + the live `NSRunningApplication`
  needed to reactivate it later; equality compares pid only.
- **`AutoPasteResult`**: `.pasted`, `.noTarget`, `.targetUnavailable`,
  `.accessibilityPermissionMissing`, `.emptyText`, `.secureField`, `.pasteboardFailed`,
  `.eventPostFailed`, `.unknown`.
- **Target capture strategy.** `DictationViewModel.startRecordingIfPossible()` calls
  `autoPasteService.captureTarget()` synchronously as the very first thing it does — before
  `state.session` even changes — so nothing (permission dialog, window activation) can change the
  frontmost app first. `captureTarget()` itself excludes Scribe's own bundle identifier, so
  dictation started from Scribe's own window captures no target.
- **Pasteboard + ⌘V strategy.** `LiveAutoPasteService.paste` writes the transcript to
  `NSPasteboard.general`, reactivates the captured target only if it's no longer frontmost
  (`activate()` + a 120ms settling delay, `reactivationDelay`), then posts a `CGEvent` ⌘V
  keydown/keyup pair on `.cgSessionEventTap` — the same mechanism a physical keypress would produce.
- **Clipboard restore strategy.** Reads the previous pasteboard string before writing the
  transcript, and restores it ~200ms after posting the keystroke (`clipboardRestoreDelay`) — but
  only if `NSPasteboard.general.changeCount` still matches what it was immediately after Scribe's
  own write. If it changed, something else (almost certainly the user, copying something new) wrote
  to the clipboard in between, and that newer content is left alone rather than overwritten back to
  the pre-paste value.
- **Secure-field detection.** `AXUIElementCopyAttributeValue` on the system-wide focused element's
  `kAXSubroleAttribute`; a match on `kAXSecureTextFieldSubrole` skips the paste before the clipboard
  or a keystroke are ever touched.
- **Stale-result guard.** `DictationViewModel.currentAutoPasteAttempt` (a `UUID`, reset at the start
  of every `startRecordingIfPossible()` and set right before the async paste `Task` in
  `performAutoPasteIfNeeded`) mirrors the pattern `TranscriptionAttemptCoordinator` already used for
  transcription results: a paste that resolves after a newer session has already started is
  discarded instead of overwriting `lastAutoPasteResult`.
- **On/off toggle.** `isAutoPasteEnabled`/`setAutoPasteEnabled(_:)`, backed by an inverted
  `UserDefaults` key (`Scribe.hasDisabledAutoPaste`) so the default (key absent, first launch) means
  enabled. Surfaced as a "Pegado automático" `Toggle` in `MenuBarContentView`. This toggle was
  originally scoped *out* of v1 (see "Explicitly out of scope" below) but shipped in Phase 6 once it
  was clear a kill switch was worth having even with an always-on default.

## Failure behavior

Never a modal dialog, and `AppError`/`state.error` are never touched by an auto-paste outcome — the
transcript is already saved and visible/copyable by the time auto-paste runs, so a paste failure
never blocks or corrupts anything else. `DictationViewModel.autoPasteStatusText` maps
`lastAutoPasteResult` to a short Spanish string for the menu bar's menu, but only for outcomes that
represent a real, attempted-and-failed paste:

| `AutoPasteResult` | Surfaced in the menu? |
| --- | --- |
| `.pasted` | No — the overlay's "Pegado" label already confirms success. |
| `.noTarget` | No — nothing was attempted, not a failure. |
| `.emptyText` | No — nothing was attempted, not a failure. |
| `.targetUnavailable` | Yes — "la app destino ya no está disponible." |
| `.accessibilityPermissionMissing` | Yes — "falta el permiso de Accesibilidad." |
| `.secureField` | Yes — "no se pegó en un campo que parece contraseña." |
| `.pasteboardFailed` / `.eventPostFailed` / `.unknown` | Yes — generic "no se pudo pegar" message pointing at "Copiar última transcripción". |

## Explicitly out of scope

Per [ROADMAP.md](ROADMAP.md), unrelated to auto-paste: live transcription, transcript history, a
model selector, and distribution/notarization work. Also out of scope specifically for auto-paste:

- Rich-text/formatting preservation — the transcript is plain text; pasting plain text is enough.
- Cross-app-specific handling — the `CGEvent` approach stayed intentionally app-agnostic; no
  per-app special-casing was added, and none has been observed to be needed yet.
- Direct AX text insertion (`AXUIElementSetAttributeValue`) as an alternative to `CGEvent` ⌘V —
  still a possible later refinement, not pursued for this version.

(A user-facing on/off toggle was originally on this "out of scope for v1" list too, but shipped in
Phase 6 — see "Implementation as shipped" above.)

## Manual QA checklist

- **Real target apps.** Paste into a plain text editor (TextEdit), a rich-text editor (Notes or
  Mail), a browser text field, Terminal, and at least one Electron-based app (VS Code, Slack) —
  confirm the transcript lands correctly and ⌘Z still undoes it normally afterward.
- **Secure field.** Focus a password field (e.g. a login prompt) right before transcription
  finishes; confirm auto-paste is skipped silently — no crash, no visible attempt — and "Copiar"
  still works.
- **Switching apps mid-transcription.** Start dictating from app A, switch focus to app B before
  transcription finishes; confirm Scribe reactivates app A (bringing it back to the front) before
  pasting into it, rather than pasting into app B.
- **Accessibility permission revoked mid-session.** Confirm auto-paste stops attempting silently
  (`.accessibilityPermissionMissing`), `HotkeyStatusView`'s recovery UI still applies, and the
  record button keeps working regardless.
- **Clipboard restore, happy path.** Copy something distinctive before dictating; confirm it's back
  on the clipboard a moment after the auto-paste completes.
- **Clipboard restore, race.** Copy something *new* while a paste is still in its restore-delay
  window (timing-sensitive, best-effort check); confirm that newer copy is not clobbered by the
  restore.
- **Toggle off/on.** Turn off "Pegado automático" in the menu bar; confirm no paste is attempted
  afterward (the transcript still updates, "Copiar" still works); turn it back on and confirm
  auto-paste resumes.
- **Rapid re-dictation.** Start a new recording immediately after a transcription whose auto-paste
  is still in flight (e.g. a slow-to-reactivate target app); confirm the first session's late result
  doesn't overwrite the second session's menu status line.
- **Empty transcription.** Confirm no paste attempt and no menu status line.
- **Target app closed before transcription finishes.** Confirm `.targetUnavailable`, a silent skip,
  and the corresponding menu status line.
- **No target captured.** Start a dictation from Scribe's own "Grabar" button (Scribe itself
  frontmost); confirm no paste attempt and no menu status line.

## Known limitations

- `reactivationDelay` (120ms) and `clipboardRestoreDelay` (200ms) are fixed heuristics, not measured
  across a representative set of real apps or hardware — a slow-to-activate app, or a toolkit that
  reads the clipboard asynchronously after a longer delay, could still race these.
- Secure-field detection is best-effort: toolkits that don't expose an Accessibility subrole
  (notably some Electron apps) won't be recognized as secure, so a synthetic paste could still be
  attempted into what is actually a password field there.
- If the user switches to a different app during transcription, Scribe brings the *original* target
  app back to the front to paste into it — a deliberate focus-stealing step scoped to auto-paste
  specifically; the rest of the app's background-first behavior (hotkey, window activation) is
  unaffected.
- Clipboard restore only preserves plain text; non-text clipboard content (an image, a file
  reference) present before an auto-paste is not restored.
- No per-app configuration — the "Pegado automático" toggle is global and all-or-nothing.
- No rich-text or formatting-aware paste; the transcript is always inserted as plain text.
