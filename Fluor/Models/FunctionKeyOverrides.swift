import Foundation

func FKeyLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: "FunctionKeys", comment: "Per-key media/function preferences")
}

enum FunctionKey: Int, CaseIterable, Codable {
    case f1 = 1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    var label: String { "F\(rawValue)" }
    var usage: UInt64 { (7 << 32) | UInt64(0x39 + rawValue) }
}

enum FunctionKeyOverride: String, CaseIterable, Codable {
    case followMode, function, media

    var title: String {
        switch self {
        case .followMode: return FKeyLocalized("Follow mode")
        case .function: return FKeyLocalized("Always function")
        case .media: return FKeyLocalized("Always media")
        }
    }
}

struct KeyboardMappingDevice {
    let id: UInt64
    let name: String
    let mediaUsages: [FunctionKey: UInt64]
}

enum FunctionKeyMap {
    // Older keyboards publish (page << 16) | usage; newer ones may use
    // (page << 32) | usage. UserKeyMapping always uses the latter encoding.
    static func parseMediaUsages(_ string: String) -> [FunctionKey: UInt64] {
        let parts = string.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count.isMultiple(of: 2) else { return [:] }
        var pairs: [UInt64: UInt64] = [:]
        for index in stride(from: 0, to: parts.count, by: 2) {
            func decode(_ part: Substring) -> UInt64? {
                let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
                let value = text.lowercased().hasPrefix("0x")
                    ? UInt64(text.dropFirst(2), radix: 16) : UInt64(text)
                guard let number = value else { return nil }
                return number > UInt32.max ? number : ((number >> 16) << 32) | (number & 0xffff)
            }
            guard let source = decode(parts[index]), let destination = decode(parts[index + 1]) else { return [:] }
            // Conflicting aliases cannot reliably identify an action.
            if let previous = pairs[source], previous != destination { return [:] }
            pairs[source] = destination
        }
        var result: [FunctionKey: UInt64] = [:]
        for key in FunctionKey.allCases {
            if let media = pairs[key.usage], media != key.usage, media >> 32 != 0 {
                result[key] = media
            }
        }
        return result
    }

    static func generate(overrides: [FunctionKey: FunctionKeyOverride],
                         mediaUsages: [FunctionKey: UInt64]) -> (mappings: [UInt64: UInt64], unsupported: [FunctionKey]) {
        var candidates: [FunctionKey: [UInt64: UInt64]] = [:]
        var unsupported: Set<FunctionKey> = []
        for key in FunctionKey.allCases {
            guard let mode = overrides[key], mode != .followMode else { continue }
            guard let media = mediaUsages[key], media != key.usage else { unsupported.insert(key); continue }
            let destination = mode == .function ? key.usage : media
            candidates[key] = [key.usage: destination, media: destination]
        }
        // If two physical keys share a media usage, do not silently apply
        // contradictory choices to that same source event.
        for (key, mappings) in candidates {
            for (other, otherMappings) in candidates where key != other {
                if mappings.contains(where: { source, target in
                    otherMappings[source].map { $0 != target } ?? false
                }) {
                    unsupported.insert(key)
                    unsupported.insert(other)
                }
            }
        }
        var result: [UInt64: UInt64] = [:]
        for (key, mappings) in candidates where !unsupported.contains(key) {
            result.merge(mappings) { _, new in new }
        }
        return (result, unsupported.sorted { $0.rawValue < $1.rawValue })
    }
}

struct FunctionKeyMappingLease: Codable {
    struct Entry: Codable {
        let source: UInt64
        let original: UInt64?
        let applied: UInt64
    }
    let deviceID: UInt64
    let entries: [Entry]
}

final class FunctionKeyOverrideStore {
    static let preferencesKey = "FunctionKeyOverrides"
    private static let journalKey = "FunctionKeyMappingRecovery"
    private let defaults: UserDefaults
    private let bootSession: String

    private struct Journal: Codable {
        let bootSession: String
        let leases: [FunctionKeyMappingLease]
    }

    init(defaults: UserDefaults = .standard, bootSession: String) {
        self.defaults = defaults
        self.bootSession = bootSession
    }

    var overrides: [FunctionKey: FunctionKeyOverride] {
        get {
            var result: [FunctionKey: FunctionKeyOverride] = [:]
            for (key, value) in defaults.dictionary(forKey: Self.preferencesKey) ?? [:] {
                if let number = Int(key), let fKey = FunctionKey(rawValue: number),
                   let text = value as? String, let mode = FunctionKeyOverride(rawValue: text), mode != .followMode {
                    result[fKey] = mode
                }
            }
            return result
        }
        set {
            var values: [String: String] = [:]
            for (key, mode) in newValue where mode != .followMode { values[String(key.rawValue)] = mode.rawValue }
            defaults.set(values, forKey: Self.preferencesKey)
        }
    }

    func loadLeases() throws -> [FunctionKeyMappingLease] {
        guard let data = defaults.data(forKey: Self.journalKey) else { return [] }
        let journal = try JSONDecoder().decode(Journal.self, from: data)
        // Registry IDs are only meaningful during the boot in which they were saved.
        guard journal.bootSession == bootSession else { return [] }
        guard Set(journal.leases.map { $0.deviceID }).count == journal.leases.count,
              journal.leases.allSatisfy({ Set($0.entries.map { $0.source }).count == $0.entries.count }) else {
            throw FunctionKeyMappingError.recoveryUnavailable
        }
        return journal.leases
    }

    func saveLeases(_ leases: [FunctionKeyMappingLease]) throws {
        let data = try JSONEncoder().encode(Journal(bootSession: bootSession, leases: leases))
        defaults.set(data, forKey: Self.journalKey)
        guard defaults.synchronize() else { throw FunctionKeyMappingError.recoveryUnavailable }
    }
}

enum FunctionKeyMappingError: LocalizedError {
    case servicesUnavailable, malformedMappings, writeFailed, recoveryUnavailable

    var errorDescription: String? {
        switch self {
        case .servicesUnavailable: return FKeyLocalized("Unable to read connected keyboards.")
        case .malformedMappings: return FKeyLocalized("Unable to read existing keyboard mappings safely.")
        case .writeFailed: return FKeyLocalized("macOS did not apply the keyboard mappings.")
        case .recoveryUnavailable: return FKeyLocalized("Unable to save keyboard mapping recovery data.")
        }
    }
}
