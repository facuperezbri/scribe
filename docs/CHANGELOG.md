# Changelog

Historical record of how Scribe got to its current shape, newest first. This is the place for
phase/MVP references — unlike code comments and the README, a changelog's whole purpose is being
a timeline. For the *why* behind specific choices, see [DECISIONS.md](DECISIONS.md).

## MVP4.5 — consolidation before auto-paste (in progress)

Housekeeping pass before starting auto-paste: split `DictationViewModel` into focused, independently
tested controllers (`PermissionStatusController`, `TranscriptSessionController`, `RecordingMeter`,
`TranscriptionAttemptCoordinator`, `RecordingDurationPolicy`); removed "Fase X"/"MVP" narrative from
code comments in favor of `DECISIONS.md`; split this README into product docs +
`CHANGELOG.md`/`ROADMAP.md`/`DECISIONS.md`.

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

Deliberately out of scope at the time (still true today): auto-paste, hold-to-talk, a configurable
shortcut, AI cleanup, history, a model selector, and always-on-top/floating window behavior for the
main window itself (the floating *overlay* added in MVP4 is a separate, narrower thing — see
[DECISIONS.md](DECISIONS.md)).

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
