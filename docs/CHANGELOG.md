# Changelog

Historical record of how Scribe got to its current shape, newest first. This is the place for
phase/MVP references — unlike code comments and the README, a changelog's whole purpose is being
a timeline. For the *why* behind specific choices, see [DECISIONS.md](DECISIONS.md).

## Hotkey: `CGEventTap` migration + double-tap-to-lock hands-free mode

Replaced the dual `NSEvent` global/local monitor pair with a single `CGEventTap` on
`flagsChanged`, so `LiveGlobalHotkeyService` can now *consume* the Fn edge (return `nil` from the
tap callback) instead of only observing it — an attempt at suppressing macOS's own "Press 🌐 Fn key
to:" system action from firing alongside Scribe's shortcut, matching what Wispr Flow appears to do.
**Not verified on real hardware** — this environment can't run the app, so whether the suppression
actually works in practice is unconfirmed; the "Do Nothing" system-setting mitigation documented
below remains the fallback. This also swaps the permission the hotkey needs from Accessibility to
**Input Monitoring** (`IOHIDCheckAccess`/`Privacy_ListenEvent`), a separate TCC permission;
`AutoPasteService`'s own Accessibility check for its synthetic ⌘V is unaffected. See
[DECISIONS.md](DECISIONS.md) for the full mechanism and why `currentStatus()` retries tap creation
lazily instead of once.

Also added a double-tap-to-lock hands-free mode on top of push-to-talk (matching Wispr Flow):
tapping the shortcut twice quickly locks recording on without holding it down; a third tap stops.
Implemented as an internal `PushToTalkState` (`.idle`/`.recording`/`.locked`) state machine inside
`LiveGlobalHotkeyService`, with **no change** to the `GlobalHotkeyServicing` protocol or to
`DictationViewModel`'s decision logic — it still sees a single `onHotkeyPressed` callback per real
edge. Releasing the shortcut now waits a short `doubleTapWindow` (defaults to
`NSEvent.doubleClickInterval`) before emitting, in case a second tap arrives; this adds that same
latency to every normal push-to-talk release, not just double-taps.

Renamed `HotkeyStatus.accessibilityPermissionRequired` → `.inputMonitoringPermissionRequired` (and
the matching `PrimaryState`/UI copy) throughout `HotkeyStatusView`, `MenuBarContentView`,
`ContentView`, `DictationStatusView`, `DictationViewModel`, and `PermissionStatusController`.
Covered by a rewritten `GlobalHotkeyServiceTests`, including a new "modo manos libres" section
exercising the double-tap/lock/stray-callback edge cases.

## Hotkey: Fn push-to-talk (matches Whispr's actual default)

Corrected the trigger introduced in the entry below: Whispr's actual default push-to-talk key is
Fn alone, not Control — Control was an intermediate step during that migration. Swapped
`HotkeyModifierTrigger`'s default from `.control` to `.function`; no other part of the mechanism
changed (`.flagsChanged` edge detection, `GlobalHotkeyServicing`, `DictationViewModel` wiring). See
[DECISIONS.md](DECISIONS.md) for the real trade-off this raises: macOS's own System Settings →
Keyboard → "Press 🌐 Fn key to:" feature (change input source, show Emoji & Symbols, start
Dictation) listens for the exact same bare-Fn gesture, and Scribe has no way to suppress that
system-level behavior from an app-level event monitor — using Fn for Scribe's shortcut while that
setting is anything other than "Do Nothing" means both fire on every recording. The only real fix
is setting it to "Do Nothing" (documented in the README); this is the same requirement Whispr
documents for its own default shortcut.

## Hotkey: Control push-to-talk + bottom overlay placement

Replaced the Fn + Espacio toggle shortcut with holding Control (push-to-talk, matching Whispr):
pressing starts recording, releasing stops and transcribes, instead of two separate toggle
presses. `HotkeyTrigger` (keyCode + modifier over `keyDown`) became `HotkeyModifierTrigger` (a bare
modifier over `flagsChanged`), since Control alone never generates a `keyDown`. The
`GlobalHotkeyServicing` contract didn't need to change — the same `onHotkeyPressed` callback now
fires on both edges (Control down and up), which is enough because `handlePrimaryDictationAction`
already decides what to do from the current session state. See [DECISIONS.md](DECISIONS.md) for
the rationale and the known trade-off (Control is also used in system/app shortcuts like Ctrl+C).
Also moved the floating recording overlay from the top to the bottom of the screen.

## MVP5 — auto-paste

Added automatic pasting of a successful transcription into whichever app was focused right before
Fn + Espacio (or the record button) was pressed, closing the gap between "transcription ready" and
the text actually landing in whatever the user was writing — no manual "Copiar" + ⌘V required. See
[MVP5_AUTO_PASTE_PLAN.md](MVP5_AUTO_PASTE_PLAN.md) for the design questions this answered, the
implementation notes, and the manual QA checklist.

- **Phase 2** — added the `AutoPasteServicing` protocol and the `AutoPasteResult`/`AutoPasteTarget`
  types (`AutoPasteService.swift`), with a `Live`/`Fake` pair following the same DI pattern as
  `ClipboardServicing`/`WindowActivationServicing`; not wired into `DictationViewModel` yet.
- **Phase 3** — `DictationViewModel.startRecordingIfPossible()` captures the frontmost app
  (`capturedAutoPasteTarget`) synchronously before anything else runs, so a permission dialog or
  window activation can't change which app auto-paste will target later.
- **Phase 4** — implemented `LiveAutoPasteService.paste(text:target:)`: writes the transcript to
  the general pasteboard and synthesizes ⌘V via `CGEvent`, reactivating the target app first if
  it's no longer frontmost (with a short settling delay). Gated on the same Accessibility
  permission the global hotkey already needs; skips silently on a secure focused field
  (`kAXSecureTextFieldSubrole`), an unavailable/terminated target, or empty text.
- **Phase 5** — restores whatever was on the clipboard before the auto-paste write, unless the
  pasteboard's `changeCount` shows something else wrote to it in the meantime (most likely the
  user copying something new mid-paste) — that newer content is left alone instead of being
  clobbered.
- **Phase 6** — feedback and an off switch: the floating overlay's "Listo" checkmark becomes
  "Pegado" after a successful auto-paste; a short status line appears in the menu bar's menu for
  failures worth mentioning (`DictationViewModel.autoPasteStatusText`); a "Pegado automático"
  toggle in the menu bar (`isAutoPasteEnabled`/`setAutoPasteEnabled(_:)`) turns it off entirely,
  persisted in `UserDefaults` and on by default.
- **Phase 7** — guarded against a stale auto-paste result: if a new recording starts before a
  slow-resolving auto-paste from the previous session finishes, that late result is now discarded
  instead of overwriting `lastAutoPasteResult` for the new session (`currentAutoPasteAttempt`, the
  same UUID-comparison pattern `TranscriptionAttemptCoordinator` already used for transcription
  results).
- **Phase 8** — README and docs finalization: documented auto-paste's behavior end-to-end in the
  README, converted `MVP5_AUTO_PASTE_PLAN.md` from a pre-implementation readiness doc into
  implementation notes + a full manual QA checklist + known limitations, and updated this changelog
  and `ROADMAP.md` to reflect that MVP5 shipped.

Covered by `AutoPasteServiceTests`, `DictationViewModelAutoPasteCaptureTests`,
`DictationViewModelAutoPasteTriggerTests`, and `DictationViewModelAutoPasteToggleTests`, on top of
the existing suite.

## MVP4.5 — consolidation before auto-paste

Housekeeping pass before starting auto-paste: split `DictationViewModel` into focused, independently
tested controllers (`PermissionStatusController`, `TranscriptSessionController`, `RecordingMeter`,
`TranscriptionAttemptCoordinator`, `RecordingDurationPolicy`); removed "Fase X"/"MVP" narrative from
code comments in favor of `DECISIONS.md`; split this README into product docs +
`CHANGELOG.md`/`ROADMAP.md`/`DECISIONS.md`; added a GitHub Actions CI workflow
(`.github/workflows/ci.yml`) that runs `xcodegen generate` → resolve package dependencies → build →
test, unsigned, on every push/PR to `main`; extracted `HotkeyTrigger` out of
`LiveGlobalHotkeyService` so the Fn + Espacio combo is an injectable value instead of hardcoded
inline, as a low-risk fallback seam for hardware where it turns out not to be reliable (see
`docs/DECISIONS.md`), and expanded the README's manual QA checklist with a dedicated Fn + Espacio
hardware-validation list (built-in keyboard, Magic Keyboard with/without a dedicated Fn key,
third-party keyboards, Karabiner-remapped keyboards); added a one-time first-launch welcome card
(`OnboardingWelcomeView`, gated by a `UserDefaults` flag on `DictationViewModel`) covering privacy,
permissions, and the Fn + Espacio shortcut in three lines; and did a VoiceOver pass across the main
window and menu bar icon — decorative icons redundant with adjacent text are now
`.accessibilityHidden`, multi-line status text is grouped into single VoiceOver stops, and the
transcript editor and menu bar status icon gained explicit accessibility labels; and added
`docs/MVP5_AUTO_PASTE_PLAN.md`, a readiness doc for the next roadmap item (auto-paste) covering what
existing building blocks it can reuse, what's still missing (a paste mechanism, clipboard-restore
behavior, secure-field handling), and open questions to resolve before implementation starts.

## MVP4 — background-first dictation, menu bar item, and floating overlay

Turned Scribe from a window-first app into a menu bar/background-first dictation utility, in the
spirit of background dictation utilities like Wispr Flow — a small always-available entry point, a
global shortcut that never steals focus, and a minimal floating indicator instead of a window
popping to the front. No third-party branding, assets, or exact UI was copied; the icon, overlay
design, and copy are original.

- **Phase 1–2** — Detect Fn + Espacio via local and global `NSEvent` monitors (see
  [DECISIONS.md](DECISIONS.md) for why both are needed).
- **Phase 3** — Stop activating the main window on every hotkey press. The behavioral core of MVP4:
  the shortcut works identically whether Scribe's window is open, minimized, or fully closed, and
  never interrupts whatever app the user is dictating into.
- **Phase 4** — Add a menu bar status item (`MenuBarContentView.swift`): `MenuBarStatusIcon` shows a
  distinct SF Symbol per broad state (idle, recording, busy, downloading, needs attention), and its
  menu offers start/stop, copy last transcript, "Mostrar Scribe", the model folder, permission
  shortcuts, and quit — all routed through the same `handlePrimaryDictationAction`/view-model
  methods the window's button already uses.
- **Phase 5** — Add the floating recording/transcribing/done overlay (`RecordingOverlayController.swift`,
  `RecordingOverlayView.swift`): a borderless, non-activating `NSPanel` shown via
  `orderFrontRegardless()` (never `orderFront`/`makeKey`, which would steal focus), driven purely by
  a computed `overlayPhase` on `DictationViewModel`.
- **Phase 6** — Visual polish: split the menu bar icon's "downloading model" case into its own
  symbol instead of sharing the idle waveform, added a short fade in/out to the overlay panel
  instead of an abrupt show/hide, and swept the app's copy for a stray non-ASCII ellipsis.

## Phase 12 — original app icon

Added a first app icon; the project previously shipped with `ASSETCATALOG_COMPILER_APPICON_NAME`
empty and no `Assets.xcassets` at all.

- The icon is an abstract equalizer/waveform mark (five rounded bars, center tallest) in white over
  a navy-to-teal diagonal gradient — original geometry, not derived from Wispr Flow's or any other
  app's mark.
- `Scripts/generate_icon.swift` is a standalone script (outside both Xcode targets, so it isn't
  compiled into the app) that builds the icon as a SwiftUI view and rasterizes it to a 1024×1024 PNG
  via `ImageRenderer`; `sips` then downscales that master into the 10 sizes macOS expects
  (16–512pt, 1x/2x) into `Scribe/Assets.xcassets/AppIcon.appiconset/`.
- To regenerate or redesign the icon later: edit the `AppIconArtwork` view in
  `Scripts/generate_icon.swift`, rerun it with `swift Scripts/generate_icon.swift /tmp/icon-master.png`,
  then re-run the `sips` resize loop to refresh the PNGs in `AppIcon.appiconset/`.

## Phase 11 — visual polish pass

A layout/hierarchy pass with no behavior changes, aimed at making the window read like a deliberate
small utility instead of a first-draft prototype.

- Added `Scribe/Metrics.swift`: shared spacing/corner-radius constants and a `cardBackground()` view
  modifier, replacing the ad hoc numbers each view used to define on its own (14, 10, 8, 6, 4...).
- The status area (icon, title, record button) and the transcript area (editor, undo, Copiar/Limpiar)
  are now each wrapped in a "card" — a rounded, subtly shadowed background — so they read as two
  clear blocks instead of a flat stack of rows.
- `DictationStatusView`'s title grew from `.title3.semibold` to `.title2.bold`, and its icon now sits
  on a soft tinted circle that pulses with it. `ScribeHeaderView` shrank to a single footnote-sized
  line so it stops competing with that title.
- The "Deshacer reemplazo" button (Phase 10) was restyled from a bordered button into a small
  accent-tinted pill/capsule.

## Phase 10 — instant replace + undo buffer

A Wispr-Flow-style redesign pass. The previous flow blocked a new recording behind a confirmation
dialog whenever there was a non-empty transcript — which fought the whole point of a fast,
keyboard-first dictation tool. See [DECISIONS.md](DECISIONS.md) for the resulting design
(`previousTranscript` single-slot undo buffer).

- `PendingConfirmation` dropped its `.replaceTranscript` case; only `.clearTranscript` remains.
- `ContentView` shows a small "Deshacer reemplazo" pill whenever `previousTranscript != nil`.
- "Limpiar" is unaffected: clearing a non-empty transcript still asks for confirmation, and also
  drops `previousTranscript` (undoing a clear the user just confirmed would be confusing).

## Phase 9 — Fn + Espacio global shortcut

Replaced the Option-alone global trigger with Fn + Espacio (modeled after Wispr Flow's default Mac
shortcut). See [DECISIONS.md](DECISIONS.md) for why Option alone was dropped.

- `LiveGlobalHotkeyService` switched its global monitor from
  `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` to `.keyDown`, firing the callback
  when Space (keyCode 49) arrives with the `.function` modifier flag and `isARepeat == false`.
- The permission model is unchanged: both event masks go through the same `NSEvent` API, gated on
  the Accessibility permission alone.
- `handleKeyDown` (internal, not `private`) is directly unit-tested with synthetic `NSEvent`s.
- All UI copy that named "Option" now says "Fn + Espacio" instead.

Known limitation at the time: the real Fn + Espacio detection had not been exercised on physical
hardware — no way to interact with a live keyboard in that environment. Still true; see the manual
QA checklist in the README.

## Phase 8 — compact dictation UI

The main window was redesigned to feel like a small dictation utility instead of a document editor,
following the interaction principles of compact/fast/minimal/keyboard-first tools (not their
branding, assets, or copy): one obvious central state, strong recording/transcribing feedback, and
a transcript that's secondary rather than the dominant element.

- `ScribeHeaderView` became a static header with no live state; `DictationStatusView` became the one
  place that changes per state.
- `DictationStatusView` is the focal point: a large icon (color-coded and pulsing while recording)
  plus the `PrimaryState` title, with the existing `RecordingFeedbackView`/`TranscribingFeedbackView`
  nested inside it.
- `TranscriptEditorView`'s minimum height dropped from 220 to 140 so it reads as a secondary card.
- `StatusBadgeView` was retired as redundant with `DictationStatusView`'s title + icon color.
- The window's minimum size went from 440×580 to 380×460.

Deliberately out of scope at the time: auto-paste (shipped later, see MVP5 above), hold-to-talk, a
configurable shortcut, AI cleanup, history, a model selector, and always-on-top/floating window
behavior for the main window itself (the floating *overlay* added in MVP4 is a separate, narrower
thing — see [DECISIONS.md](DECISIONS.md)). Hold-to-talk, the configurable shortcut, history, and
the model selector are still out of scope today — see [ROADMAP.md](ROADMAP.md).

## Phase 7 — window activation and app focus

Pressing the global shortcut used to also bring Scribe's window to the front first, from any app, so
the confirmation dialog and the recording/transcribing feedback were always visible to whoever just
triggered them. (MVP4 Phase 3, above, later removed this in favor of background-first.) See
[DECISIONS.md](DECISIONS.md) for `WindowActivationServicing`, `AppDelegate` owning
`DictationViewModel`, and the `openWindow` reopen bridge introduced in this phase.

## MVP3 — global shortcut (Option, then migrated to Fn + Espacio)

Introduced Scribe's first global dictation trigger: the Option key alone, pressed with no other
modifier, from anywhere in macOS. Added `GlobalHotkeyServicing` (`start`/`stop`/`currentStatus()`),
wired straight to `handlePrimaryDictationAction(source: .globalHotkey)` — the same method the
record/stop button already called — so the hotkey and the UI can't get out of sync. Added
`HotkeyStatus` (`.unknown`/`.active`/`.accessibilityPermissionRequired`/`.failed`) and the
Accessibility-permission recovery UI (`HotkeyStatusView`). Phase 9 (above) later replaced the
Option-alone trigger with Fn + Espacio; the protocol shape and state ownership described here were
unchanged by that migration — only the key-detection details changed.

## Storage migration — LocalDictate → Scribe rename

The app was renamed from LocalDictate to Scribe. The visible app name and module changed, but the
Bundle Identifier intentionally stayed `com.localdictate.app` (see the README's Troubleshooting
section for why — TCC keys the microphone grant off the Bundle ID, not the display name). Existing
`LocalDictate` transcript/model data on disk and `UserDefaults` keys were migrated forward
(copied for the transcript, read-in-place for the model, renamed for small preferences) without ever
deleting the legacy files.
