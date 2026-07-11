import XCTest
@testable import Scribe

@MainActor
final class TranscriptionAttemptCoordinatorTests: XCTestCase {
    func testSuccessfulTranscriptionReturnsTheText() async {
        let service = FakeTranscriptionService()
        service.transcribeResult = .success("hola mundo")
        let coordinator = TranscriptionAttemptCoordinator(transcriptionService: service)

        let outcome = await coordinator.transcribe(url: URL(fileURLWithPath: "/tmp/a.wav"))

        guard case .success(let text) = outcome else {
            return XCTFail("esperaba .success, fue \(outcome)")
        }
        XCTAssertEqual(text, "hola mundo")
    }

    func testFailedTranscriptionReturnsATypedError() async {
        let service = FakeTranscriptionService()
        service.transcribeResult = .failure(URLError(.badServerResponse))
        let coordinator = TranscriptionAttemptCoordinator(transcriptionService: service)

        let outcome = await coordinator.transcribe(url: URL(fileURLWithPath: "/tmp/a.wav"))

        guard case .failure = outcome else {
            return XCTFail("esperaba .failure, fue \(outcome)")
        }
    }

    func testExplicitCancelDiscardsALateResult() async {
        let service = FakeTranscriptionService()
        service.transcribeResult = .success("no debería llegar")
        service.delayMilliseconds = 100
        let coordinator = TranscriptionAttemptCoordinator(transcriptionService: service)

        let task = Task { await coordinator.transcribe(url: URL(fileURLWithPath: "/tmp/a.wav")) }
        try? await Task.sleep(for: .milliseconds(20))
        coordinator.cancel()

        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    func testStartingANewAttemptDiscardsTheStaleOne() async {
        let service = FakeTranscriptionService()
        service.transcribeResult = .success("primero")
        service.delayMilliseconds = 100
        let coordinator = TranscriptionAttemptCoordinator(transcriptionService: service)

        let staleTask = Task { await coordinator.transcribe(url: URL(fileURLWithPath: "/tmp/a.wav")) }
        try? await Task.sleep(for: .milliseconds(20))

        service.transcribeResult = .success("segundo")
        service.delayMilliseconds = 0
        let freshOutcome = await coordinator.transcribe(url: URL(fileURLWithPath: "/tmp/b.wav"))

        let staleOutcome = await staleTask.value
        XCTAssertEqual(staleOutcome, .cancelled)
        guard case .success(let text) = freshOutcome else {
            return XCTFail("esperaba .success, fue \(freshOutcome)")
        }
        XCTAssertEqual(text, "segundo")
    }
}
