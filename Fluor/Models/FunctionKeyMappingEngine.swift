import Foundation

protocol FunctionKeyMappingBackend: AnyObject {
    func keyboards() throws -> [KeyboardMappingDevice]
    func readMappings(deviceID: UInt64) throws -> [UInt64: UInt64]
    func writeMappings(_ mappings: [UInt64: UInt64], deviceID: UInt64) throws
}

struct FunctionKeyMappingStatus {
    let device: KeyboardMappingDevice
    let activeCount: Int
    let unsupported: [FunctionKey]
    let error: String?
}

// Accessed only on the controller's serial queue. The backend is injectable so
// restoration, hotplug and write failures can be tested without changing a keyboard.
final class FunctionKeyMappingEngine {
    private let backend: FunctionKeyMappingBackend
    private let store: FunctionKeyOverrideStore
    private var leases: [FunctionKeyMappingLease]?

    init(backend: FunctionKeyMappingBackend, store: FunctionKeyOverrideStore) {
        self.backend = backend
        self.store = store
    }

    func reconcile(enabled: Bool, overrides: [FunctionKey: FunctionKeyOverride]) throws -> [FunctionKeyMappingStatus] {
        if leases == nil { leases = try store.loadLeases() }
        let devices = try backend.keyboards()
        let connectedIDs = Set(devices.map { $0.id })
        // A disconnected service no longer has mappings. Never reuse its lease
        // for a newly connected keyboard with a different registry ID.
        leases = leases?.filter { connectedIDs.contains($0.deviceID) }
        try persistJournal()
        var statuses: [FunctionKeyMappingStatus] = []
        for device in devices {
            let generated = FunctionKeyMap.generate(overrides: enabled ? overrides : [:], mediaUsages: device.mediaUsages)
            do {
                var current = try backend.readMappings(deviceID: device.id)
                if let lease = leases?.first(where: { $0.deviceID == device.id }) {
                    let applied = Dictionary(uniqueKeysWithValues: lease.entries.map { ($0.source, $0.applied) })
                    if applied == generated.mappings && applied.allSatisfy({ current[$0.key] == $0.value }) {
                        statuses.append(.init(device: device,
                                              activeCount: overrides.count - generated.unsupported.count,
                                              unsupported: generated.unsupported, error: nil))
                        continue
                    }
                    for entry in lease.entries where current[entry.source] == entry.applied {
                        current[entry.source] = entry.original
                    }
                    try backend.writeMappings(current, deviceID: device.id)
                    leases?.removeAll { $0.deviceID == device.id }
                    try persistJournal()
                }
                if !generated.mappings.isEmpty {
                    let entries = generated.mappings.sorted { $0.key < $1.key }.map {
                        FunctionKeyMappingLease.Entry(source: $0.key, original: current[$0.key], applied: $0.value)
                    }
                    leases?.append(.init(deviceID: device.id, entries: entries))
                    // Persist ownership BEFORE changing the system. A failed or
                    // interrupted write can then be repaired on the next run.
                    try persistJournal()
                    current.merge(generated.mappings) { _, new in new }
                    try backend.writeMappings(current, deviceID: device.id)
                }
                statuses.append(.init(device: device,
                                      activeCount: enabled ? overrides.count - generated.unsupported.count : 0,
                                      unsupported: generated.unsupported, error: nil))
            } catch {
                statuses.append(.init(device: device, activeCount: 0,
                                      unsupported: generated.unsupported, error: error.localizedDescription))
            }
        }
        return statuses
    }

    private func persistJournal() throws {
        try store.saveLeases(leases ?? [])
    }
}
