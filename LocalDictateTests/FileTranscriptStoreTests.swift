import XCTest
@testable import LocalDictate

final class FileTranscriptStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalDictateTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("last-transcript.txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        fileURL = nil
        super.tearDown()
    }

    func testLoadReturnsNilWhenNoFileExistsYet() {
        let store = FileTranscriptStore(fileURL: fileURL)
        XCTAssertNil(store.loadTranscript())
    }

    func testSaveAndLoadRoundTrip() {
        let store = FileTranscriptStore(fileURL: fileURL)

        store.saveTranscript("hola mundo")

        XCTAssertEqual(store.loadTranscript(), "hola mundo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSavingEmptyStringRemovesTheFile() {
        let store = FileTranscriptStore(fileURL: fileURL)
        store.saveTranscript("algo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.saveTranscript("")

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(store.loadTranscript())
    }

    func testTranscriptPersistsAcrossStoreInstances() {
        FileTranscriptStore(fileURL: fileURL).saveTranscript("persistido")

        let reloaded = FileTranscriptStore(fileURL: fileURL).loadTranscript()

        XCTAssertEqual(reloaded, "persistido")
    }
}
