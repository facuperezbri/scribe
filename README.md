# Scribe

macOS desktop app for **local Spanish dictation**: hold Fn (or click "Grabar"),
speak, and get a cleaned transcript pasted into whatever app you were using — no
account, no cloud transcription, no analytics or telemetry.

Built on [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (Whisper on
Core ML) for on-device speech-to-text, with optional post-processing via Apple's
on-device Foundation Models when Apple Intelligence is available.

## At a glance

- **On-device transcription** — Whisper `large-v3` runs locally; Spanish only.
- **Fn push-to-talk** — global shortcut works from any app; background-first (no
  focus steal). Double-tap Fn for hands-free lock.
- **Floating overlay** — recording/transcribing feedback near the bottom of the
  screen without bringing Scribe forward.
- **Auto-paste** — successful transcriptions paste into the app that was focused
  when recording started (synthetic ⌘V).
- **Optional formatting** — Apple Intelligence can polish the literal Whisper
  output (remove fillers, fix punctuation, Casual or Formal tone). Falls back to
  raw text if unavailable.
- **Single last transcript** — one honest transcript slot with copy/clear, inline
  edit, and a one-slot undo after replace.
- **Menu bar control** — start/stop, copy, show window, toggles, and permission
  shortcuts always available.

## Table of contents

- [Privacy](#privacy)
- [Requirements](#requirements)
- [Build and run](#build-and-run)
- [Running the tests](#running-the-tests)
- [Usage](#usage)
- [Architecture](#architecture)
- [Model](#model)
- [Transcript](#transcript)
- [Storage migration (LocalDictate → Scribe)](#storage-migration-localdictate--scribe)
- [Error handling](#error-handling)
- [Troubleshooting](#troubleshooting)
- [Manual QA checklist](#manual-qa-checklist)
- [Known limitations](#known-limitations)
- [Learn more](#learn-more)

## Privacy

> Audio and text stay on this Mac. Nothing is sent to Scribe's servers — there
> are none.

Scribe has two separate on-device processing paths:

**Transcription (required for dictation).** Audio is recorded to a local WAV
file and transcribed by WhisperKit on this Mac. The only network use in the
whole app is the **one-time download** of the Whisper model (~626 MB), triggered
exclusively by the user via "Descargar modelo". `ModelManager` never downloads
on its own; it only reads disk to check whether the model is already installed.

**Formatting (optional, on by default).** After Whisper finishes, Scribe can pass
the literal transcript through Apple's on-device Foundation Models (Apple
Intelligence) to clean up fillers, stutters, and punctuation. This also runs
entirely on the Mac — no cloud API — but it **requires Apple Intelligence to be
enabled** on a supported machine. If Apple Intelligence is off, not ready, or
the reformat step fails, Scribe keeps the literal Whisper text and continues;
formatting never blocks dictation.

## Requirements

- macOS 26 or later
- Xcode 26 or later (aligned with the deployment target in `project.yml`)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- ~1 GB of free disk space for the Whisper model (`large-v3-v20240930_626MB`)
- **For formatting:** a Mac that supports Apple Intelligence, with it enabled in
  System Settings. Transcription works without it; formatting is skipped instead.

## Build and run

```bash
xcodegen generate
open Scribe.xcodeproj
```

Then run the `Scribe` scheme from Xcode (⌘R).

It can also be built from the terminal:

```bash
xcodegen generate
xcodebuild -project Scribe.xcodeproj -scheme Scribe \
  -configuration Debug -destination 'platform=macOS' build
```

## Running the tests

The tests live in the `ScribeTests` target (unit tests, no UI tests).
They don't require a real microphone, a model download, WhisperKit, or Apple
Intelligence: they exercise `DictationViewModel` (and the controllers it
delegates to) through fakes, by manipulating state directly.

From Xcode: ⌘U with the `Scribe` scheme (the tests are wired into its
test action).

From the terminal:

```bash
xcodegen generate
xcodebuild -project Scribe.xcodeproj -scheme Scribe \
  -configuration Debug -destination 'platform=macOS' test
```

## Usage

The main window is a calm local dictation control center (~820×680), not a
document editor: an identity bar (brand, live state, settings menu), an inline
attention row when setup needs action, a hero dictation card (voice motif, Fn
shortcut, contextual record/stop) alongside the last-transcript card, and a
quiet full-width system status footer (model, microphone, accessibility,
auto-paste, formatting, privacy).

1. Press "Grabar" (or hold Fn, see below) and speak in Spanish. While
   recording, the control card shows elapsed time, a microphone level meter
   (to confirm audio is being captured), and, past 2 and 5 minutes, a warning
   that the recording is getting long. Press "Detener" to stop.
2. The first time, the model (~626 MB) needs to be downloaded with the
   "Descargar modelo" button. Transcription of the pending recording starts
   automatically as soon as the download finishes.
3. While transcribing, the control card shows an indeterminate progress indicator (WhisperKit
   doesn't expose incremental progress for this step) along with a
   "Cancelar" button. Cancelling is "soft": the app discards the result as
   soon as it arrives, but it can't guarantee WhisperKit will abort inference
   midway. If formatting is enabled and Apple Intelligence is available, the
   status line briefly shows "Puliendo transcripción..." after Whisper finishes
   but before the text appears — still under `session == .transcribing`, so the
   overlay stays in its transcribing state for both steps.
4. Once done, the control card shows "Transcripción lista". The text
   appears in the last-transcript card, with copy/clear actions and an
   optional one-slot recovery banner. It can be edited by hand. Recording again
   while there's an existing transcript starts immediately (no confirmation) and
   replaces it; only "Limpiar" asks for confirmation (see
   [docs/DECISIONS.md](docs/DECISIONS.md) for why).
5. Once the model is installed, "Ver en Finder" opens the folder where it
   lives on disk.
6. Holding Fn anywhere in macOS — not just with Scribe's window
   focused — starts recording, exactly as if the "Grabar" button had been
   pressed; releasing it stops and starts transcription, push-to-talk style
   (Whispr's default shortcut). Tapping Fn twice quickly instead locks
   recording on without holding it down (hands-free); a third tap stops it.
   The shortcut is **background-first**: it never brings Scribe's window to
   the front or steals focus from whichever app you're dictating into. A
   small floating overlay near the bottom of the screen shows
   recording/transcribing feedback instead, and a menu bar item is always
   available as an alternative way to start/stop, show the window, or copy
   the last transcript.
7. As soon as the final text is ready (formatted or literal), Scribe
   automatically pastes it into whichever app was focused right before you
   started dictating — see "Auto-paste" below. "Copiar" keeps working exactly
   as before regardless of whether the auto-paste succeeded.

### Transcript formatting

After Whisper produces a literal transcript, Scribe can optionally run it through
Apple's on-device Foundation Models to clean it up:

- **What it does.** Removes conversational fillers ("o sea", "eh", …), stutters,
  and accidental repetitions; fixes punctuation and capitalization. Two tone
  profiles — **Casual** and **Formal** — adjust style; both always clean the
  text (there is no "literal only" profile — turn formatting off for that).
- **Default.** Formatting is **on** at first launch. If Apple Intelligence is
  unavailable or the model throws, Scribe silently keeps the literal Whisper
  output — same non-blocking philosophy as auto-paste.
- **Controls.** Toggle and profile picker live in the **settings menu** (gear in
  the identity bar) and the **Reformateo** column of the system status footer.
  When formatting is on but Apple Intelligence isn't ready, the attention row
  shows "Reformateo necesita Apple Intelligence" with an "Abrir Ajustes" action.
- **Not a security boundary.** The formatting prompt treats all transcript text
  as content to clean, not as instructions to follow — best-effort, not a
  guarantee against prompt injection via dictated text.

Direct use of `FoundationModels` is confined to `TranscriptFormattingService`
and `AppleIntelligenceAvailability`; the rest of the app only sees the
`TranscriptFormatting` protocol.

### Global Fn shortcut and Input Monitoring permission

A single `CGEventTap` (`CGEvent.tapCreate` on `.cghidEventTap`, watching
`flagsChanged` — see [docs/DECISIONS.md](docs/DECISIONS.md)) watches the
`.function` modifier flag and fires on each rising/falling edge (Fn pressed /
Fn released), whether or not Scribe itself is focused. Unlike a plain
`NSEvent` monitor, a tap can *consume* the event instead of just observing
it — Scribe returns `nil` from the tap callback on a real trigger edge, which
is an attempt at keeping macOS's own system Fn action (see below) from also
seeing that same press.

macOS only delivers events to a `CGEventTap` if the app has been granted the
**Input Monitoring** permission (Ajustes del Sistema → Privacidad y seguridad
→ Monitoreo de entrada) — a different TCC permission from Accessibility, and
not the same one Auto-paste needs for its synthetic ⌘V (see "Auto-paste"
below; that one is unaffected by this). Scribe never shows a native
permission prompt for this itself — it only checks silently
(`IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`) and reflects the result in
the UI, so granting it is always the user's explicit choice from System
Settings.

If that permission hasn't been granted yet, holding Fn does nothing, and
Scribe shows setup guidance in the consolidated attention row ("Monitoreo de
entrada"), with an "Abrir Ajustes" button and a refresh control that
rechecks when the app becomes active again (e.g. after returning from
System Settings). Missing this permission is non-fatal: the
record/stop button in the main window always works regardless of it.

**Hands-free mode:** tapping Fn twice quickly (within `doubleTapWindow`,
which defaults to the system's double-click interval) locks recording on
without holding the key down; releasing while locked does nothing, and one
more tap stops it immediately. This adds that same short delay to *every*
normal push-to-talk release (not just double-taps), since Scribe has to wait
briefly to see whether a second tap is coming. See
[docs/DECISIONS.md](docs/DECISIONS.md) for the state machine.

**Known limitation — conflicts with macOS's own Fn action, suppression
unverified:** System Settings → Keyboard → "Press 🌐 Fn key to:" lets you bind
a bare Fn tap to a system action (change input source, show Emoji & Symbols,
start Dictation). That's the exact same gesture Scribe's shortcut listens
for. Scribe now *attempts* to suppress that system action via the event tap
described above, matching what Wispr Flow appears to do — but this hasn't
been confirmed on real hardware in this environment, so treat it as
best-effort, not a guarantee. If it doesn't work in practice, or you'd rather
not rely on it, set "Press 🌐 Fn key to:" to "Do Nothing" in System Settings →
Keyboard (the same requirement Whispr documents for its own default
shortcut) as a reliable fallback. If that's not viable for you,
`HotkeyModifierTrigger` in `GlobalHotkeyService.swift` is the point of change
to fall back to a different modifier (e.g. Control). Also unconfirmed on real
hardware across every keyboard model (see "Manual QA checklist" below).

### Auto-paste

Once a transcription succeeds, Scribe pastes it automatically into whichever app had focus right
before recording started — no manual "Copiar" + ⌘V needed. This only fires when dictation started
with some other app in front; starting a recording from Scribe's own "Grabar" button has nothing
to paste into, so nothing is attempted.

- **Target capture.** `AutoPasteServicing.captureTarget()` reads the frontmost app
  (`NSWorkspace.shared.frontmostApplication`) synchronously the instant recording starts — before
  any permission dialog or window activation could change which app is in front — and excludes
  Scribe itself.
- **Paste mechanism.** `LiveAutoPasteService` writes the transcript to the general pasteboard and
  synthesizes ⌘V with `CGEvent`, the same mechanism a real keypress would trigger, so it respects
  whatever paste handling the target app already has (rich text, undo, etc.). If the user switched
  to a different app while transcription was running, Scribe reactivates the *original* target app
  first (with a short settling delay) before sending ⌘V — a deliberate, narrow exception to the
  background-first philosophy described above, scoped to auto-paste only.
- **Clipboard preservation.** Whatever was on the clipboard before the auto-paste write is restored
  right after pasting, unless something else (almost always the user copying something new) wrote
  to the clipboard in the meantime — detected via the pasteboard's `changeCount` — in which case
  that newer content is left alone instead of being clobbered.
- **Secure fields.** If the focused element in the target app looks like a password field
  (`kAXSecureTextFieldSubrole`, checked via the Accessibility API), auto-paste is skipped silently:
  no keystroke, no clipboard write. This is best-effort — some toolkits (e.g. Electron) don't
  expose a subrole, so a secure field there won't be detected.
- **Permission reuse.** Auto-paste needs its own Accessibility permission for the synthetic ⌘V,
  separate from the Fn shortcut's Input Monitoring permission described above — granting one does
  not grant the other. If Accessibility isn't granted, auto-paste is silently skipped and "Copiar"
  remains the only way to get the text out, exactly as it worked before this feature existed.
- **Failure is silent but visible.** A skipped or failed auto-paste never shows a modal dialog. The
  floating overlay's "Listo" checkmark becomes "Pegado" after a successful paste; a short status
  line appears next to "Estado actual" in the menu bar's menu for outcomes worth mentioning (target
  app closed, permission missing, secure field, or the keystroke failing to post). Non-attempts (no
  target captured, empty transcript) show nothing at all, and the transcript/"Copiar" are never
  affected either way.
- **Turning it off.** "Pegado automático" is on by default and persisted across launches. Toggle it
  in the menu bar menu, the settings menu (gear), or the **Auto-pegado** column of the system
  status footer — all three stay in sync.
- **Stale results across sessions.** Transcribing and pasting are both async; if a new recording
  starts before a slow-resolving auto-paste from the previous session finishes, that late result is
  discarded instead of overwriting the new session's status.

See [docs/MVP5_AUTO_PASTE_PLAN.md](docs/MVP5_AUTO_PASTE_PLAN.md) for the implementation notes,
design trade-offs, and the full manual QA checklist for this feature.

### Window activation

Pressing the global shortcut (or the menu bar's start/stop items) never
brings Scribe's window to the front or changes its focus — see
[docs/DECISIONS.md](docs/DECISIONS.md) for why. Showing the window is a
separate, explicit, user-initiated action: `DictationViewModel.showMainWindow()`
calls `WindowActivationServicing.activateMainWindow()` and is wired to
"Mostrar Scribe" in the menu bar's menu (`Scribe/MenuBarContentView.swift`).

`LiveWindowActivationService` (`Scribe/WindowActivationService.swift`) calls
`NSApplication.shared.activate(ignoringOtherApps: true)`, unhides the app if
hidden, and deminiaturizes the window if it was minimized. If the window was
closed entirely, it falls back to reopening it via SwiftUI's `openWindow`
action (see [docs/DECISIONS.md](docs/DECISIONS.md) for the mechanism and its
known limitation).

## Architecture

| File | Responsibility |
|---|---|
| `ScribeApp.swift` | App entry point (`WindowGroup`) and the `openWindow` bridge for reopening a closed window. |
| `AppDelegate.swift` | Owns the single long-lived `DictationViewModel` and the `RecordingOverlayController`, independent of window lifecycle. |
| `ContentView.swift` | Thin wrapper around `ScribeMainView`. |
| `ScribeMainView.swift` | Main window layout: three calm zones — identity bar, hero dictation card + transcript, and system status footer. |
| `ScribeDesignTokens.swift` | Adaptive semantic colors (warm graphite/indigo), spacing, radii, typography, and motion tokens. |
| `ScribeCardStyle.swift` | Reusable `scribeCard()`, `scribeQuietSurface()`, and `scribeControlSurface()` modifiers. |
| `DictationControlCard.swift` | Hero dictation card: voice motif, large `PrimaryState` title, Fn shortcut, and a contextual record/stop action. |
| `LastTranscriptCard.swift` | Honest single-transcript section with empty state, editor, recovery, and actions. |
| `SystemStatusFooter.swift` | Quiet full-width footer: model, microphone, accessibility, auto-paste, formatting, privacy. |
| `SetupAttentionBanner.swift` | Compact consolidated attention row with recovery actions (mic, Input Monitoring, Accessibility, model, Apple Intelligence). |
| `SpeechSignalView.swift` | Shared voice-motif bars (hero size for the control card, compact size for the overlay). |
| `TranscriptEmptyState.swift` | Empty transcript placeholder with Fn hint. |
| `TranscriptRecoveryBanner.swift` | One-slot undo-replace inline affordance and restore action. |
| `TranscriptActionBar.swift` | Copy/clear actions for the last transcript, in the card header. |
| `DictationViewModel.swift` | App state, `PrimaryState` copy mapping, orchestration between services, formatting, and auto-paste. |
| `PermissionStatusController.swift` | Microphone permission status/request and Settings deep-links. |
| `AppleIntelligenceAvailability.swift` | Live check of Apple Intelligence / Foundation Models availability and Settings deep-link. |
| `TranscriptFormattingService.swift` | On-device transcript cleanup via `FoundationModels` (`TranscriptFormatting` protocol). |
| `TranscriptSessionController.swift` | Debounced transcript load/save. |
| `RecordingMeter.swift` | Elapsed time + input level polling while recording. |
| `TranscriptionAttemptCoordinator.swift` | Discards a stale/cancelled transcription result. |
| `RecordingDurationPolicy.swift` | Maps elapsed recording time to a warning level. |
| `MenuBarContentView.swift` | Menu bar icon (`MenuBarStatusIcon`) and menu (`MenuBarContentView`): start/stop, copy last transcript, show window, permission shortcuts, quit. |
| `RecordingOverlayController.swift` | Owns the non-activating `NSPanel` that shows the floating recording/transcribing/done overlay without stealing focus. |
| `RecordingOverlayView.swift` | SwiftUI content of the floating overlay capsule (level bars, cascading dots, checkmark). |
| `WindowActivationService.swift` | Brings Scribe's window to the front (`WindowActivationServicing`), used by `showMainWindow()` for the menu bar's "Mostrar Scribe". |
| `ScribeHeaderView.swift` | Identity bar: brand, one live state label, a quiet "Local" privacy tag, and the settings menu (formatting, auto-paste, permissions). |
| `RecordingFeedbackView.swift` | Elapsed time, level meter, and duration warnings while recording. |
| `TranscribingFeedbackView.swift` | Progress indicator and cancel button while transcribing. |
| `TranscriptEditorView.swift` | Editable transcript area with metadata when non-empty. |
| `AudioRecorderService.swift` | Records audio to a local WAV file (16 kHz, mono, 16-bit). |
| `GlobalHotkeyService.swift` | Global Fn `CGEventTap` (`GlobalHotkeyServicing`), its `HotkeyStatus`, and the double-tap-to-lock hands-free state machine. |
| `MicrophonePermissionManager.swift` | System microphone permission. |
| `ModelManager.swift` | Presence and explicit download of the WhisperKit model. |
| `TranscriptionService.swift` | Wraps WhisperKit to transcribe locally. |
| `ClipboardService.swift` | Copies text to the clipboard. |
| `AutoPasteService.swift` | Captures the pre-recording frontmost app and pastes a successful transcription into it via the clipboard + a synthetic ⌘V (`AutoPasteServicing`). |
| `AppError.swift` | Typed app error model and its category-to-message mapping. |

Direct use of WhisperKit is confined to `ModelManager` and
`TranscriptionService`; direct use of `FoundationModels` is confined to
`TranscriptFormattingService` and `AppleIntelligenceAvailability`.

### State model

`DictationViewModel` keeps a single `AppState` with four independent
dimensions instead of one flat "current mode" enum:

- `permission: MicrophonePermissionStatus` — microphone access.
- `model: ModelState` — `.missing` / `.downloading(progress:)` / `.installed`.
- `session: DictationSessionState` — `.idle`, `.requestingPermission`,
  `.startingRecording`, `.recording`, `.stoppingRecording`, `.transcribing`.
- `error: AppError?` — the last error, if any, independent of the other
  three (e.g. the model can be missing while an unrelated clipboard error
  is still showing).

While `session == .transcribing`, both Whisper inference and optional Apple
Intelligence formatting run back-to-back; the overlay and control card stay in
their transcribing presentation for the whole span.

`setupIssues` surfaces configuration gaps for the attention banner, in priority
order: microphone denied, Input Monitoring required, Accessibility required (only
when auto-paste is on), missing model, and Apple Intelligence unavailable (only
when formatting is on).

Every record/stop action, regardless of where it comes from (the button, the
global hotkey, or the menu bar), goes through a single entry point:
`handlePrimaryDictationAction(source: DictationActionSource = .userInterface)`.
It checks `isBusy` and `pendingConfirmation` before doing anything, so
rapid repeated calls (double-clicking the button, or holding down the
hotkey) can't start two recordings or transcribe twice.

Clearing a non-empty transcript is the one destructive, no-way-back action
left, so `clearTranscript()` doesn't do it directly: it sets
`pendingConfirmation = .clearTranscript`, which `ContentView` renders as a
confirmation alert, and only `confirmPendingAction()`/
`cancelPendingConfirmation()` resolve it. Recording again over a non-empty
transcript is *not* treated this way — see
[docs/DECISIONS.md](docs/DECISIONS.md) for why, and how `previousTranscript`
covers the same risk without a blocking dialog.

`PrimaryState` is a separate, derived mapping used only for the big title in
`DictationControlCard` — `.ready`, `.recording`, `.stoppingRecording`,
`.transcribing`, `.transcriptReady`, `.microphoneDenied`, `.missingModel`,
`.downloadingModel`, `.inputMonitoringRequired`, `.error(message)`. See
[docs/DECISIONS.md](docs/DECISIONS.md) for why it's kept separate from
`statusText` and how ties are broken between simultaneous blockers.

## Model

- Variant: `large-v3-v20240930_626MB` (repo `argmaxinc/whisperkit-coreml`).
- New downloads go to `~/Library/Application Support/Scribe/Models`
  (`StoragePaths.currentModelsDirectory`).
- If the model was already downloaded by a previous version of the app
  (under `~/Library/Application Support/LocalDictate/Models`), it is **read
  in place, not copied or moved**. Copying a ~626 MB file on every launch
  just to rename its parent folder isn't worth the disk churn and I/O risk,
  so `ModelManager` keeps whatever path is recorded in `UserDefaults`
  (`Scribe.modelFolderPath`, migrated from the legacy
  `LocalDictate.modelFolderPath` key the first time the app runs
  post-upgrade) and only ever writes *new* downloads under the current
  `Scribe` folder. Legacy model files are never deleted.
- Transcription language is fixed to Spanish (`TranscriptionService`).

## Transcript

- The last transcript is saved to
  `~/Library/Application Support/Scribe/last-transcript.txt`
  (`FileTranscriptStore`), with a small debounce so it doesn't write to disk
  on every keystroke. It's restored automatically when the app opens.
- If that file doesn't exist yet but a legacy one does
  (`~/Library/Application Support/LocalDictate/last-transcript.txt`, from a
  previous version of the app), it is **copied** (not moved) to the new
  path once, so it keeps working exactly like a normal transcript from then
  on. The legacy file is never deleted. If both exist, the current
  (`Scribe`) transcript always wins.
- `UserDefaults` stores small preferences (model path, formatting on/off,
  formatting profile, auto-paste on/off), never the transcript text itself.

## Storage migration (LocalDictate → Scribe)

- The visible app name is Scribe; the Bundle Identifier intentionally
  remains `com.localdictate.app` (see "Troubleshooting" below and
  [docs/DECISIONS.md](docs/DECISIONS.md) for why).
- All storage-path constants live in `StoragePaths.swift`.
- Existing `LocalDictate` data on disk is never deleted:
  - The transcript file is copied to the new `Scribe` path the first time
    the app runs without a current-path file, but the original stays put.
  - The downloaded model is read from wherever it already is (no copy); only
    new downloads land under the `Scribe` folder.
- Small `UserDefaults` keys (e.g. the installed model's folder path) are
  migrated from their `LocalDictate.*` name to a `Scribe.*` name the first
  time they're read; this only renames the preference entry, it never
  touches files on disk.

## Error handling

- Errors are modeled as a typed `AppError` (`AppError.swift`), with a fixed
  category (`microphonePermission`, `recording`, `transcription`, `model`,
  `storage`, `clipboard`, `unknown`) plus a Spanish user-facing message.
- The Spanish message is resolved in one place
  (`AppErrorCategory.defaultMessage`, optionally overridden per error site),
  so `DictationViewModel` doesn't inline error strings scattered across its
  catch blocks.
- Tests can assert on `AppError.category` instead of comparing message
  strings.
- `AudioRecorderService` implements `AVAudioRecorderDelegate` to detect
  when a recording stops on its own (another app taking the audio device,
  or an encoding error) instead of via `stopRecording()`. That interruption
  surfaces as a `.recording`-category `AppError` and moves `session` back
  to `.idle`, so the UI doesn't keep showing "Recording..." after audio
  has actually stopped.

## Troubleshooting

### macOS asks for microphone permission repeatedly, on every reinstall

Root cause: without a stable signing Team ID, every recompiled build has a
different signing identity, and TCC (macOS's permission system) can't
associate the granted permission with the next version of the app. Fixed by
signing with a fixed Team ID:

1. In Xcode, select the `Scribe` project (not the target) in the
   Project Navigator, then the **Signing & Capabilities** tab of the
   `Scribe` target.
2. Enable "Automatically manage signing" and pick your Apple ID / Team.
3. Confirm `project.yml` has `DEVELOPMENT_TEAM` set to that Team ID (you can
   also check it with `security find-identity -v -p codesigning`, or by
   inspecting an already-signed build with `codesign -dvvv Scribe.app`
   — the `TeamIdentifier` field shouldn't say `not set`).

What actually keeps the app's identity stable for TCC (and therefore avoids
the re-prompt) are three things, all already fixed in this repo:

- **Bundle Identifier**: `com.localdictate.app`, fixed in `project.yml`
  (`PRODUCT_BUNDLE_IDENTIFIER`), not recomputed per build. This stayed
  unchanged through the LocalDictate → Scribe rename on purpose (see
  [docs/DECISIONS.md](docs/DECISIONS.md)): TCC keys the microphone grant off
  the Bundle Identifier, not the display name or module name.
- **Team ID / signing certificate**: as long as there's a single valid
  "Apple Development" certificate in the keychain for that Team (`security
  find-identity -v -p codesigning` should list exactly one), Xcode always
  signs the same way. If more than one valid certificate ever shows up,
  Xcode may sign with a different one between builds, and that does reset
  the permission.
- **Build path (DerivedData)**: doesn't matter. TCC identifies the app by
  its code signature (Team ID + Bundle ID), not by the binary's path, so
  successive builds in `DerivedData` with different hashes don't trigger a
  new prompt as long as the signature doesn't change.

The only thing that does force a re-prompt even with this resolved is an
explicit `tccutil reset Microphone`, or revoking the development certificate
(for example, when reinstalling Xcode from scratch or switching Apple IDs).

### The microphone permission dialog never appears, not even an entry in Settings

Root cause: with `ENABLE_HARDENED_RUNTIME: YES`, macOS requires an explicit
entitlement to access protected resources like the microphone
(`com.apple.security.device.audio-input`), in addition to the
`NSMicrophoneUsageDescription` text. Without that entitlement, the TCC
dialog never even shows up — no attempt is logged in Settings either — and
the console may show something like `NSViewBridgeErrorCanceled`. Fixed by
adding the entitlement in `Scribe/Scribe.entitlements` (already
included in this repo) and pointing to it from `CODE_SIGN_ENTITLEMENTS` in
`project.yml`.

If you need to retry the permission flow from scratch during development:

```bash
tccutil reset Microphone com.localdictate.app
```

### Console messages like `ViewBridge ... NSViewBridgeErrorCanceled` or `Unable to obtain a task name port right`

Benign macOS noise (the `RemoteViewService`/`ViewBridge` subsystem used by
out-of-process system panels, and the debugger's attempt to attach to a
short-lived helper process). Apple's own message says as much: `benign
unless unexpected`. If the app works fine (recording, permission,
transcription), these don't indicate a real problem.

## Manual QA checklist

No screenshot-based or automated UI testing is used in this project — visual
and end-to-end checks are manual, run by a person on a real Mac. This list
consolidates the checks called out throughout this document:

- **Recording basics** — click the record button, speak, click again to
  stop; the transcript appears and "Copiar" puts it on the clipboard.
- **Fn (background-first)** — with another app focused (e.g. a
  text editor) and Scribe's window closed or minimized, hold Fn:
  recording should start with the floating overlay appearing near the bottom
  of the screen, and the other app should keep its focus/key window the
  whole time — Scribe's window must NOT come to the front or steal focus.
  Release Fn to stop and transcribe.
- **Fn hardware validation** — this hasn't been confirmed across every
  keyboard model. Repeat the check above on as many of these as you have
  access to, and note which ones were actually tried:
  - Built-in laptop keyboard (the most common case, and the most likely to
    already work correctly).
  - Apple Magic Keyboard.
  - A third-party keyboard, especially one without a dedicated Fn key.
  - A keyboard remapped through a tool like Karabiner-Elements, since
    remapping can change what modifier flag actually reaches Scribe.
  - If any of these fails: don't try to fix it by touching
    `LiveGlobalHotkeyService`'s event-matching logic directly — the modifier
    it checks for is a single `HotkeyModifierTrigger` value (`.function` by
    default; see [docs/DECISIONS.md](docs/DECISIONS.md)) injected at
    construction, so a confirmed hardware-specific fallback can be swapped in
    by passing a different `HotkeyModifierTrigger` to
    `LiveGlobalHotkeyService(trigger:)`, without touching the monitor or
    permission code around it. This is a code-level escape hatch, not a
    user-facing setting — a configurable shortcut is still out of scope (see
    [docs/ROADMAP.md](docs/ROADMAP.md)).
- **Fn system-action suppression (unverified, needs real hardware)** — with
  System Settings → Keyboard → "Press 🌐 Fn key to:" set to something other
  than "Do Nothing" (e.g. "Change Input Source"), hold Fn to dictate and
  observe whether that system action *also* fires. Scribe's `CGEventTap`
  attempts to consume the event and suppress it (see
  [docs/DECISIONS.md](docs/DECISIONS.md)) — this checklist item is what
  actually confirms whether that works in practice, since nothing in this
  development environment can test it. If the system action still fires
  anyway, that's the known fallback case: set "Press 🌐 Fn key to:" to
  "Do Nothing" and confirm only Scribe reacts.
- **Fn while Scribe itself is focused** — with Scribe's own window
  open and focused, confirm the shortcut still starts/stops recording (the
  `CGEventTap` covers both this and the other-app-focused case with the same
  mechanism) and that typing normally in the transcript editor is unaffected.
- **Double-tap-to-lock hands-free mode (unverified, needs real hardware)** —
  tap Fn twice quickly: recording should lock on and the overlay should stay
  in the recording state without holding the key down. Release Fn while
  locked: confirm recording does NOT stop. Tap Fn once more while locked:
  confirm it stops immediately and transcribes. Separately, do a normal
  single press-and-release (no second tap) and confirm it still stops and
  transcribes as before, just with a brief extra delay
  (`doubleTapWindow`/`NSEvent.doubleClickInterval`) before it does.
- **Floating overlay** — confirm it shows a mic-level indicator while
  recording (bars should react to actual mic input), a cascading-dots
  indicator while transcribing (including during formatting, if enabled), and
  a brief checkmark flash after a successful transcription that disappears
  on its own — "Pegado" if auto-paste succeeded, "Listo" otherwise; confirm
  it does NOT flash after a cancelled or failed transcription, or on app
  launch with a previously restored transcript.
- **Menu bar item** — confirm the icon changes between idle, recording,
  busy/transcribing, downloading, and needs-attention states; confirm
  "Iniciar dictado"/"Detener dictado", "Copiar última transcripción",
  "Mostrar Scribe", the "Pegado automático" toggle, and the permission/model
  shortcuts in the menu all work and stay in sync with the main window's own
  controls.
- **Auto-paste** — see the dedicated, more detailed checklist in
  [docs/MVP5_AUTO_PASTE_PLAN.md](docs/MVP5_AUTO_PASTE_PLAN.md); at minimum,
  confirm a dictation started from another app pastes into that app
  automatically, "Copiar" still works regardless of the paste outcome, and
  toggling "Pegado automático" off (from the menu bar, settings menu, or
  footer) actually stops the paste from happening.
- **Transcript formatting** — with formatting on and Apple Intelligence
  available, dictate a filler-heavy phrase and confirm the result is cleaned
  up (not a verbatim Whisper dump). Switch between Casual and Formal in the
  settings menu and confirm tone shifts without changing meaning. Turn
  formatting off in the footer toggle and confirm the next dictation keeps
  literal Whisper output. With formatting on but Apple Intelligence disabled,
  confirm the attention row appears, dictation still works, and the literal
  text is kept.
- **Footer toggles** — confirm the Auto-pegado and Reformateo switches in
  the system status footer stay in sync with the settings menu and menu bar.
- **Instant replace + undo** — with a transcript already showing, record
  again (button or hotkey): it should start immediately with no dialog. Once
  transcribed, a "Deshacer reemplazo" pill should appear; clicking it should
  bring back the previous text and make the pill disappear.
- **Clear confirmation** — with a non-empty transcript, click "Limpiar": it
  should ask for confirmation before actually clearing.
- **Model missing/downloading** — with the model not installed, confirm the
  "Descargar modelo..." button and progress bar behave as described in
  "Model" above, and that recording still works before the model finishes
  downloading (only transcribing needs it).
- **Microphone permission denied** — deny the permission (System Settings)
  and confirm the app shows the blocked state with a working "Abrir Ajustes
  del Sistema" button, without crashing or getting stuck.
- **Input Monitoring permission required** — revoke Input Monitoring for
  Scribe and confirm the attention row shows recovery UI ("Abrir Ajustes" /
  refresh), and that the record button still works even though the global
  shortcut doesn't. Granting it back and reactivating the app should clear
  the recovery UI without restarting Scribe.
- **Visual pass** — at the window's minimum size, confirm the hero card,
  transcript card, and system status footer don't clip or overlap, and check
  both light and dark appearance (System Settings > Appearance).
- **App icon** — confirm the Dock icon, Cmd-Tab switcher, and Finder all
  show the new icon (not the default Swift/Xcode placeholder), and that it
  stays legible at the smallest sizes.

## Known limitations

- Spanish only; no language selector or auto-detection.
- Error handling is basic: messages are shown as text, with no automatic
  retries beyond leaving the buttons available to try again.
- Each transcription replaces the previous one; there's no append mode or
  history of past transcriptions. There's a single-slot, in-memory "undo
  replace" (`previousTranscript`, see [docs/DECISIONS.md](docs/DECISIONS.md)),
  but it only remembers the one transcript that was just overwritten, not a
  running history, and it's lost on app restart by design.
- Cancelling an in-progress transcription is "soft": WhisperKit doesn't
  expose a way to abort inference midway, so the app only guarantees
  discarding the result once it arrives, not stopping the computation
  earlier.
- No model selector: it always uses the same WhisperKit model fixed in
  `ModelManager`.
- No live transcription while recording; the floating overlay shows
  recording/transcribing feedback, not a partial transcript.
- The global shortcut is fixed to Fn; it isn't configurable and there's no
  alternative combo or side (left/right).
- Scribe attempts to suppress macOS's own "Press 🌐 Fn key to:" system action
  via a `CGEventTap` so it doesn't also fire alongside Scribe's shortcut, but
  this has **not been verified on real hardware** — this environment can't
  run the app to confirm it. If it doesn't work in practice, setting
  "Press 🌐 Fn key to:" to "Do Nothing" remains the reliable fallback — see
  the known limitation above.
- The double-tap-to-lock hands-free mode adds a short delay (defaults to the
  system's double-click interval) to every push-to-talk release, not just
  actual double-taps, so recording stops slightly later than it would
  without that mode. Whether that delay feels right on a keyboard (as
  opposed to the mouse double-click it borrows its default from) is also
  unverified on real hardware.
- The global shortcut now requires the **Input Monitoring** permission
  instead of Accessibility (Auto-paste still needs Accessibility separately,
  for its own synthetic ⌘V — see "Auto-paste" above).
- The floating overlay always positions itself on `NSScreen.main`; on a
  multi-monitor setup it won't follow the display the user is currently
  working on.
- Auto-paste's reactivation/clipboard-restore delays are fixed heuristics
  (120ms/200ms), not measured across a representative set of real apps or
  hardware; secure-field detection is best-effort and misses toolkits that
  don't expose an Accessibility subrole (e.g. some Electron apps); clipboard
  restore only preserves plain text, not other content types; and the
  "Pegado automático" toggle is global, with no per-app configuration. See
  [docs/MVP5_AUTO_PASTE_PLAN.md](docs/MVP5_AUTO_PASTE_PLAN.md) for the full
  list.
- **Formatting** depends on Apple Intelligence being enabled on a supported
  Mac; there is no cloud fallback and no "tone only, no cleanup" profile —
  disable formatting entirely to keep literal Whisper output. Formatting
  errors fall back silently to the raw transcript. The cleanup prompt is
  best-effort against instruction-like content in dictated text, not a
  security guarantee.

## Learn more

- [docs/DECISIONS.md](docs/DECISIONS.md) — the *why* behind non-obvious design choices.
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — how Scribe got to its current shape, phase by phase.
- [docs/MVP5_AUTO_PASTE_PLAN.md](docs/MVP5_AUTO_PASTE_PLAN.md) — auto-paste's design trade-offs, implementation notes, and manual QA checklist.
- [docs/ROADMAP.md](docs/ROADMAP.md) — tentative next steps (live transcription, transcript history, a configurable shortcut, hold-to-talk, a model/language selector, distribution).
