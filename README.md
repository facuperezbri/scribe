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

The window is a compact dictation utility, not a document editor: a header,
a central status area that's the main thing you look at, the record button,
a small transcript card, and a thin footer. See "Phase 8" below for the
reasoning behind that layout.

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
   with no way back. See "Phase 10" below for why.
5. Once the model is installed, "Ver en Finder" opens the folder where it
   lives on disk.
6. Pressing Fn + Espacio anywhere in macOS — not just with Scribe's window
   focused — starts recording, exactly as if the "Grabar" button had been
   pressed; pressing it again stops and starts transcription. Holding it
   down doesn't repeat-trigger it. Since MVP4, the shortcut is
   **background-first**: it never brings Scribe's window to the front or
   steals focus from whichever app you're dictating into. A small floating
   overlay near the top of the screen shows recording/transcribing feedback
   instead, and a menu bar item is always available as an alternative way to
   start/stop, show the window, or copy the last transcript — see "MVP4"
   below for both.

### Global Fn + Espacio shortcut and Accessibility permission

Scribe's global dictation trigger is Fn + Espacio (modeled after Wispr
Flow's default Mac shortcut), replacing the Option-alone trigger used
through Phase 8. Option alone was dropped because it collides with macOS's
Spanish dead-key accents (Option+E, Option+U, etc. for á/é/í/ó/ú, ü) —
holding Option to type an accented vowel would otherwise also toggle
recording. Fn + Espacio doesn't collide with any dead-key or system-reserved
combination.

The shortcut is implemented with the same mechanism as before, just a
different event mask: a global event monitor
(`NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`) checks for Space
(keyCode 49) with the `.function` modifier flag set and `isARepeat == false`.
macOS only delivers those events if the app has been granted the
**Accessibility** permission (Ajustes del Sistema → Privacidad y seguridad →
Accesibilidad) — the same single permission the Option-based version needed;
switching from `.flagsChanged` to `.keyDown` doesn't add a separate "Input
Monitoring" requirement, since both event masks go through the same
Accessibility-gated `NSEvent` API rather than a raw `CGEventTap`/
`IOHIDManager` tap. Scribe never shows the native Accessibility prompt itself
(`AXIsProcessTrustedWithOptions` is not used) — it only checks silently with
`AXIsProcessTrusted()` and reflects the result in the UI, so granting the
permission is always the user's explicit choice from System Settings, not
something the app pushes on launch.

`NSEvent.addGlobalMonitorForEvents` only delivers events destined for *other*
apps — as soon as Scribe itself becomes the active app (e.g. its window is
open and focused), the system stops routing those events to the global
monitor. MVP4 (Phase 1–2) added a second, local monitor
(`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`) that covers exactly
that complementary case, so Fn + Espacio keeps working whether another app or
Scribe itself currently has focus. The two dispatch paths are mutually
exclusive for the same physical key press (AppKit delivers an event through
one or the other, never both), so having both monitors installed doesn't
double-trigger the shortcut — both delegate to the same `handleKeyDown`
detection logic. Unlike the global monitor, the local one doesn't require the
Accessibility permission, and it returns the event unmodified so it never
swallows normal typing inside Scribe's own window.

If that permission hasn't been granted yet, pressing Fn + Espacio does
nothing, and Scribe shows a small status message next to the model status
explaining why ("Para usar Fn + Espacio desde cualquier app, Scribe necesita
permiso de Accesibilidad."), with an "Abrir Ajustes" button that opens the
Accessibility privacy pane directly, and a "Revisar permiso" button to
recheck without restarting the app. The status also rechecks automatically
whenever the app becomes active again (e.g. after returning from System
Settings). Missing this permission is non-fatal: the record/stop button in
the main window always works regardless of it.

Since MVP4 (Phase 3), pressing Fn + Espacio no longer brings Scribe's window
to the front — see "Window activation" below for why, and "MVP4" for the
floating overlay and menu bar item that replace the window as feedback/entry
points while dictating in the background.

**Known limitation:** Fn combined with certain keys (arrows, Delete, F-keys)
is intercepted by the keyboard driver for built-in system functions before it
reaches any app as a modifier flag, so not every Fn+key combination is
observable this way. Space isn't one of the reassigned keys, so Fn + Espacio
is expected to arrive as a normal `keyDown` with `.function` set — but this
hasn't been confirmed on real hardware across every keyboard model (see
"Manual QA" below).

### Window activation

Through MVP3, the global Fn + Espacio shortcut used to bring Scribe's window
to the front before recording, on the theory that the user should always see
what triggered. MVP4 (Phase 3) removed that: Scribe is meant to be used as a
background utility, so pressing Fn + Espacio now runs
`handlePrimaryDictationAction` directly, with no window activation at all —
identical to what the click-driven button path already did, since the window
is already the one the user just clicked in. Feedback while dictating in the
background comes instead from the floating overlay and the menu bar item
(see "MVP4" below), not from the main window popping up.

Window activation itself wasn't deleted, since showing the window on demand
is still useful — it just moved to an explicit, user-initiated entry point.
`DictationViewModel.showMainWindow()` (Phase 4) calls
`WindowActivationServicing.activateMainWindow()` and is wired to "Mostrar
Scribe" in the menu bar's menu (`Scribe/MenuBarContentView.swift`).

`LiveWindowActivationService` (`Scribe/WindowActivationService.swift`) calls
`NSApplication.shared.activate(ignoringOtherApps: true)`, unhides the app if
hidden, and deminiaturizes the window if it was minimized. `DictationViewModel`
lives in `AppDelegate` (`Scribe/AppDelegate.swift`), not as `ContentView`'s
`@StateObject`: closing the window used to deallocate the view model along
with it, which silently killed the global hotkey monitor (it captures `self`
as `weak`) until the app was relaunched. Owning it at the app level keeps the
monitor alive for as long as the app is running, independent of whether the
window is open, minimized, or closed.

If the window was closed entirely (no `NSWindow` left to reactivate),
`LiveWindowActivationService` falls back to a `reopenHandler` closure that
`ScribeApp` registers once, at launch, wrapping SwiftUI's
`@Environment(\.openWindow)` action for the `WindowGroup(id: "main")` scene.
Because it's a singleton `WindowGroup` (no associated per-window data type),
calling `openWindow(id:)` while a window already exists just brings that
window forward instead of creating a second one, so repeated activations
never produce duplicate windows.

## Architecture

| File | Responsibility |
|---|---|
| `ScribeApp.swift` | App entry point (`WindowGroup`) and the `openWindow` bridge for reopening a closed window. |
| `AppDelegate.swift` | Owns the single long-lived `DictationViewModel` and the `RecordingOverlayController`, independent of window lifecycle. |
| `ContentView.swift` | Main SwiftUI layout and confirmation dialogs. |
| `Metrics.swift` | Shared spacing/corner-radius constants and the `cardBackground()` view modifier. |
| `DictationViewModel.swift` | App state, `PrimaryState` copy mapping, and orchestration between services. |
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

Clearing a non-empty transcript is the one destructive, no-way-back action
left, so `clearTranscript()` doesn't do it directly: it sets
`pendingConfirmation = .clearTranscript`, which `ContentView` renders as a
confirmation alert, and only `confirmPendingAction()`/
`cancelPendingConfirmation()` resolve it. Recording again over a non-empty
transcript is *not* treated this way anymore — see "Phase 10" below for why,
and how `previousTranscript` covers the same risk without a blocking dialog.

`PrimaryState` (Phase 8) is a separate, derived mapping used only for the
big title in `DictationStatusView` — `.ready`, `.recording`,
`.stoppingRecording`, `.transcribing`, `.transcriptReady`,
`.microphoneDenied`, `.missingModel`, `.downloadingModel`,
`.accessibilityRequired`, `.error(message)`. It exists apart from
`statusText` (the ad hoc detail line set inline through the flow methods)
because the central area needs one fixed, predictable string per case,
not whatever intermediate text an async transition happened to set.
`DictationViewModel.primaryState` resolves it with a fixed priority: an
in-progress session (recording/transcribing/etc.) always wins, since it's
the most urgent live truth, even if the model is missing or Accessibility
isn't granted — neither blocks recording itself. Only at rest (`.idle`) do
permission/model/accessibility blockers and transcript-ready get checked,
in that order.

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

## Manual QA checklist

No screenshot-based or automated UI testing is used in this project — visual
and end-to-end checks are manual, run by a person on a real Mac. This list
consolidates the checks called out throughout this document (referenced
above as "Manual QA"/"Manual QA checklist"):

- **Recording basics** — click the record button, speak, click again to
  stop; the transcript appears and "Copiar" puts it on the clipboard.
- **Fn + Espacio (background-first)** — with another app focused (e.g. a
  text editor) and Scribe's window closed or minimized, press Fn + Espacio:
  recording should start with the floating overlay appearing near the top
  of the screen, and the other app should keep its focus/key window the
  whole time — Scribe's window must NOT come to the front or steal focus.
  Press again to stop and transcribe. Try it on more than one keyboard model
  if possible (built-in vs. Magic Keyboard vs. third-party), since Fn-key
  behavior can vary (see "MVP3").
- **Fn + Espacio while Scribe itself is focused** — with Scribe's own window
  open and focused, confirm the shortcut still starts/stops recording (this
  is the local-monitor path added in MVP4 Phase 1–2, distinct from the
  global-monitor path used when another app has focus) and that typing
  normally in the transcript editor is unaffected.
- **Floating overlay** — confirm it shows a mic-level indicator while
  recording (bars should react to actual mic input), a cascading-dots
  indicator while transcribing, and a brief checkmark "Listo" flash after a
  successful transcription that disappears on its own; confirm it does NOT
  flash "Listo" after a cancelled or failed transcription, or on app launch
  with a previously restored transcript.
- **Menu bar item** — confirm the icon changes between idle, recording,
  busy/transcribing, downloading, and needs-attention states; confirm
  "Iniciar dictado"/"Detener dictado", "Copiar última transcripción",
  "Mostrar Scribe", and the permission/model shortcuts in the menu all work
  and stay in sync with the main window's own controls.
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
  replace" (`previousTranscript`, see "Phase 10"), but it only remembers the
  one transcript that was just overwritten, not a running history, and it's
  lost on app restart by design.
- Cancelling an in-progress transcription is "soft": WhisperKit doesn't
  expose a way to abort inference midway, so the app only guarantees
  discarding the result once it arrives, not stopping the computation
  earlier.
- No model selector: it always uses the same WhisperKit model fixed in
  `ModelManager`.
- No live transcription while recording; the floating overlay (MVP4) shows
  recording/transcribing feedback, not a partial transcript.
- The global shortcut is fixed to Fn + Espacio; it isn't configurable and
  there's no alternative combo.
- No "hold to talk" mode: the shortcut always toggles start/stop, it never
  records only while a key is held down.
- The floating overlay always positions itself on `NSScreen.main`; on a
  multi-monitor setup it won't follow the display the user is currently
  working on.

## MVP3: global shortcut (originally Option, migrated to Fn + Espacio in Phase 9)

Scribe's global dictation trigger was originally the Option key alone,
pressed with no other modifier, from anywhere in macOS — not just with
Scribe's window focused. Phase 9 (below) replaced it with Fn + Espacio; see
"Global Fn + Espacio shortcut and Accessibility permission" above for the
current user-facing behavior and permission flow. The architectural notes
below (protocol shape, state ownership) are unchanged since MVP3 — only the
key-detection details changed, and are described as of Phase 9.

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
  clear-transcript confirmation).
- `LiveGlobalHotkeyService` registers a `keyDown` global monitor via
  `NSEvent.addGlobalMonitorForEvents` and fires the callback only when Space
  (keyCode 49) arrives with the `.function` modifier flag set and
  `isARepeat == false` (so holding Fn + Espacio doesn't repeat-trigger it),
  hopping to the main actor before calling back. Before Phase 9 this
  monitored `flagsChanged` instead, firing on the transition into exactly
  `[.option]`.
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
- Manual, real-device QA of the Fn + Espacio shortcut and the Accessibility
  permission flow (see the checklist in "Global Fn + Espacio shortcut and
  Accessibility permission") still needs a Mac with GUI/Accessibility access
  to fully exercise — automated tests only cover the key-detection logic
  with synthetic `NSEvent`s and the rest through fakes.

## Phase 7: window activation and app focus

Pressing the global shortcut no longer just toggles recording — it also
brings Scribe's window to the front first, from any app, so the confirmation
dialog (at the time, replace *or* clear transcript — replace confirmation
was later removed in Phase 10, only clear remains) and the
recording/transcribing feedback are always visible to the user who just
triggered them. See "Window activation" under Architecture for the
implementation (`WindowActivationServicing`, `AppDelegate` owning
`DictationViewModel`, the `openWindow` reopen bridge).

This closed the risk noted above in MVP3's "Remaining risks": the
confirmation used to need the window already visible to be answerable; now
the shortcut guarantees that before the confirmation can even appear.

Known limitation: reopening a fully-closed window depends on SwiftUI's
`openWindow(id:)` bridge being registered by `ContentView`'s `onAppear`
before the window is closed. Since that only runs once the window has
appeared at least once, this is reliable for the normal case (app launched
normally, window closed later) but hasn't been exercised for exotic startup
states (e.g. the window failing to open at all on first launch).

## Phase 8: compact dictation UI

The main window was redesigned to feel like a small dictation utility
instead of a document editor, following the interaction principles of
compact/fast/minimal/keyboard-first tools (not their branding, assets, or
copy): one obvious central state, strong recording/transcribing feedback,
and a transcript that's secondary rather than the dominant element.

- `ScribeHeaderView` is a static header (app name + "Dictado local"); it
  carries no live state, so there's exactly one place — the new
  `DictationStatusView` — that changes per state.
- `DictationStatusView` is the focal point: a large icon (color-coded and
  pulsing while recording) plus the `PrimaryState` title (see "State
  model"), with the existing `RecordingFeedbackView`/`TranscribingFeedbackView`
  nested inside it instead of living as separate siblings in `ContentView`.
  When the transcript is ready and nothing more urgent is happening, it
  also shows a prominent "Copiar" call to action.
- `TranscriptEditorView`'s minimum height dropped from 220 to 140 so it
  reads as a secondary card, not the dominant element; it kept its
  placeholder, word/character counter, and copy/clear buttons untouched (the
  confirmation flow itself was later simplified in Phase 10).
- `StatusBadgeView` was retired: `DictationStatusView`'s title + icon color
  now cover the same "what's going on" signal it used to provide, and
  keeping both was redundant chatter in a compact window.
- The footer (`ModelStatusView`, `HotkeyStatusView`, `PrivacyNoteView`)
  is unchanged in structure; only copy got trimmed (the hotkey hint read
  "Option para grabar/detener" at the time, the privacy note "Audio y texto
  se procesan localmente") to match the terser tone. The hotkey hint text was
  updated again in Phase 9 when the shortcut itself changed from Option to
  Fn + Espacio.
- The window's minimum size went from 440×580 to 380×460.

Deliberately out of scope for this phase (unchanged): auto-paste, menu bar
mode, hold-to-talk, a configurable shortcut, AI cleanup, history, a model
selector, and any always-on-top/floating panel behavior — the last one
would need real tradeoff analysis (losing normal window management vs.
staying reachable) that wasn't asked for here, so the window remains a
regular, non-floating window.

## Phase 9: Fn + Espacio global shortcut

Replaced the Option-alone global trigger with Fn + Espacio (modeled after
Wispr Flow's default Mac shortcut). Option alone was pulled because it
blocks normal use of Option for Spanish accents/dead keys (Option+E, etc.
for á/é/í/ó/ú) — every accented keystroke would otherwise also toggle
recording.

- `LiveGlobalHotkeyService` (`Scribe/GlobalHotkeyService.swift`) switched its
  global monitor from `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)`
  to `.keyDown`, firing the callback when Space (keyCode 49) arrives with the
  `.function` modifier flag and `isARepeat == false`. This mirrors what a
  physical Fn + Espacio press produces: Space isn't one of the keys macOS
  reassigns when combined with Fn (unlike arrows, Delete, or the F-row), so
  it reaches apps as an ordinary `keyDown` rather than being intercepted by
  the keyboard driver.
- The permission model is unchanged: both event masks go through the same
  `NSEvent` API, which macOS gates on the **Accessibility** permission alone
  (checked via `AXIsProcessTrusted()`, same as before). Switching to
  `.keyDown` does not introduce a separate "Input Monitoring" requirement,
  since that TCC category applies to raw `CGEventTap`/`IOHIDManager` taps,
  not to `NSEvent`'s higher-level global monitor.
- `handleKeyDown` (internal, not `private`) is directly unit-tested with
  synthetic `NSEvent`s built via `NSEvent.keyEvent(with:...)` — no real
  keyboard or OS-level event delivery involved — covering: Fn + Espacio
  fires once; Space alone, Fn + any other key, and Option + Espacio don't
  fire; and holding the combo down (`isARepeat == true`) doesn't
  repeat-fire. See `ScribeTests/GlobalHotkeyServiceTests.swift`.
- All UI copy that named "Option" (the ready-state hint, `HotkeyStatusView`'s
  active/permission-required text) now says "Fn + Espacio" instead. No other
  behavior changed: the hotkey service is still a "dumb" notifier behind
  `GlobalHotkeyServicing`, still wired to
  `handlePrimaryDictationAction(source: .globalHotkey)`, and window
  activation (see "Window activation" above) is unaffected.

Known limitation: the real Fn + Espacio detection was not exercised on
physical hardware as part of this change — there was no way to interact with
a live keyboard or take screenshots for visual QA in this environment (see
"Manual QA checklist" below, to be run by a person on a real Mac). Fn-key
behavior can vary slightly across keyboard models (Magic Keyboard vs.
built-in vs. third-party), so this is the main risk to validate before
relying on it.

## Phase 10: instant replace + undo buffer

A Wispr-Flow-style redesign pass. The previous flow blocked a new recording
behind a confirmation dialog ("Ya tenés una transcripción. Si grabás de
nuevo, se va a reemplazar...") whenever there was a non-empty transcript —
which fought the whole point of a fast, keyboard-first dictation tool: every
re-dictation needed a mouse click to dismiss a dialog first.

- `PendingConfirmation` dropped its `.replaceTranscript` case; only
  `.clearTranscript` remains. `handlePrimaryDictationAction(source:)` now
  calls `startRecordingIfPossible()` directly from `.idle`, with no branch
  on whether `transcript` is empty.
- In exchange, `DictationViewModel` added a single in-memory buffer,
  `previousTranscript: String?` (not persisted, not a history — see "Known
  limitations"). Right before a new transcription overwrites `transcript`
  inside `transcribe(url:)`, the old value (if non-empty) is saved there.
  `restorePreviousTranscript()` swaps it back and clears the buffer; it's a
  one-shot undo, not a stack.
- `ContentView` shows a small "Deshacer reemplazo" button whenever
  `previousTranscript != nil`, styled as a light accent-tinted pill (see
  "Phase 11") rather than a bordered button, to read as transient rather
  than a permanent action.
- "Limpiar" is unaffected: clearing a non-empty transcript still asks for
  confirmation, since it's the one action with no way back at all —
  `performClear()` also drops `previousTranscript`, since undoing a clear
  the user just confirmed would be confusing.

Known limitation: the undo buffer is a single slot, in memory only. It's
lost on app restart and only remembers the one transcript that was just
replaced — recording twice in a row without restoring loses the first one
for good. This is intentional (a low-friction safety net, not a history
product); a full history is tracked separately under "MVP6" below.

## Phase 11: visual polish pass

A layout/hierarchy pass with no behavior changes, aimed at making the
window read like a deliberate small utility instead of a first-draft
prototype.

- Added `Scribe/Metrics.swift`: shared spacing/corner-radius constants and
  a `cardBackground()` view modifier, replacing the ad hoc numbers each view
  used to define on its own (14, 10, 8, 6, 4...).
- The status area (icon, title, record button) and the transcript area
  (editor, undo, Copiar/Limpiar) are now each wrapped in a "card" —
  a rounded, subtly shadowed background — so they read as two clear blocks
  instead of a flat stack of rows.
- `DictationStatusView`'s title grew from `.title3.semibold` to
  `.title2.bold`, and its icon now sits on a soft tinted circle that pulses
  with it, making the central state the one thing that visibly commands
  attention. `ScribeHeaderView` shrank to a single footnote-sized line so it
  stops competing with that title.
- The "Deshacer reemplazo" button (Phase 10) was restyled from a bordered
  button into a small accent-tinted pill/capsule, to distinguish it from the
  persistent Copiar/Limpiar actions next to it.

## Phase 12: original app icon

Added a first app icon; the project previously shipped with
`ASSETCATALOG_COMPILER_APPICON_NAME` empty and no `Assets.xcassets` at all.

- The icon is an abstract equalizer/waveform mark (five rounded bars, center
  tallest) in white over a navy-to-teal diagonal gradient — original
  geometry, not derived from Wispr Flow's or any other app's mark.
- `Scripts/generate_icon.swift` is a standalone script (outside both Xcode
  targets, so it isn't compiled into the app) that builds the icon as a
  SwiftUI view and rasterizes it to a 1024×1024 PNG via `ImageRenderer`;
  `sips` then downscales that master into the 10 sizes macOS expects
  (16–512pt, 1x/2x) into `Scribe/Assets.xcassets/AppIcon.appiconset/`.
- `project.yml` now sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
  Since `sources: - path: Scribe` already covers anything dropped under
  `Scribe/`, no other xcodegen changes were needed.
- To regenerate or redesign the icon later: edit the `AppIconArtwork` view
  in `Scripts/generate_icon.swift`, rerun it with
  `swift Scripts/generate_icon.swift /tmp/icon-master.png`, then re-run the
  `sips` resize loop from this phase's implementation (or write a small
  script around it) to refresh the PNGs in `AppIcon.appiconset/`.

## MVP4: background-first dictation, menu bar item, and floating overlay

Turned Scribe from a window-first app into a menu bar/background-first
dictation utility, in the spirit of background dictation utilities like
Wispr Flow — a small always-available entry point, a global shortcut that
never steals focus, and a minimal floating indicator instead of a window
popping to the front. No third-party branding, assets, or exact UI was
copied; the icon, overlay design, and copy are original.

Phases:

- **Phase 1–2** — Detect Fn + Espacio via local and global `NSEvent`
  monitors (superseding the Option-only shortcut from MVP3/Phase 9 with the
  combo already documented above).
- **Phase 3** — Stop activating the main window on every hotkey press; see
  "Window activation" above for the before/after. This is the behavioral
  core of MVP4: the shortcut works identically whether Scribe's window is
  open, minimized, or fully closed, and never interrupts whatever app the
  user is dictating into.
- **Phase 4** — Add a menu bar status item (`MenuBarContentView.swift`):
  `MenuBarStatusIcon` shows a distinct SF Symbol per broad state (idle,
  recording, busy, downloading, needs attention), and its menu offers
  start/stop, copy last transcript, "Mostrar Scribe" (`showMainWindow()`),
  the model folder, permission shortcuts, and quit — all routed through the
  same `handlePrimaryDictationAction`/view-model methods the window's button
  already uses, so there's no separate menu-bar code path to keep in sync.
- **Phase 5** — Add the floating recording/transcribing/done overlay
  (`RecordingOverlayController.swift`, `RecordingOverlayView.swift`): a
  borderless, non-activating `NSPanel` shown via `orderFrontRegardless()`
  (never `orderFront`/`makeKey`, which would steal focus), driven purely by
  a computed `overlayPhase` on `DictationViewModel` so it can't fall out of
  sync with the rest of the app's state. A dedicated one-shot
  `lastTranscriptionOutcome` signal (cleared at the start of every
  recording) distinguishes "a transcription just finished successfully" —
  worth a brief "Listo" flash — from any other idle moment, like the app
  launching with a previously restored transcript still on screen.
- **Phase 6** — Visual polish: split the menu bar icon's "downloading model"
  case into its own symbol instead of sharing the idle waveform, added a
  short fade in/out to the overlay panel instead of an abrupt
  show/hide, and swept the app's copy for a stray non-ASCII ellipsis (the
  rest of the app's copy always uses literal "...").

Remaining risks:

- The overlay only supports `NSScreen.main`; see "Known limitations" above.
- The menu bar icon's state grouping is coarser than `PrimaryState`
  (several states share one symbol) — deliberately, since finer-grained
  distinctions aren't legible at menu-bar icon size.

## Next steps (out of scope for this version)

Tentative roadmap, in priority order:

- **MVP3** — Automatic pasting of the transcription result into whichever
  app was active before the shortcut was pressed (the global Fn + Espacio
  shortcut itself, its permission UX, and window activation are already
  implemented).
- **MVP5** — Live transcription while recording, instead of waiting for
  "Detener".
- **MVP6** — History of past transcriptions (today only the last one is
  persisted).
- **MVP7** — Model selector (choose between Whisper variants depending on
  the speed/accuracy trade-off each user prefers) and remaining cleanup
  ahead of distribution (notarization, DMG/installer, etc. — the app icon
  itself is already done, see "Phase 12").
