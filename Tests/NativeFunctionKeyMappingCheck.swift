import Foundation

// Opt-in integration check: temporarily changes only F5/F10 mappings, verifies
// macOS accepted them, then restores exactly the mappings present at entry.
@main
enum NativeFunctionKeyMappingCheck {
    static func main() throws {
        let suite = "Fluor.NativeMappingCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = FunctionKeyOverrideStore(defaults: defaults, bootSession: SystemFunctionKeyMappingBackend.bootSessionIdentifier())
        let backend = SystemFunctionKeyMappingBackend()
        let devices = try backend.keyboards()
        guard devices.contains(where: { $0.mediaUsages[.f5] != nil }) else {
            throw FunctionKeyMappingError.servicesUnavailable
        }
        var original: [UInt64: [UInt64: UInt64]] = [:]
        for device in devices {
            original[device.id] = try backend.readMappings(deviceID: device.id)
            print("\(device.name): \(device.mediaUsages.count)/12 media actions identified")
        }
        let engine = FunctionKeyMappingEngine(backend: backend, store: store)
        // This journal must remain available if cleanup itself fails.
        defer {
            do {
                let statuses = try engine.reconcile(enabled: false, overrides: [:])
                guard statuses.allSatisfy({ $0.error == nil }) else {
                    print("RESTORATION FAILED; recovery defaults suite: \(suite)")
                    exit(1)
                }
                for device in devices {
                    guard try backend.readMappings(deviceID: device.id) == original[device.id] else {
                        print("RESTORATION MISMATCH: \(device.name); recovery suite: \(suite)")
                        exit(1)
                    }
                }
                defaults.removePersistentDomain(forName: suite)
                print("Original native mappings restored.")
            } catch {
                print("RESTORATION FAILED: \(error); recovery suite: \(suite)")
                exit(1)
            }
        }
        let overrides: [FunctionKey: FunctionKeyOverride] = [.f5: .function, .f10: .media]
        let statuses = try engine.reconcile(enabled: true, overrides: overrides)
        guard statuses.allSatisfy({ $0.error == nil }) else {
            for status in statuses { if let error = status.error { print("\(status.device.name): \(error)") } }
            throw FunctionKeyMappingError.writeFailed
        }
        for device in devices {
            let expected = FunctionKeyMap.generate(overrides: overrides, mediaUsages: device.mediaUsages).mappings
            let actual = try backend.readMappings(deviceID: device.id)
            guard expected.allSatisfy({ actual[$0.key] == $0.value }) else { throw FunctionKeyMappingError.writeFailed }
        }
        print("Native F5/function and F10/media mappings verified by read-back.")
    }
}
