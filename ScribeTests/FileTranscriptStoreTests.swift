import XCTest
@testable import Scribe

final class FileTranscriptStoreTests: XCTestCase {
    private var fileURL: URL!
    private var legacyFileURL: URL!

    override func setUp() {
        super.setUp()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScribeTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("current/last-transcript.txt")
        legacyFileURL = directory.appendingPathComponent("legacy/last-transcript.txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent().deletingLastPathComponent())
        fileURL = nil
        legacyFileURL = nil
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

    // MARK: - Migration from a legacy (LocalDictate) transcript file

    func testNoTranscriptWhenNeitherCurrentNorLegacyExist() {
        let store = FileTranscriptStore(fileURL: fileURL, legacyFileURL: legacyFileURL)
        XCTAssertNil(store.loadTranscript())
    }

    func testUsesCurrentTranscriptWhenOnlyCurrentExists() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? "actual".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = FileTranscriptStore(fileURL: fileURL, legacyFileURL: legacyFileURL)

        XCTAssertEqual(store.loadTranscript(), "actual")
    }

    func testMigratesFromLegacyTranscriptWhenOnlyLegacyExists() {
        try? FileManager.default.createDirectory(
            at: legacyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? "legado".write(to: legacyFileURL, atomically: true, encoding: .utf8)

        let store = FileTranscriptStore(fileURL: fileURL, legacyFileURL: legacyFileURL)

        XCTAssertEqual(store.loadTranscript(), "legado")
        // The legacy file must never be deleted as part of the migration.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFileURL.path))
    }

    func testCurrentTranscriptWinsWhenBothCurrentAndLegacyExist() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? "actual".write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.createDirectory(
            at: legacyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? "legado".write(to: legacyFileURL, atomically: true, encoding: .utf8)

        let store = FileTranscriptStore(fileURL: fileURL, legacyFileURL: legacyFileURL)

        XCTAssertEqual(store.loadTranscript(), "actual")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFileURL.path))
    }

    func testMigratedTranscriptBehavesLikeANormalTranscript() {
        try? FileManager.default.createDirectory(
            at: legacyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? "legado".write(to: legacyFileURL, atomically: true, encoding: .utf8)

        let store = FileTranscriptStore(fileURL: fileURL, legacyFileURL: legacyFileURL)
        XCTAssertEqual(store.loadTranscript(), "legado")

        store.saveTranscript("reemplazado")
        XCTAssertEqual(store.loadTranscript(), "reemplazado")

        store.saveTranscript("")
        XCTAssertNil(store.loadTranscript())
    }
}
