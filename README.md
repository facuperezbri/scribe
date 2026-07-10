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
only exercise `DictationViewModel`'s pure logic by manipulating its state
directly.

From Xcode: ⌘U with the `Scribe` scheme (the tests are wired into its
test action).

From the terminal:

```bash
xcodegen generate
xcodebuild -project Scribe.xcodeproj -scheme Scribe \
  -configuration Debug -destination 'platform=macOS' test
```

## Usage

1. Press "Grabar" and speak in Spanish. While recording, the app shows the
   elapsed time, a meter for the microphone's input level (to confirm audio
   is being captured), and, past 2 and 5 minutes, a warning that the
   recording is getting long. Press "Detener" to stop.
2. The first time, the model (~626 MB) needs to be downloaded with the
   "Descargar modelo" button. Transcription of the pending recording starts
   automatically as soon as the download finishes.
3. While transcribing, an indeterminate progress indicator is shown
   (WhisperKit doesn't expose incremental progress for this step) along with
   a "Cancelar" button. Cancelling is "soft": the app discards the result as
   soon as it arrives, but it can't guarantee WhisperKit will abort inference
   midway.
4. The transcribed text appears in the editable area, with a word/character
   counter below it. It can be edited by hand, copied with "Copiar", or
   cleared with "Limpiar". Recording again or clearing while there's an
   existing transcript asks for confirmation before replacing or deleting it.
5. Once the model is installed, "Ver en Finder" opens the folder where it
   lives on disk.
6. Pressing Option alone (with no other key) anywhere in macOS — not just
   with Scribe's window focused — brings Scribe to the front and starts
   recording; pressing Option again stops it and starts transcription,
   exactly as if the "Grabar"/"Detener" button had been pressed. Holding
   Option down doesn't repeat-trigger it. If Scribe's window is minimized,
   it's unminimized; if it was closed while the app kept running, pressing
   Option reopens it.

### Global Option shortcut and Accessibility permission

The Option shortcut is implemented with a global event monitor
(`NSEvent.addGlobalMonitorForEvents`), which macOS only delivers events to if
the app has been granted the **Accessibility** permission (Ajustes del
Sistema → Privacidad y seguridad → Accesibilidad). Scribe never shows the
native Accessibility prompt itself (`AXIsProcessTrustedWithOptions` is not
used) — it only checks silently with `AXIsProcessTrusted()` and reflects the
result in the UI, so granting the permission is always the user's explicit
choice from System Settings, not something the app pushes on launch.

If that permission hasn't been granted yet, pressing Option does nothing,
and Scribe shows a small status message next to the model status
explaining why ("Para usar Option desde cualquier app, Scribe necesita
permiso de Accesibilidad."), with an "Abrir Ajustes" button that opens the
Accessibility privacy pane directly, and a "Revisar permiso" button to
recheck without restarting the app. The status also rechecks automatically
whenever the app becomes active again (e.g. after returning from System
Settings). Missing this permission is non-fatal: the record/stop button in
the main window always works regardless of it.

Pressing Option also brings Scribe's window to the front, regardless of
which app currently has focus — see "Window activation" below.

### Window activation

When the global Option shortcut fires, `DictationViewModel` first asks
`WindowActivationServicing` to activate the app and bring its window to the
front, then runs the same `handlePrimaryDictationAction` the button uses —
so pressing Option always shows Scribe before deciding whether to record,
show the replace/clear confirmation, or just keep showing the transcribing
state. The click-driven button path never calls this, since the window is
already the one the user just clicked in.

`LiveWindowActivationService` (`Scribe/WindowActivationService.swift`) calls
`NSApplication.shared.activate(ignoringOtherApps: true)`, unhides the app if
hidden, and deminiaturizes the window if it was minimized. `DictationViewModel`
now lives in `AppDelegate` (`Scribe/AppDelegate.swift`), not as `ContentView`'s
`@StateObject`: closing the window used to deallocate the view model along
with it, which silently killed the global Option monitor (it captures `self`
as `weak`) until the app was relaunched. Owning it at the app level keeps the
monitor alive for as long as the app is running, independent of whether the
window is open, minimized, or closed.

If the window was closed entirely (no `NSWindow` left to reactivate),
`LiveWindowActivationService` falls back to a `reopenHandler` closure that
`ScribeApp` registers once, at launch, wrapping SwiftUI's
`@Environment(\.openWindow)` action for the `WindowGroup(id: "main")` scene.
Because it's a singleton `WindowGroup` (no associated per-window data type),
calling `openWindow(id:)` while a window already exists just brings that
window forward instead of creating a second one, so repeated Option presses
never produce duplicate windows.

## Architecture

| File | Responsibility |
|---|---|
| `ScribeApp.swift` | App entry point (`WindowGroup`) and the `openWindow` bridge for reopening a closed window. |
| `AppDelegate.swift` | Owns the single long-lived `DictationViewModel`, independent of window lifecycle. |
| `ContentView.swift` | Main SwiftUI layout and confirmation dialogs. |
| `DictationViewModel.swift` | App state and orchestration between services. |
| `WindowActivationService.swift` | Brings Scribe's window to the front (`WindowActivationServicing`) when the global shortcut fires. |
| `RecordingButton.swift` | Main Record/Stop button. |
| `RecordingFeedbackView.swift` | Elapsed time, level meter, and duration warnings while recording. |
| `TranscribingFeedbackView.swift` | Progress indicator and cancel button while transcribing. |
| `TranscriptEditorView.swift` | Editable transcript area, with placeholder and word/character counter. |
| `StatusBadgeView.swift` | Compact indicator of the app's current state. |
| `ModelStatusView.swift` | Model status (installed / downloading / not installed). |
| `HotkeyStatusView.swift` | Global Option shortcut status and Accessibility-permission recovery UI. |
| `PrivacyNoteView.swift` | Fixed privacy note at the bottom of the window. |
| `AudioRecorderService.swift` | Records audio to a local WAV file (16 kHz, mono, 16-bit). |
| `GlobalHotkeyService.swift` | Global Option-key monitor (`GlobalHotkeyServicing`) and its `HotkeyStatus`. |
| `MicrophonePermissionManager.swift` | System microphone permission. |
| `ModelManager.swift` | Presence and explicit download of the WhisperKit model. |
| `TranscriptionService.swift` | Wraps WhisperKit to transcribe locally. |
| `ClipboardService.swift` | Copies text to the clipboard. |
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

Every record/stop action, regardless of where it comes from, goes through
a single entry point:
`handlePrimaryDictationAction(source: DictationActionSource = .userInterface)`.
It checks `isBusy` and `pendingConfirmation` before doing anything, so
rapid repeated calls (double-clicking the button, or in the future a
hotkey held down) can't start two recordings or transcribe twice.
`DictationActionSource` exists so a future caller (MVP3's global hotkey)
identifies itself without duplicating the logic above — see "MVP3
readiness" below.

Replacing or clearing a non-empty transcript is a destructive action, so
`handlePrimaryDictationAction`/`clearTranscript` don't do it directly:
they set `pendingConfirmation` (`.replaceTranscript` / `.clearTranscript`),
which `ContentView` renders as a confirmation alert, and only
`confirmPendingAction()`/`cancelPendingConfirmation()` resolve it.

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
  remains `com.localdictate.app` (see "Troubleshooting" below for why).
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
  unchanged through the LocalDictate → Scribe rename on purpose: TCC keys
  the microphone grant off the Bundle Identifier, not the display name or
  module name, so changing it would have reset everyone's microphone
  permission for no functional benefit.
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

## Known limitations

- Spanish only; no language selector or auto-detection.
- No custom app icon.
- Error handling is basic: messages are shown as text, with no automatic
  retries beyond leaving the buttons available to try again.
- Each transcription replaces the previous one; there's no append mode or
  history of past transcriptions.
- Cancelling an in-progress transcription is "soft": WhisperKit doesn't
  expose a way to abort inference midway, so the app only guarantees
  discarding the result once it arrives, not stopping the computation
  earlier.
- No model selector: it always uses the same WhisperKit model fixed in
  `ModelManager`.
- No menu bar icon or live transcription while recording (out of scope for
  this version, reserved for a future one).
- The global shortcut is fixed to Option alone; it isn't configurable and
  there's no alternative combo.
- No "hold to talk" mode: the shortcut always toggles start/stop, it never
  records only while a key is held down.

## MVP3: global Option shortcut

Scribe's global dictation trigger is the Option key alone, pressed with no
other modifier, from anywhere in macOS — not just with Scribe's window
focused. See "Global Option shortcut and Accessibility permission" above for
the user-facing behavior and permission flow.

Implementation notes:

- `GlobalHotkeyServicing` (`Scribe/GlobalHotkeyService.swift`) is the
  protocol a hotkey service must implement: `start(onHotkeyPressed:)`,
  `stop()`, and `currentStatus() -> HotkeyStatus`. It only reports "the
  hotkey fired" or "this is its current status" — it has no opinion on what
  recording should do. `DictationViewModel` takes one as an injectable
  dependency (default `LiveGlobalHotkeyService()`, matching the pattern used
  for every other service) and wires its callback straight to
  `handlePrimaryDictationAction(source: .globalHotkey)` in `init` — the same
  method the record/stop button already calls with `source: .userInterface`
  — instead of re-implementing start/stop/transcribe logic. This is what
  keeps the hotkey and the UI from getting out of sync (e.g. the hotkey
  starting a second recording while one is already running, or bypassing the
  replace/clear-transcript confirmation).
- `LiveGlobalHotkeyService` registers a `flagsChanged` global monitor via
  `NSEvent.addGlobalMonitorForEvents` and fires the callback only on the
  transition into exactly `[.option]` (so holding Option doesn't
  repeat-trigger it), hopping to the main actor before calling back.
- `HotkeyStatus` (`.unknown` / `.active` / `.accessibilityPermissionRequired`
  / `.failed(String)`) is recalculated on every `currentStatus()` call, never
  cached — the monitor is installed unconditionally on `start`, regardless of
  the Accessibility permission, so if the user grants it later the shortcut
  starts working without an app restart, and the next `currentStatus()` call
  (e.g. when the app becomes active again) reflects `.active` right away.
- State lives in one place (`AppState`, see "State model" above), so the
  hotkey doesn't need its own state machine; it reads and mutates the exact
  state the UI reads and mutates. `hotkeyStatus` on `DictationViewModel` is a
  separate, independent piece of state purely for the shortcut's own
  status UI.

Remaining risks:

- Audio interruption handling (see "Error handling") reverts to `.idle` and
  sets a typed error, but there's no menu bar icon or notification yet to
  surface that to a user who triggered the whole flow via keyboard only.
- Manual, real-device QA of the Option shortcut and the Accessibility
  permission flow (see the checklist in "Global Option shortcut and
  Accessibility permission") still needs a Mac with GUI/Accessibility access
  to fully exercise — automated tests only cover it through fakes.

## Phase 7: window activation and app focus

Pressing Option no longer just toggles recording — it also brings Scribe's
window to the front first, from any app, so the confirmation dialog (replace/
clear transcript) and the recording/transcribing feedback are always visible
to the user who just triggered them. See "Window activation" under
Architecture for the implementation (`WindowActivationServicing`,
`AppDelegate` owning `DictationViewModel`, the `openWindow` reopen bridge).

This closed the risk noted above in MVP3's "Remaining risks": the
replace/clear-transcript confirmation used to need the window already
visible to be answerable; now the shortcut guarantees that before the
confirmation can even appear.

Known limitation: reopening a fully-closed window depends on SwiftUI's
`openWindow(id:)` bridge being registered by `ContentView`'s `onAppear`
before the window is closed. Since that only runs once the window has
appeared at least once, this is reliable for the normal case (app launched
normally, window closed later) but hasn't been exercised for exotic startup
states (e.g. the window failing to open at all on first launch).

## Next steps (out of scope for this version)

Tentative roadmap, in priority order:

- **MVP3** — Automatic pasting of the transcription result into whichever
  app was active before the shortcut was pressed (the global Option
  shortcut itself, its permission UX, and window activation are already
  implemented).
- **MVP4** — Menu bar icon (menu bar extra) as an alternative way to use the
  app, without depending on the main window.
- **MVP5** — Live transcription while recording, instead of waiting for
  "Detener".
- **MVP6** — History of past transcriptions (today only the last one is
  persisted).
- **MVP7** — Model selector (choose between Whisper variants depending on
  the speed/accuracy trade-off each user prefers) and cleanup ahead of
  eventual distribution (custom app icon, etc.).
