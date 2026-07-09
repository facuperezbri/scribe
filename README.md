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

## Architecture

| File | Responsibility |
|---|---|
| `ScribeApp.swift` | App entry point (`WindowGroup`). |
| `ContentView.swift` | Main SwiftUI layout and confirmation dialogs. |
| `DictationViewModel.swift` | App state and orchestration between services. |
| `RecordingButton.swift` | Main Record/Stop button. |
| `RecordingFeedbackView.swift` | Elapsed time, level meter, and duration warnings while recording. |
| `TranscribingFeedbackView.swift` | Progress indicator and cancel button while transcribing. |
| `TranscriptEditorView.swift` | Editable transcript area, with placeholder and word/character counter. |
| `StatusBadgeView.swift` | Compact indicator of the app's current state. |
| `ModelStatusView.swift` | Model status (installed / downloading / not installed). |
| `PrivacyNoteView.swift` | Fixed privacy note at the bottom of the window. |
| `AudioRecorderService.swift` | Records audio to a local WAV file (16 kHz, mono, 16-bit). |
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
- No global keyboard shortcut, menu bar icon, or live transcription while
  recording (all of this is intentional: out of scope for this version and
  reserved for a future one).

## MVP3 readiness

MVP2.5 exists to make the global-hotkey work in MVP3 safe to add without
restructuring the app again. Concretely:

- The hotkey handler should call
  `DictationViewModel.handlePrimaryDictationAction(source: .globalHotkey)` —
  the same method the record/stop button already calls with
  `source: .userInterface` — instead of re-implementing start/stop/transcribe
  logic. This is what keeps the hotkey and the UI from getting out of sync
  (e.g. the hotkey starting a second recording while one is already running,
  or bypassing the replace/clear-transcript confirmation).
- State lives in one place (`AppState`, see "State model" above), so the
  hotkey doesn't need its own state machine; it reads and mutates the exact
  state the UI reads and mutates.

Remaining risks to resolve before wiring up the actual shortcut:

- `pendingConfirmation` (replace/clear transcript) is currently resolved
  through a SwiftUI alert bound to the main window. What a hotkey should do
  when it fires while that alert is pending — queue the action, ignore it,
  or bring the window forward — hasn't been decided yet.
- A global hotkey usually implies the app can act without its window being
  frontmost (or open at all). Permission prompts (`NSWorkspace`,
  microphone access) and the confirmation alerts above have only been
  exercised with the main window focused; their behavior when the app is
  backgrounded or windowless is untested.
- Audio interruption handling (see "Error handling") reverts to `.idle` and
  sets a typed error, but there's no menu bar icon or notification yet to
  surface that to a user who triggered the whole flow via keyboard only.

## Next steps (out of scope for this version)

Tentative roadmap for after MVP2, in priority order:

- **MVP3** — Global keyboard shortcut to record/stop without focusing the
  window, and automatic pasting of the result into whichever app was
  active.
- **MVP4** — Menu bar icon (menu bar extra) as an alternative way to use the
  app, without depending on the main window.
- **MVP5** — Live transcription while recording, instead of waiting for
  "Detener".
- **MVP6** — History of past transcriptions (today only the last one is
  persisted).
- **MVP7** — Model selector (choose between Whisper variants depending on
  the speed/accuracy trade-off each user prefers) and cleanup ahead of
  eventual distribution (custom app icon, etc.).
