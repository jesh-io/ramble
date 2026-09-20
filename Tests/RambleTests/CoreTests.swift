import XCTest
import RambleCore
import RambleClean
import RambleProviders
@testable import RambleSTTElevenLabs

final class CoreTests: XCTestCase {
    func testMinimalConfigDefaultsToPrivateStorage() throws {
        let config = try JSONDecoder().decode(RambleConfig.self, from: Data("{}".utf8))
        XCTAssertFalse(config.analyticsEnabled)
        XCTAssertFalse(config.recordings.enabled)
        XCTAssertFalse(config.recordings.historyEnabled)
        XCTAssertEqual(config.stt.provider, "apple")
    }
    func testOldStorageSettingsSurvive() throws {
        let config = try JSONDecoder().decode(RambleConfig.self, from: Data(#"{"recordings":{"enabled":true,"retentionHours":12}}"#.utf8))
        XCTAssertTrue(config.recordings.enabled)
        XCTAssertEqual(config.recordings.retentionHours, 12)
        XCTAssertFalse(config.recordings.historyEnabled)
    }
    func testGestureDefaultIsThreeFingerTripleTap() throws {
        let config = try JSONDecoder().decode(RambleConfig.self, from: Data("{}".utf8))
        XCTAssertTrue(config.gesture.enabled)
        XCTAssertEqual(config.gesture.fingers, 3)
        XCTAssertEqual(config.gesture.taps, 3)
    }
    func testPre011ConfigIsMarkedForTheGestureDefault() throws {
        // No `gestureDefaultApplied` key: written before gestures shipped,
        // so `load()` adopts the new default once. A file that has the key
        // keeps whatever the user chose.
        let legacy = try JSONDecoder().decode(
            RambleConfig.self, from: Data(#"{"gesture":{"enabled":false,"fingers":3,"taps":2,"tapToEnter":true}}"#.utf8))
        XCTAssertFalse(legacy.gestureDefaultApplied)
        let chosen = try JSONDecoder().decode(
            RambleConfig.self,
            from: Data(#"{"gestureDefaultApplied":true,"gesture":{"enabled":false,"fingers":3,"taps":2,"tapToEnter":true}}"#.utf8))
        XCTAssertTrue(chosen.gestureDefaultApplied)
        XCTAssertFalse(chosen.gesture.enabled)
    }
    func testSpokenFormatting() {
        XCTAssertEqual(SpokenCommands.apply(to: "hello new paragraph world"), "Hello\n\nWorld")
    }
    func testVocabularyCorrection() {
        XCTAssertEqual(Vocabulary.applyKnownMishearings(to: "use rumble today", vocabulary: ["Ramble (misheard: rumble)"]), "use Ramble today")
    }
    func testGuardRejectsInventedAnswer() {
        let raw = "Can you explain how this works?"
        let result = CleanupValidator.guardOutput(raw: raw, cleaned: "The system uses artificial intelligence to automatically create a detailed answer for you.", maxInsertedRun: 3)
        XCTAssertTrue(result.rejected)
        XCTAssertEqual(result.text, raw)
    }
    func testUnavailableProvidersCannotBeSelected() {
        var config = RambleConfig.default
        config.accounts = [APIAccount(id: "test", provider: "elevenlabs")]
        XCTAssertEqual(ProviderRegistry.sttProviders(config).map(\.id), ["apple"])
    }
    func testElevenLabsParsingFixtures() { XCTAssertEqual(ElevenLabsSelfTest.run(), []) }
    func testPrivateFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sample.json")
        try PrivateFiles.write(Data("{}".utf8), to: file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
