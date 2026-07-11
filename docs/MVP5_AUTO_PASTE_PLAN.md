# MVP5 readiness: auto-paste

A design/readiness doc for the next feature on [ROADMAP.md](ROADMAP.md), written before writing any
code for it. Goal: paste the transcription result directly into whichever app was focused before the
Fn + Espacio shortcut was pressed, instead of requiring a manual "Copiar" + ⌘V. This doc doesn't
implement anything; it's the plan to review before Phase 1 of that work starts.

## What already exists to build on

MVP4/MVP4.5 already put most of the non-paste-specific plumbing in place:

- **Global shortcut with a stable entry point.** Every record/stop action already funnels through
  `handlePrimaryDictationAction(source:)` regardless of trigger (button, hotkey, menu bar). Auto-paste
  only needs a new step *after* a successful transcription, not a new trigger path.
- **Background-first focus model.** `WindowActivationServicing`/`LiveWindowActivationService` and the
  decision to never activate Scribe's window from the hotkey (see [DECISIONS.md](DECISIONS.md)) mean
  the previously-focused app is, in the common case, still focused when transcription finishes —
  auto-paste doesn't have to fight Scribe's own window for focus the way it would have before MVP4.
- **Accessibility permission already required and modeled.** `HotkeyStatus`
  (`.unknown`/`.active`/`.accessibilityPermissionRequired`/`.failed`) and its recovery UI
  (`HotkeyStatusView`) already gate the hotkey on the same Accessibility permission that synthetic
  keystrokes (see below) would also need — no new permission prompt/flow to design, just a second
  consumer of a permission the user has likely already granted.
- **`ClipboardService`/`ClipboardServicing`.** Auto-paste still needs the clipboard as the mechanism
  (see "How auto-paste would work" below), so this isn't replaced, just extended.
- **Typed error model.** `AppError`/`AppErrorCategory` already separates category from message; a new
  `.autoPaste` (or similar) category slots in without redesigning error handling.

## What's missing

1. **A way to actually insert text into another app.** Two real options on macOS, both needing the
   Accessibility permission Scribe already requests:
   - Synthesize ⌘V via `CGEvent`/`CGEventPost` (simulate the same keystroke a human would press).
     Works anywhere a normal paste would, respects the target app's own paste handling (rich text
     fields, undo stack, etc.), but depends on the clipboard, so it clobbers whatever the user had
     copied before.
   - Insert text directly via the Accessibility API (`AXUIElementSetAttributeValue` on the focused
     `AXUIElement`'s value/selected-text attribute), bypassing the clipboard entirely. Doesn't clobber
     the clipboard, but not every app/control exposes a settable text attribute (e.g. some Electron
     apps, secure text fields by design), so it needs a fallback path anyway.
   - Recommendation: start with the `CGEvent` ⌘V approach (simpler, works nearly everywhere, matches
     what "Copiar" + manual ⌘V already does today) and treat direct `AXUIElementSetAttributeValue`
     insertion as a possible later refinement, not a blocker for a first version.
2. **Knowing paste even makes sense for the target app/field.** Secure input fields (password fields)
   actively block synthetic keystrokes and programmatic AX text insertion by design — this should fail
   silently/gracefully (falling back to "just copied, paste manually"), not retry or error loudly.
3. **A restore point for the clipboard.** Since the `CGEvent` approach must put the transcript on the
   clipboard to paste it, the user's previous clipboard contents are overwritten. Needs a decision:
   restore the previous clipboard contents automatically after pasting (safer, matches user
   expectation, but timing-sensitive if the target app reads the clipboard asynchronously), or leave
   the transcript on the clipboard (simpler, but silently destroys whatever the user had copied
   before, with no warning).
4. **Deciding what happens if the user has since switched apps.** Transcription is async and can take
   several seconds; the app that was focused when recording started may not be the one focused when
   transcription finishes. Needs a decision: paste into whatever is focused *now* (matches "paste"
   semantics literally, but may surprise the user if they've switched windows in the meantime), or
   remember and refocus the originally-recording app first (more predictable, but reintroduces a
   focus-stealing step the background-first design deliberately avoided).
5. **A way to fail visibly but non-intrusively.** If the synthetic paste doesn't land (permission
   revoked mid-session, target field rejected it, no focused element at all), the user needs to find
   out without a modal dialog interrupting whatever they're doing — most likely surfaced through the
   existing floating overlay (`RecordingOverlayView`) and/or `AppError`, not a new UI surface.
6. **Whether "Copiar" stays as a fallback/parallel action, not a replacement.** Manual copy must keep
   working exactly as it does today regardless of auto-paste's success/failure — auto-paste should be
   additive, never a required step to get the text out.

## Explicitly out of scope for this feature

Per [ROADMAP.md](ROADMAP.md), unrelated to auto-paste and not part of this plan: live transcription,
transcript history, a model selector, and distribution/notarization work. Also out of scope
specifically for auto-paste itself, at least for a first version:

- A user-facing toggle to disable auto-paste — start with it always-on (matching "background-first,
  no extra clicks" philosophy) and revisit only if manual testing surfaces real cases where it's
  actively unwanted, per the standing rule against building settings speculatively.
- Rich-text/formatting preservation — the transcript is plain text; pasting plain text is enough.
- Cross-app-specific handling (e.g. special-casing certain apps' known paste quirks) — the CGEvent
  approach is intentionally app-agnostic; special-casing individual apps is a rabbit hole to avoid
  starting down without a concrete, observed failure first.

## Suggested shape of the implementation (for the next planning pass, not decided yet)

Once the open questions above have answers, the likely shape — subject to revision once actual
implementation planning starts:

- A new `AutoPasteServicing` protocol (mirroring the existing `ClipboardServicing`/
  `WindowActivationServicing` pattern), with a `Live` implementation wrapping `CGEventPost` and a
  `Fake` for tests, following the DI pattern already used throughout `DictationViewModel`'s
  dependencies.
- A single new step at the point `DictationViewModel` currently marks a transcription successful,
  gated on the same Accessibility-permission check `HotkeyStatus` already exposes — if that permission
  isn't granted, auto-paste is silently skipped (never a hard failure) and "Copiar" remains the only
  path, exactly like today.
- No changes to `AppState`'s four dimensions (permission/model/session/error) — auto-paste is a
  side effect of a successful transcription, not a new state dimension of its own.

## Manual QA this feature will need before shipping

Not exhaustive — a first pass, to be expanded once implementation specifics are settled:

- Paste into a variety of real target apps: a plain text editor, a rich-text editor (e.g. Mail,
  Notes), a browser text field, a terminal, and at least one Electron-based app, since those are the
  most likely to behave unexpectedly with synthetic keystrokes.
- A secure text field (e.g. a password prompt) focused at the moment transcription finishes: confirm
  auto-paste fails silently with no crash, no error dialog, and the clipboard-based fallback ("Copiar"
  still works) is unaffected.
- Switching focus to a different app mid-transcription, to observe and confirm whichever behavior gets
  chosen for the "user switched apps" open question above.
- Revoking Accessibility permission mid-session: confirm auto-paste stops attempting silently, the
  existing `HotkeyStatusView` recovery UI still applies, and the hotkey/record button keep working.
- Whatever clipboard-restore behavior gets chosen: confirm the user's pre-existing clipboard contents
  end up in the expected state (restored or intentionally overwritten) after a paste.
