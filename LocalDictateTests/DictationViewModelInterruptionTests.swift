import XCTest
@testable import LocalDictate

/// Cubre la Fase 8: una interrupción de grabación reportada por `AudioRecordingServicing`
/// (delegate de AVAudioRecorder en la implementación real) se convierte en un `AppError`
/// tipado y devuelve la sesión a `.idle`, sin depender de hardware de audio real.
@MainActor
final class DictationViewModelInterruptionTests: XCTestCase {
    private func makeViewModel(
        audioRecorder: FakeAudioRecordingService = FakeAudioRecordingService()
    ) -> DictationViewModel {
        DictationViewModel(
            audioRecorder: audioRecorder,
            modelManager: FakeModelManager(),
            microphonePermissionManager: FakeMicrophonePermissionManager(),
            clipboardService: FakeClipboardService(),
            transcriptStore: FakeTranscriptStore(),
            transcriptionService: FakeTranscriptionService()
        )
    }

    func testInterruptionWhileRecordingSurfacesTypedErrorAndReturnsToIdle() async {
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(audioRecorder: audioRecorder)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .recording)

        audioRecorder.simulateInterruption()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertEqual(viewModel.state.error?.category, .recording)
        XCTAssertEqual(viewModel.inputLevel, 0)
    }

    func testInterruptionWithUnderlyingErrorIsAlsoCategorizedAsRecording() async {
        struct SomeEncodingFailure: Error {}
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(audioRecorder: audioRecorder)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))

        audioRecorder.simulateInterruption(error: SomeEncodingFailure())
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(viewModel.state.error?.category, .recording)
    }

    func testInterruptionWhileNotRecordingHasNoEffect() {
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(audioRecorder: audioRecorder)

        audioRecorder.simulateInterruption()

        XCTAssertEqual(viewModel.state.session, .idle)
        XCTAssertNil(viewModel.state.error)
    }

    func testLateInterruptionAfterUserAlreadyStoppedDoesNotOverwriteState() async {
        let audioRecorder = FakeAudioRecordingService()
        let viewModel = makeViewModel(audioRecorder: audioRecorder)

        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.handlePrimaryDictationAction()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.state.session, .idle)

        audioRecorder.simulateInterruption()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertNil(viewModel.state.error)
        XCTAssertEqual(viewModel.state.session, .idle)
    }
}
