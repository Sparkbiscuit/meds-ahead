import XCTest
@testable import Meds

/// The one-time move of the store into the app group container, on real
/// files in a scratch directory. Getting this wrong loses a person's history,
/// so every branch is exercised.
final class StoreLocationTests: XCTestCase {
    private var root: URL!
    private var legacy: URL!
    private var shared: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("store-location-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("legacy"), withIntermediateDirectories: true)
        legacy = root.appendingPathComponent("legacy/Meds.store")
        shared = root.appendingPathComponent("group/Meds.store")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ url: URL, _ bytes: Int) throws {
        try Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    func testAFreshInstallHasNothingToMove() {
        XCTAssertEqual(StoreLocation.migrate(from: legacy, to: shared), .nothingToMove)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path), "the app creates the store, not the move")
    }

    func testALegacyStoreMovesWithItsSidecarsAndTheOriginalsAreRetired() throws {
        try write(legacy, 4096)
        try write(URL(fileURLWithPath: legacy.path + "-wal"), 512)
        try write(URL(fileURLWithPath: legacy.path + "-shm"), 32_768)

        XCTAssertEqual(StoreLocation.migrate(from: legacy, to: shared), .moved)

        for suffix in StoreLocation.sidecarSuffixes {
            XCTAssertTrue(FileManager.default.fileExists(atPath: shared.path + suffix), suffix)
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path + suffix), "original \(suffix) still in place")
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path + StoreLocation.retiredSuffix + suffix), "retired \(suffix)")
        }
        XCTAssertEqual(try Data(contentsOf: shared).count, 4096)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: shared.path + "-wal")).count, 512, "the write-ahead log travels with the store")
    }

    func testAStoreWithoutSidecarsStillMoves() throws {
        try write(legacy, 2048)
        XCTAssertEqual(StoreLocation.migrate(from: legacy, to: shared), .moved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: shared.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path + "-wal"))
    }

    func testASharedStoreIsNeverTouchedAgain() throws {
        try FileManager.default.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(shared, 100)
        try write(legacy, 4096)

        XCTAssertEqual(StoreLocation.migrate(from: legacy, to: shared), .alreadyShared)
        XCTAssertEqual(try Data(contentsOf: shared).count, 100, "the shared store is the store; a leftover legacy file cannot replace it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "and the leftover is left alone")
    }

    func testAnEmptyLegacyFileIsNotTrustedAsACopy() throws {
        try write(legacy, 0)
        guard case .keptLegacy = StoreLocation.migrate(from: legacy, to: shared) else {
            return XCTFail("an empty file must not become the shared store")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path), "nothing left behind at the shared location")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testAnUnwritableGroupLocationKeepsTheLegacyStore() throws {
        try write(legacy, 4096)
        // A file where the group directory should be, so the directory cannot be made.
        try write(root.appendingPathComponent("group"), 1)

        guard case .keptLegacy = StoreLocation.migrate(from: legacy, to: shared) else {
            return XCTFail("expected the legacy store to be kept")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path + StoreLocation.retiredSuffix))
    }

    func testTheSecondLaunchFindsTheMoveDone() throws {
        try write(legacy, 4096)
        XCTAssertEqual(StoreLocation.migrate(from: legacy, to: shared), .moved)
        XCTAssertEqual(StoreLocation.migrate(from: legacy, to: shared), .alreadyShared)
    }
}
