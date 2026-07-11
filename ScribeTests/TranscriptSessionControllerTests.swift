import XCTest
@testable import Scribe

@MainActor
final class TranscriptSessionControllerTests: XCTestCase {
    func testLoadSavedTranscriptForwardsTheUnderlyingStore() {
        let store = FakeTranscriptStore()
        store.storedTranscript = "transcripción guardada"
        let controller = TranscriptSessionController(transcriptStore: store)

        XCTAssertEqual(controller.loadSavedTranscript(), "transcripción guardada")
    }

    func testScheduleSaveWritesToTheStoreAfterTheDebounce() async {
        let store = FakeTranscriptStore()
        let controller = TranscriptSessionController(transcriptStore: store)

        controller.scheduleSave("hola")
        XCTAssertNil(store.storedTranscript, "no debería escribir antes de que pase el debounce")

        try? await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(store.storedTranscript, "hola")
    }

    func testRapidScheduleSaveCallsOnlyPersistTheLastValue() async {
        let store = FakeTranscriptStore()
        let controller = TranscriptSessionController(transcriptStore: store)

        controller.scheduleSave("primero")
        controller.scheduleSave("segundo")

        try? await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(store.storedTranscript, "segundo")
    }
}
