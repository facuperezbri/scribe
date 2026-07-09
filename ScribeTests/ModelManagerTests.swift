import XCTest
@testable import Scribe

final class ModelManagerTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var modelsDirectory: URL!

    override func setUp() {
        super.setUp()
        suiteName = "ModelManagerTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        modelsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScribeTests-\(UUID().uuidString)/Models", isDirectory: true)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: modelsDirectory.deletingLastPathComponent())
        userDefaults = nil
        modelsDirectory = nil
        super.tearDown()
    }

    func testNoInstalledModelWhenNothingWasEverDownloaded() {
        let manager = ModelManager(userDefaults: userDefaults, modelsDirectory: modelsDirectory)
        XCTAssertNil(manager.installedModelFolder)
        XCTAssertFalse(manager.isModelInstalled)
    }

    func testInstalledModelFolderResolvesFromLegacyDefaultsKeyWithoutMovingFiles() throws {
        let legacyModelFolder = modelsDirectory.deletingLastPathComponent()
            .appendingPathComponent("LegacyModels/large-v3", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyModelFolder, withIntermediateDirectories: true)
        userDefaults.set(legacyModelFolder.path, forKey: "LocalDictate.modelFolderPath")

        let manager = ModelManager(userDefaults: userDefaults, modelsDirectory: modelsDirectory)

        XCTAssertEqual(manager.installedModelFolder, legacyModelFolder)
        XCTAssertTrue(manager.isModelInstalled)
        // The legacy defaults entry is migrated to the current key, but the model files
        // themselves are never copied or moved.
        XCTAssertEqual(userDefaults.string(forKey: "Scribe.modelFolderPath"), legacyModelFolder.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyModelFolder.path))
    }

    func testCurrentDefaultsKeyIsNotOverwrittenWhenAlreadySet() throws {
        let currentModelFolder = modelsDirectory.appendingPathComponent("large-v3", isDirectory: true)
        try FileManager.default.createDirectory(at: currentModelFolder, withIntermediateDirectories: true)
        userDefaults.set(currentModelFolder.path, forKey: "Scribe.modelFolderPath")
        userDefaults.set("/some/stale/legacy/path", forKey: "LocalDictate.modelFolderPath")

        let manager = ModelManager(userDefaults: userDefaults, modelsDirectory: modelsDirectory)

        XCTAssertEqual(manager.installedModelFolder, currentModelFolder)
        XCTAssertEqual(userDefaults.string(forKey: "Scribe.modelFolderPath"), currentModelFolder.path)
    }

    func testInstalledModelFolderIsNilWhenStoredPathNoLongerExistsOnDisk() {
        userDefaults.set("/nonexistent/model/path", forKey: "Scribe.modelFolderPath")

        let manager = ModelManager(userDefaults: userDefaults, modelsDirectory: modelsDirectory)

        XCTAssertNil(manager.installedModelFolder)
        XCTAssertFalse(manager.isModelInstalled)
    }
}
