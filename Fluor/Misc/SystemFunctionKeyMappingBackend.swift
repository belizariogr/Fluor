import Foundation
import IOKit
import IOKit.hidsystem

final class SystemFunctionKeyMappingBackend: FunctionKeyMappingBackend {
    private let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var services: [UInt64: IOHIDServiceClient] = [:]
    private let mappingKey = "UserKeyMapping" as CFString
    private let sourceKey = "HIDKeyboardModifierMappingSrc"
    private let destinationKey = "HIDKeyboardModifierMappingDst"

    func keyboards() throws -> [KeyboardMappingDevice] {
        guard let available = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            throw FunctionKeyMappingError.servicesUnavailable
        }
        services.removeAll()
        var result: [KeyboardMappingDevice] = []
        for service in available {
            let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value
            guard let deviceID = id else { continue }
            let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(deviceID))
            defer { if entry != 0 { IOObjectRelease(entry) } }
            func property(_ key: String) -> Any? {
                if let value = IOHIDServiceClientCopyProperty(service, key as CFString) { return value }
                guard entry != 0 else { return nil }
                return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            let mediaMap = property("FnFunctionUsageMap") as? String
            guard IOHIDServiceClientConformsTo(service, 1, 6) != 0 || mediaMap != nil else { continue }
            let name = property("Product") as? String ?? FKeyLocalized("Keyboard")
            services[deviceID] = service
            result.append(.init(id: deviceID, name: name,
                                mediaUsages: mediaMap.map(FunctionKeyMap.parseMediaUsages) ?? [:]))
        }
        return result.sorted { $0.id < $1.id }
    }

    func readMappings(deviceID: UInt64) throws -> [UInt64: UInt64] {
        guard let service = services[deviceID] else { throw FunctionKeyMappingError.servicesUnavailable }
        guard let value = IOHIDServiceClientCopyProperty(service, mappingKey) else { return [:] }
        guard let pairs = value as? [[String: Any]] else { throw FunctionKeyMappingError.malformedMappings }
        var result: [UInt64: UInt64] = [:]
        for pair in pairs {
            guard let source = pair[sourceKey] as? NSNumber, let destination = pair[destinationKey] as? NSNumber else {
                throw FunctionKeyMappingError.malformedMappings
            }
            // Do not normalize an ambiguous external mapping by dropping entries.
            guard result[source.uint64Value] == nil else { throw FunctionKeyMappingError.malformedMappings }
            result[source.uint64Value] = destination.uint64Value
        }
        return result
    }

    func writeMappings(_ mappings: [UInt64: UInt64], deviceID: UInt64) throws {
        guard let service = services[deviceID] else { throw FunctionKeyMappingError.servicesUnavailable }
        if try readMappings(deviceID: deviceID) == mappings { return }
        let pairs = mappings.sorted { $0.key < $1.key }.map {
            [sourceKey: NSNumber(value: $0.key), destinationKey: NSNumber(value: $0.value)]
        }
        guard IOHIDServiceClientSetProperty(service, mappingKey, pairs as CFArray),
              try readMappings(deviceID: deviceID) == mappings else { throw FunctionKeyMappingError.writeFailed }
    }

    static func bootSessionIdentifier() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else {
            // A stable boot time is a fallback; process uptime is not a boot identity.
            var bootTime = timeval()
            size = MemoryLayout<timeval>.size
            guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return "unavailable-\(UUID().uuidString)" }
            return "\(bootTime.tv_sec)-\(bootTime.tv_usec)"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "unavailable-\(UUID().uuidString)" }
        return String(cString: buffer)
    }
}
