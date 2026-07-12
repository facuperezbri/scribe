# Scribe

macOS desktop app that records speech in Spanish and transcribes it fully
on-device, using [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)
(Whisper on Core ML) from Argmax. There is no backend, no analytics or
telemetry, no login and no payments.

## Privacy

> Audio and text are processed locally on this Mac. Nothing is sent to
> servers. The only use of the internet is to download the model if it
> isn't installed yet.

This is the only network operation in the whole app: the initial download
of the Whisper model, triggered exclusively by the user via the "Descargar
modelo" button. `ModelManager` never downloads anything on its own; it only
reads disk to check whether the model is already installed.

## Requirements

- macOS 13 or later
- Xcode 15 or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- ~1 GB of free disk space for the model (`large-v3-v20240930_626MB`)

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
They don't require a real microphone, a model download, or WhisperKit: they
only exercise `DictationViewModel` (and the controllers it delegates to)
through fakes, by manipulating state directly.

From Xcode: ⌘U with the `Scribe` scheme (the tests are wired into its
test action).

From the terminal:

```bash
xcodegen generate
xcodebuild -project Scribe.xcodeproj -scheme Scribe \
  -configuration Debug -destination 'platform=macOS' test
```

## Usage

The window is a compact dictation utility, not a document editor: a header,
a central status area that's the main thing you look at, the record button,
a small transcript card, and a thin footer.

1. Press "Grabar" (or Fn + Espacio, see below) and speak in Spanish. While
   recording, the central status area shows a pulsing red indicator, the
   elapsed time, a meter for the microphone's input level (to confirm audio
   is being captured), and, past 2 and 5 minutes, a warning that the
   recording is getting long. Press "Detener" to stop.
2. The first time, the model (~626 MB) needs to be downloaded with the
   "Descargar modelo" button. Transcription of the pending recording starts
   automatically as soon as the download finishes.
3. While transcribing, the central status area shows "Transcribiendo
   localmente..." with an indeterminate progress indicator (WhisperKit
   doesn't expose incremental progress for this step) along with a
   "Cancelar" button. Cancelling is "soft": the app discards the result as
   soon as it arrives, but it can't guarantee WhisperKit will abort inference
   midway.
4. Once transcribed, the central area shows "Transcripción lista" with a
   prominent "Copiar" action. The text itself appears below in a smaller,
   secondary transcript card, with a word/character counter under it. It can
   be edited by hand, copied with the "Copiar" button next to "Limpiar", or
   cleared with "Limpiar". Recording again while there's an existing
   transcript starts immediately (no confirmation) and replaces it, showing
   a small "Deshacer reemplazo" button to bring the previous one back; only
   "Limpiar" still asks for confirmation, since it's the one way to lose text
   with no way back (see [docs/DECISIONS.md](docs/DECISIONS.md) for why).
5. Once the model is installed, "Ver en Finder" opens the folder where it
   lives on disk.
6. Pressing Fn + Espacio anywhere in macOS — not just with Scribe's window
   focused — starts recording, exactly as if the "Grabar" button had been
   pressed; pressing it again stops and starts transcription. Holding it
   down doesn't repeat-trigger it. The shortcut is **background-first**: it
   never brings Scribe's window to the front or steals focus from whichever
   app you're dictating into. A small floating overlay near the top of the
   screen shows recording/transcribing feedback instead, and a menu bar item
   is always available as an alternative way to start/stop, show the
   window, or copy the last transcript.
7. As soon as that transcription is ready, Scribe automatically pastes it
   into whichever app was focused right before you started dictating — see
   "Auto-paste" below. "Copiar" keeps working exactly as before regardless
   of whether the auto-paste succeeded.

### Global Fn + Espacio shortcut and Accessibility permission

A global event monitor (`NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`,
plus a local one for when Scribe itself is focused — see
[docs/DECISIONS.md](docs/DECISIONS.md)) checks for Space (keyCode 49) with the
`.function` modifier flag set and `isARepeat == false`. macOS only delivers
those events if the app has been granted the **Accessibility** permission
(Ajustes del Sistema → Privacidad y seguridad → Accesibilidad). Scribe never
shows the native Accessibility prompt itself (`AXIsProcessTrustedWithOptions`
is not used) — it only checks silently with `AXIsProcessTrusted()` and
reflects the result in the UI, so granting the permission is always the
user's explicit choice from System Settings, not something the app pushes on
launch.

If that permission hasn't been granted yet, pressing Fn + Espacio does
nothing, and Scribe shows a small status message next to the model status
explaining why ("Para usar Fn + Espacio desde cualquier app, Scribe necesita
permiso de Accesibilidad."), with an "Abrir Ajustes" button that opens the
Accessibility privacy pane directly, and a "Revisar permiso" button to
recheck without restarting the app. The status also rechecks automatically
whenever the app becomes active again (e.g. after returning from System
Settings). Missing this permission is non-fatal: the record/stop button in
the main window always works regardless of it.

**Known limitation:** Fn combined with certain keys (arrows, Delete, F-keys)
is intercepted by the keyboard driver for built-in system functions before it
reaches any app as a modifier flag, so not every Fn+key combination is
observable this way. Space isn't one of the reassigned keys, so Fn + Espacio
is expected to arrive as a normal `keyDown` with `.function` set — but this
hasn't been confirmed on real hardware across every keyboard model (see
"Manual QA checklist" below).

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
- **Permission reuse.** Auto-paste needs the same Accessibility permission the Fn + Espacio
  shortcut already requests above — no second prompt. If it isn't granted, auto-paste is silently
  skipped and "Copiar" remains the only way to get the text out, exactly as it worked before this
  feature existed.
- **Failure is silent but visible.** A skipped or failed auto-paste never shows a modal dialog. The
  floating overlay's "Listo" checkmark becomes "Pegado" after a successful paste; a short status
  line appears next to "Estado actual" in the menu bar's menu for outcomes worth mentioning (target
  app closed, permission missing, secure field, or the keystroke failing to post). Non-attempts (no
  target captured, empty transcript) show nothing at all, and the transcript/"Copiar" are never
  affected either way.
- **Turning it off.** The menu bar menu has a "Pegado automático" toggle, on by default and
  persisted across launches. There's no equivalent switch in the main window — the menu bar is the
  only place to change it.
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
| `ContentView.swift` | Main SwiftUI layout and confirmation dialogs. |
| `Metrics.swift` | Shared spacing/corner-radius constants and the `cardBackground()` view modifier. |
| `DictationViewModel.swift` | App state, `PrimaryState` copy mapping, and orchestration between services. |
| `PermissionStatusController.swift` | Microphone permission status/request and Settings deep-links. |
| `TranscriptSessionController.swift` | Debounced transcript load/save. |
| `RecordingMeter.swift` | Elapsed time + input level polling while recording. |
| `TranscriptionAttemptCoordinator.swift` | Discards a stale/cancelled transcription result. |
| `RecordingDurationPolicy.swift` | Maps elapsed recording time to a warning level. |
| `MenuBarContentView.swift` | Menu bar icon (`MenuBarStatusIcon`) and menu (`MenuBarContentView`): start/stop, copy last transcript, show window, permission shortcuts, quit. |
| `RecordingOverlayController.swift` | Owns the non-activating `NSPanel` that shows the floating recording/transcribing/done overlay without stealing focus. |
| `RecordingOverlayView.swift` | SwiftUI content of the floating overlay capsule (level bars, cascading dots, checkmark). |
| `WindowActivationService.swift` | Brings Scribe's window to the front (`WindowActivationServicing`), used by `showMainWindow()` for the menu bar's "Mostrar Scribe". |
| `ScribeHeaderView.swift` | Fixed header: app name and "Dictado local" line. |
| `DictationStatusView.swift` | Central status area: icon, `PrimaryState` title, and the recording/transcribing/copy feedback nested inside it. |
| `RecordingButton.swift` | Main Record/Stop button. |
| `RecordingFeedbackView.swift` | Elapsed time, level meter, and duration warnings while recording (nested in `DictationStatusView`). |
| `TranscribingFeedbackView.swift` | Progress indicator and cancel button while transcribing (nested in `DictationStatusView`). |
| `TranscriptEditorView.swift` | Editable transcript area, with placeholder and word/character counter. |
| `ModelStatusView.swift` | Model status (installed / downloading / not installed). |
| `HotkeyStatusView.swift` | Global Fn + Espacio shortcut status and Accessibility-permission recovery UI. |
| `PrivacyNoteView.swift` | Fixed privacy note at the bottom of the window. |
| `AudioRecorderService.swift` | Records audio to a local WAV file (16 kHz, mono, 16-bit). |
| `GlobalHotkeyService.swift` | Global Fn + Espacio monitor (`GlobalHotkeyServicing`) and its `HotkeyStatus`. |
| `MicrophonePermissionManager.swift` | System microphone permission. |
| `ModelManager.swift` | Presence and explicit download of the WhisperKit model. |
| `TranscriptionService.swift` | Wraps WhisperKit to transcribe locally. |
| `ClipboardService.swift` | Copies text to the clipboard. |
| `AutoPasteService.swift` | Captures the pre-recording frontmost app and pastes a successful transcription into it via the clipboard + a synthetic ⌘V (`AutoPasteServicing`). |
| `AppError.swift` | Typed app error model and its category-to-message mapping. |

Direct use of WhisperKit is confined to `ModelManager` and
`TranscriptionService`; the rest of the app doesn't know about that
dependency.

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
`DictationStatusView` — `.ready`, `.recording`, `.stoppingRecording`,
`.transcribing`, `.transcriptReady`, `.microphoneDenied`, `.missingModel`,
`.downloadingModel`, `.accessibilityRequired`, `.error(message)`. See
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
- `UserDefaults` is only used for small preferences (e.g. the installed
  model's path), never for the transcript text.

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
- **Fn + Espacio (background-first)** — with another app focused (e.g. a
  text editor) and Scribe's window closed or minimized, press Fn + Espacio:
  recording should start with the floating overlay appearing near the top
  of the screen, and the other app should keep its focus/key window the
  whole time — Scribe's window must NOT come to the front or steal focus.
  Press again to stop and transcribe.
- **Fn + Espacio hardware validation** — the exact combo hasn't been
  confirmed across every keyboard model (see
  [docs/DECISIONS.md](docs/DECISIONS.md) for why: Fn-reassigned keys like
  arrows are intercepted before reaching any app, and that's only confirmed
  to be a non-issue for Space in theory, not tested on hardware). Repeat the
  check above on as many of these as you have access to, and note which ones
  were actually tried:
  - Built-in laptop keyboard (the most common case, and the most likely to
    already work correctly).
  - Apple Magic Keyboard (with and without a dedicated Fn key — older/small
    Magic Keyboards don't have one).
  - A third-party keyboard with no dedicated Fn key at all.
  - A keyboard remapped through a tool like Karabiner-Elements, since
    remapping can change what keyCode/modifier combination actually reaches
    Scribe.
  - If any of these fails: don't try to fix it by touching
    `LiveGlobalHotkeyService`'s event-matching logic directly — the combo it
    checks for is a single `HotkeyTrigger` value (`.fnSpace` by default; see
    [docs/DECISIONS.md](docs/DECISIONS.md)) injected at construction, so a
    confirmed hardware-specific fallback can be swapped in by passing a
    different `HotkeyTrigger` to `LiveGlobalHotkeyService(trigger:)`,
    without touching the monitor or permission code around it. This is a
    code-level escape hatch, not a user-facing setting — a configurable
    shortcut is still out of scope (see
    [docs/ROADMAP.md](docs/ROADMAP.md)).
- **Fn + Espacio while Scribe itself is focused** — with Scribe's own window
  open and focused, confirm the shortcut still starts/stops recording (this
  is the local-monitor path, distinct from the global-monitor path used when
  another app has focus) and that typing normally in the transcript editor
  is unaffected.
- **Floating overlay** — confirm it shows a mic-level indicator while
  recording (bars should react to actual mic input), a cascading-dots
  indicator while transcribing, and a brief checkmark flash after a
  successful transcription that disappears on its own — "Pegado" if
  auto-paste succeeded, "Listo" otherwise; confirm it does NOT flash after a
  cancelled or failed transcription, or on app launch with a previously
  restored transcript.
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
  toggling "Pegado automático" off in the menu bar actually stops the paste
  from happening.
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
- **Accessibility permission required** — revoke Accessibility for Scribe
  and confirm `HotkeyStatusView` shows the recovery UI ("Abrir Ajustes" /
  "Revisar permiso"), and that the record button still works even though the
  global shortcut doesn't.
- **Visual pass** — at the window's minimum size, confirm the status card
  and transcript card don't clip or overlap, and check both light and dark
  appearance (System Settings > Appearance).
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
- The global shortcut is fixed to Fn + Espacio; it isn't configurable and
  there's no alternative combo.
- No "hold to talk" mode: the shortcut always toggles start/stop, it never
  records only while a key is held down.
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

## Learn more

- [docs/DECISIONS.md](docs/DECISIONS.md) — the *why* behind non-obvious design choices.
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — how Scribe got to its current shape, phase by phase.
- [docs/MVP5_AUTO_PASTE_PLAN.md](docs/MVP5_AUTO_PASTE_PLAN.md) — auto-paste's design trade-offs, implementation notes, and manual QA checklist.
- [docs/ROADMAP.md](docs/ROADMAP.md) — tentative next steps (live transcription, transcript history, a configurable shortcut, hold-to-talk, a model/language selector, distribution).
