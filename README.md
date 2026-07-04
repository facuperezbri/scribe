# LocalDictate

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
open LocalDictate.xcodeproj
```

Then run the `LocalDictate` scheme from Xcode (⌘R).

It can also be built from the terminal:

```bash
xcodegen generate
xcodebuild -project LocalDictate.xcodeproj -scheme LocalDictate \
  -configuration Debug -destination 'platform=macOS' build
```

## Running the tests

The tests live in the `LocalDictateTests` target (unit tests, no UI tests).
They don't require a real microphone, a model download, or WhisperKit: they
only exercise `DictationViewModel`'s pure logic by manipulating its state
directly.

From Xcode: ⌘U with the `LocalDictate` scheme (the tests are wired into its
test action).

From the terminal:

```bash
xcodegen generate
xcodebuild -project LocalDictate.xcodeproj -scheme LocalDictate \
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
| `LocalDictateApp.swift` | App entry point (`WindowGroup`). |
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

## Model

- Variant: `large-v3-v20240930_626MB` (repo `argmaxinc/whisperkit-coreml`).
- Stored under `~/Library/Application Support/LocalDictate/Models`.
- Transcription language is fixed to Spanish (`TranscriptionService`).

## Transcript

- The last transcript is saved to
  `~/Library/Application Support/LocalDictate/last-transcript.txt`
  (`FileTranscriptStore`), with a small debounce so it doesn't write to disk
  on every keystroke. It's restored automatically when the app opens.
- `UserDefaults` is only used for small preferences (e.g. the installed
  model's path), never for the transcript text.

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

## Troubleshooting

### macOS asks for microphone permission repeatedly, on every reinstall

Root cause: without a stable signing Team ID, every recompiled build has a
different signing identity, and TCC (macOS's permission system) can't
associate the granted permission with the next version of the app. Fixed by
signing with a fixed Team ID:

1. In Xcode, select the `LocalDictate` project (not the target) in the
   Project Navigator, then the **Signing & Capabilities** tab of the
   `LocalDictate` target.
2. Enable "Automatically manage signing" and pick your Apple ID / Team.
3. Confirm `project.yml` has `DEVELOPMENT_TEAM` set to that Team ID (you can
   also check it with `security find-identity -v -p codesigning`, or by
   inspecting an already-signed build with `codesign -dvvv LocalDictate.app`
   — the `TeamIdentifier` field shouldn't say `not set`).

What actually keeps the app's identity stable for TCC (and therefore avoids
the re-prompt) are three things, all already fixed in this repo:

- **Bundle Identifier**: `com.localdictate.app`, fixed in `project.yml`
  (`PRODUCT_BUNDLE_IDENTIFIER`), not recomputed per build.
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
adding the entitlement in `LocalDictate/LocalDictate.entitlements` (already
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
