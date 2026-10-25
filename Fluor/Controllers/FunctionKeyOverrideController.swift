import Cocoa
import IOKit
import DefaultsWrapper

extension Notification.Name {
    static let functionKeyOverridesDidChange = Notification.Name("FunctionKeyOverridesDidChange")
}

final class FunctionKeyOverrideController {
    static let shared = FunctionKeyOverrideController()

    private let store: FunctionKeyOverrideStore
    private let engine: FunctionKeyMappingEngine
    private let queue = DispatchQueue(label: "com.thinksoft.Fluor.function-key-mappings")
    private var observers: [NSObjectProtocol] = []
    private var notificationPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var refreshWork: DispatchWorkItem?
    private var started = false
    private var awake = true
    private var activeSession = true
    private var generation = 0

    private(set) var statusText = FKeyLocalized("Reading connected keyboards…")
    var overrides: [FunctionKey: FunctionKeyOverride] { store.overrides }
    private var disabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeyName.disabledOnLunch.rawValue)
    }

    private init() {
        let store = FunctionKeyOverrideStore(bootSession: SystemFunctionKeyMappingBackend.bootSessionIdentifier())
        self.store = store
        self.engine = FunctionKeyMappingEngine(backend: SystemFunctionKeyMappingBackend(), store: store)
    }

    func start() {
        guard !started else { return }
        started = true
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        activeSession = session?["kCGSSessionOnConsoleKey"] as? Bool ?? true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self = self else { return }
                switch note.name {
                case NSWorkspace.willSleepNotification: self.awake = false
                case NSWorkspace.didWakeNotification: self.awake = true
                case NSWorkspace.sessionDidResignActiveNotification: self.activeSession = false
                case NSWorkspace.sessionDidBecomeActiveNotification: self.activeSession = true
                default: break
                }
                if self.awake && self.activeSession { self.refresh() }
                else { self.restoreSynchronously() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                object: nil, queue: nil) { [weak self] _ in
            // Defaults notifications may arrive during singleton initialization
            // or a recovery-journal write on the worker queue. Never reenter an
            // initializer or make that writer synchronously wait for the UI.
            DispatchQueue.main.async { self?.refreshIfSettingsChanged() }
        })
        observeKeyboards()
        refresh()
    }

    private var lastSettings: String = ""
    private func refreshIfSettingsChanged() {
        guard started else { return }
        let fingerprint = "\(disabled)-\(store.overrides.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue):\($0.value.rawValue)" })"
        guard fingerprint != lastSettings else { return }
        lastSettings = fingerprint
        refresh()
    }

    func setOverride(_ mode: FunctionKeyOverride, for key: FunctionKey) {
        var values = store.overrides
        values[key] = mode == .followMode ? nil : mode
        store.overrides = values
        refreshIfSettingsChanged()
        notifyChange()
    }

    func reset() {
        store.overrides = [:]
        refreshIfSettingsChanged()
        notifyChange()
    }

    func refresh() {
        guard started else { return }
        generation += 1
        let request = generation
        let enabled = awake && activeSession && !disabled
        let overrides = store.overrides
        queue.async { [weak self] in
            guard let self = self else { return }
            let text: String
            do {
                let statuses = try self.engine.reconcile(enabled: enabled, overrides: overrides)
                text = self.describe(statuses, enabled: enabled, hasOverrides: !overrides.isEmpty)
            } catch { text = error.localizedDescription }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.started, self.generation == request else { return }
                self.statusText = text
                self.notifyChange()
            }
        }
    }

    func stop() {
        guard started else { return }
        refreshWork?.cancel()
        restoreSynchronously()
        started = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port = notificationPort { IONotificationPortDestroy(port) }
        notificationPort = nil
    }

    private func restoreSynchronously() {
        generation += 1
        do {
            let statuses = try queue.sync { try engine.reconcile(enabled: false, overrides: [:]) }
            statusText = describe(statuses, enabled: false, hasOverrides: !store.overrides.isEmpty)
        } catch { statusText = error.localizedDescription }
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .functionKeyOverridesDidChange, object: self)
    }

    private func describe(_ statuses: [FunctionKeyMappingStatus], enabled: Bool, hasOverrides: Bool) -> String {
        var lines: [String] = []
        if !enabled {
            lines.append(FKeyLocalized("Exceptions are paused while Fluor is disabled or the session is inactive."))
        } else if !hasOverrides {
            lines.append(FKeyLocalized("All F keys follow the current mode."))
        }
        if statuses.isEmpty {
            lines.append(FKeyLocalized("No keyboard is connected."))
        }
        for status in statuses {
            if let error = status.error { lines.append("\(status.device.name): \(error)"); continue }
            if !status.unsupported.isEmpty {
                let keys = status.unsupported.map { $0.label }.joined(separator: ", ")
                lines.append(String(format: FKeyLocalized("%@: cannot identify the media action for %@."), status.device.name, keys))
            } else if enabled && hasOverrides {
                lines.append(String(format: FKeyLocalized("%@: %ld active exceptions."), status.device.name, status.activeCount))
            } else if status.device.mediaUsages.isEmpty {
                lines.append(String(format: FKeyLocalized("%@: media actions could not be identified."), status.device.name))
            }
        }
        return lines.joined(separator: "\n")
    }

    private func observeKeyboards() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let context = Unmanaged.passUnretained(self).toOpaque()
            let result = IOServiceAddMatchingNotification(port, kind, IOServiceMatching("IOHIDEventService"), { context, iterator in
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
                guard let context = context else { return }
                let owner = Unmanaged<FunctionKeyOverrideController>.fromOpaque(context).takeUnretainedValue()
                owner.scheduleRefresh()
            }, context, &iterator)
            if result == KERN_SUCCESS {
                iterators.append(iterator)
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
            }
        }
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
