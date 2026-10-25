import Foundation
import XCTest

private final class KeyboardBackend: FunctionKeyMappingBackend {
    var devices: [KeyboardMappingDevice] = []
    var maps: [UInt64: [UInt64: UInt64]] = [:]
    var writes = 0
    var failRead = false
    var failWrite = false
    var failAfterWrite = false

    func keyboards() throws -> [KeyboardMappingDevice] { devices }
    func readMappings(deviceID: UInt64) throws -> [UInt64: UInt64] {
        if failRead { throw FunctionKeyMappingError.malformedMappings }
        return maps[deviceID] ?? [:]
    }
    func writeMappings(_ mappings: [UInt64: UInt64], deviceID: UInt64) throws {
        if failWrite { throw FunctionKeyMappingError.writeFailed }
        writes += 1
        maps[deviceID] = mappings
        if failAfterWrite { throw FunctionKeyMappingError.writeFailed }
    }
}

final class FunctionKeyMappingTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: FunctionKeyOverrideStore!
    private var backend: KeyboardBackend!
    private var engine: FunctionKeyMappingEngine!
    private let dictation: UInt64 = (12 << 32) | 0xcf
    private let mute: UInt64 = (12 << 32) | 0xe2

    override func setUp() {
        super.setUp()
        suite = "Fluor.FunctionKeyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = FunctionKeyOverrideStore(defaults: defaults, bootSession: "boot-a")
        backend = KeyboardBackend()
        backend.devices = [.init(id: 1, name: "Keyboard", mediaUsages: [.f5: dictation, .f10: mute])]
        engine = FunctionKeyMappingEngine(backend: backend, store: store)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    @objc func testParsesKeyboardSpecificUsageEncodings() {
        XCTAssertEqual(FunctionKeyMap.parseMediaUsages("0x0007003e,0x000c00cf"), [.f5: dictation])
        XCTAssertEqual(FunctionKeyMap.parseMediaUsages("0x70000003e,0xc000000cf"), [.f5: dictation])
        XCTAssertEqual(FunctionKeyMap.parseMediaUsages("0x0007003e,0x00ff0008")[.f5], (255 << 32) | 8)
        XCTAssertTrue(FunctionKeyMap.parseMediaUsages("0x0007003e,invalid").isEmpty)
        XCTAssertTrue(FunctionKeyMap.parseMediaUsages("0x0007003e").isEmpty)
        XCTAssertTrue(FunctionKeyMap.parseMediaUsages("0x0007003e,0x0007003e").isEmpty)
    }

    @objc func testAllTwelveKeysIgnoreGlobalModeAndFnInversion() {
        let media = Dictionary(uniqueKeysWithValues: FunctionKey.allCases.map { ($0, (12 << 32) | UInt64(0x100 + $0.rawValue)) })
        for key in FunctionKey.allCases {
            for choice in [FunctionKeyOverride.function, .media] {
                let map = FunctionKeyMap.generate(overrides: [key: choice], mediaUsages: media)
                XCTAssertTrue(map.unsupported.isEmpty)
                for globalMode in [false, true] {
                    for fnHeld in [false, true] {
                        // The native keyboard filter performs Fn/global-mode
                        // translation first, then applies UserKeyMapping once.
                        let input = globalMode == fnHeld ? media[key]! : key.usage
                        XCTAssertEqual(map.mappings[input], choice == .function ? key.usage : media[key]!)
                    }
                }
                XCTAssertEqual(map.mappings.count, 2)
            }
        }
    }

    @objc func testSimultaneousExceptionsAndUnsupportedKeys() {
        let result = FunctionKeyMap.generate(overrides: [.f5: .function, .f10: .media, .f12: .function],
                                            mediaUsages: [.f5: dictation, .f10: mute])
        XCTAssertEqual(result.mappings[dictation], FunctionKey.f5.usage)
        XCTAssertEqual(result.mappings[FunctionKey.f10.usage], mute)
        XCTAssertNil(result.mappings[FunctionKey.f1.usage])
        XCTAssertEqual(result.unsupported, [.f12])
    }

    @objc func testConflictingMediaAliasesAreNotGuessed() {
        let result = FunctionKeyMap.generate(overrides: [.f5: .function, .f10: .function],
                                            mediaUsages: [.f5: dictation, .f10: dictation])
        XCTAssertTrue(result.mappings.isEmpty)
        XCTAssertEqual(result.unsupported, [.f5, .f10])
    }

    @objc func testInvalidMediaIdentityIsUnsupported() {
        let result = FunctionKeyMap.generate(overrides: [.f5: .function], mediaUsages: [.f5: FunctionKey.f5.usage])
        XCTAssertTrue(result.mappings.isEmpty)
        XCTAssertEqual(result.unsupported, [.f5])
    }

    @objc func testPreferencesRoundTripAndReset() {
        XCTAssertTrue(store.overrides.isEmpty)
        store.overrides = [.f5: .function, .f10: .media, .f1: .followMode]
        let reloaded = FunctionKeyOverrideStore(defaults: defaults, bootSession: "boot-a")
        XCTAssertEqual(reloaded.overrides, [.f5: .function, .f10: .media])
        defaults.set(["0": "function", "13": "media", "5": "invalid", "10": "media"], forKey: FunctionKeyOverrideStore.preferencesKey)
        XCTAssertEqual(store.overrides, [.f10: .media])
        store.overrides = [:]
        XCTAssertTrue(reloaded.overrides.isEmpty)
    }

    @objc func testExistingMappingsAreRestoredOnDisable() throws {
        let external: UInt64 = 123
        backend.maps[1] = [external: 456, FunctionKey.f5.usage: 789]
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        XCTAssertEqual(backend.maps[1]?[external], 456)
        XCTAssertEqual(backend.maps[1]?[dictation], FunctionKey.f5.usage)
        _ = try engine.reconcile(enabled: false, overrides: [.f5: .function])
        XCTAssertEqual(backend.maps[1], [external: 456, FunctionKey.f5.usage: 789])
        XCTAssertTrue(try store.loadLeases().isEmpty)
    }

    @objc func testExternalChangesWhileActiveSurviveCleanup() throws {
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        backend.maps[1]?[dictation] = 999
        backend.maps[1]?[888] = 777
        _ = try engine.reconcile(enabled: false, overrides: [:])
        XCTAssertEqual(backend.maps[1], [dictation: 999, 888: 777])
    }

    @objc func testEditingAndResetReleaseOnlyOwnedSources() throws {
        backend.maps[1] = [123: 456]
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        _ = try engine.reconcile(enabled: true, overrides: [.f10: .media])
        XCTAssertNil(backend.maps[1]?[dictation])
        XCTAssertEqual(backend.maps[1]?[FunctionKey.f10.usage], mute)
        _ = try engine.reconcile(enabled: true, overrides: [:])
        XCTAssertEqual(backend.maps[1], [123: 456])
    }

    @objc func testUnchangedConfigurationDoesNotRewriteHeldKeys() throws {
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        let writes = backend.writes
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        XCTAssertEqual(backend.writes, writes)
    }

    @objc func testCrashRecoveryRestoresOriginalMapping() throws {
        backend.maps[1] = [dictation: 42]
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        let restarted = FunctionKeyMappingEngine(backend: backend, store: store)
        _ = try restarted.reconcile(enabled: false, overrides: [:])
        XCTAssertEqual(backend.maps[1], [dictation: 42])
        XCTAssertTrue(try store.loadLeases().isEmpty)
    }

    @objc func testOldBootJournalDoesNotTouchReusedRegistryID() throws {
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        backend.maps[1] = [dictation: 77]
        let nextBootStore = FunctionKeyOverrideStore(defaults: defaults, bootSession: "boot-b")
        let nextBoot = FunctionKeyMappingEngine(backend: backend, store: nextBootStore)
        _ = try nextBoot.reconcile(enabled: false, overrides: [:])
        XCTAssertEqual(backend.maps[1], [dictation: 77])
    }

    @objc func testHotplugUsesEachKeyboardsOwnMediaAction() throws {
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        let keyboardBacklight: UInt64 = (255 << 32) | 8
        backend.devices.append(.init(id: 2, name: "Older keyboard", mediaUsages: [.f5: keyboardBacklight]))
        _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        XCTAssertEqual(backend.maps[2]?[keyboardBacklight], FunctionKey.f5.usage)
        XCTAssertNil(backend.maps[2]?[dictation])
        backend.devices.removeAll { $0.id == 1 }
        _ = try engine.reconcile(enabled: false, overrides: [:])
        XCTAssertEqual(backend.maps[2], [:])
        XCTAssertTrue(try store.loadLeases().isEmpty)
    }

    @objc func testPauseAndResume() throws {
        for _ in 0..<3 {
            _ = try engine.reconcile(enabled: true, overrides: [.f5: .function])
            XCTAssertEqual(backend.maps[1]?[dictation], FunctionKey.f5.usage)
            _ = try engine.reconcile(enabled: false, overrides: [:])
            XCTAssertEqual(backend.maps[1], [:])
        }
    }

    @objc func testWriteFailureIsReportedAndPartialWriteCanRecover() throws {
        backend.failAfterWrite = true
        let statuses = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        XCTAssertNotNil(statuses.first?.error)
        XCTAssertFalse(try store.loadLeases().isEmpty)
        backend.failAfterWrite = false
        let restarted = FunctionKeyMappingEngine(backend: backend, store: store)
        _ = try restarted.reconcile(enabled: false, overrides: [:])
        XCTAssertEqual(backend.maps[1], [:])
    }

    @objc func testReadFailureNeverReplacesUnknownExternalMappings() throws {
        backend.maps[1] = [123: 456]
        backend.failRead = true
        let statuses = try engine.reconcile(enabled: true, overrides: [.f5: .function])
        XCTAssertNotNil(statuses.first?.error)
        XCTAssertEqual(backend.writes, 0)
        XCTAssertEqual(backend.maps[1], [123: 456])
    }

    @objc func testCorruptRecoveryDataDoesNotChangeKeyboard() throws {
        let entry = FunctionKeyMappingLease.Entry(source: dictation, original: nil, applied: FunctionKey.f5.usage)
        try store.saveLeases([.init(deviceID: 1, entries: [entry, entry])])
        XCTAssertThrowsError(try engine.reconcile(enabled: true, overrides: [.f5: .function]))
        XCTAssertEqual(backend.writes, 0)
    }


}

@main
enum FunctionKeyTestsRunner {
    static func main() {
        let suite = XCTestSuite(forTestCaseClass: FunctionKeyMappingTests.self)
        suite.run()
        exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
    }
}
