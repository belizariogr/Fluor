import Cocoa

// Compiled only by test-function-keys-ui.py in its isolated temporary project.
@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menu = StatusMenuController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        precondition(Bundle.main.bundleIdentifier == "com.thinksoft.Fluor.function-key-ui-tests")
        UserDefaults.standard.removeObject(forKey: FunctionKeyOverrideStore.preferencesKey)
        FunctionKeyOverrideController.shared.start()
        for cycle in 1...3 {
            let tabs = openPreferences()
            for index in tabs.tabViewItems.indices {
                tabs.selectedTabViewItemIndex = index
                tabs.view.window?.layoutIfNeeded()
            }
            let keysIndex = tabs.tabViewItems.firstIndex { ($0.identifier as? String) == "function_keys_tab" }!
            tabs.selectedTabViewItemIndex = keysIndex
            let keysView = tabs.tabViewItems[keysIndex].viewController!.view
            keysView.layoutSubtreeIfNeeded()
            let controls = descendants(keysView).compactMap { $0 as? NSSegmentedControl }
            precondition(controls.count == 12)
            let choices: [FunctionKeyOverride] = [.followMode, .media, .function]
            for control in controls {
                let rect = keysView.convert(control.bounds, from: control)
                precondition(keysView.bounds.insetBy(dx: -1, dy: -1).contains(rect), "Clipped F-key control: \(control.tag), \(rect), \(keysView.bounds)")
                precondition(control.segmentCount == 3 && control.selectedSegment == 0)
                for (index, choice) in choices.enumerated() {
                    precondition(control.image(forSegment: index)?.isValid == true)
                    precondition(control.image(forSegment: index)?.accessibilityDescription == choice.title)
                    precondition(control.toolTip(forSegment: index) == choice.title)
                    precondition((control.label(forSegment: index) ?? "").isEmpty)
                }
            }
            for (number, choice) in [(5, 2), (10, 1)] {
                let control = controls.first { $0.tag == number }!
                control.selectedSegment = choice
                control.sendAction(control.action!, to: control.target)
            }
            precondition(FunctionKeyOverrideController.shared.overrides == [.f5: .function, .f10: .media])
            tabs.view.window?.close()
            let reopened = openPreferences()
            precondition(reopened !== tabs)
            reopened.selectedTabViewItemIndex = keysIndex
            let reopenedView = reopened.tabViewItems[keysIndex].viewController!.view
            let restored = descendants(reopenedView).compactMap { $0 as? NSSegmentedControl }
            precondition(restored.first { $0.tag == 5 }?.selectedSegment == 2)
            precondition(restored.first { $0.tag == 10 }?.selectedSegment == 1)
            let reset = descendants(reopenedView).compactMap { $0 as? NSButton }.first { $0.title == FKeyLocalized("Reset all to follow mode") }!
            reset.performClick(nil)
            precondition(FunctionKeyOverrideController.shared.overrides.isEmpty)
            precondition(restored.allSatisfy { $0.selectedSegment == 0 })
            NSLog("UI PASS cycle %d: twelve icon selectors, accessible labels, saved selections and reset", cycle)
            reopened.view.window?.close()
        }
        if let argument = CommandLine.arguments.firstIndex(of: "--snapshot-directory") {
            let tabs = openPreferences()
            tabs.selectedTabViewItemIndex = tabs.tabViewItems.firstIndex { ($0.identifier as? String) == "function_keys_tab" }!
            let directory = URL(fileURLWithPath: CommandLine.arguments[argument + 1])
            let window = tabs.view.window!
            let frameView = window.contentView!.superview!
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                window.layoutIfNeeded()
                frameView.display()
                let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds)!
                frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
                let data = bitmap.representation(using: .png, properties: [:])!
                try! data.write(to: directory.appendingPathComponent("function-keys-\(name).png"))
            }
            window.close()
        }
        if CommandLine.arguments.contains("--show") {
            let tabs = openPreferences()
            tabs.selectedTabViewItemIndex = tabs.tabViewItems.firstIndex { ($0.identifier as? String) == "function_keys_tab" }!
        } else {
            FunctionKeyOverrideController.shared.stop()
            NSLog("FUNCTION KEY UI SMOKE PASSED")
            NSApp.terminate(nil)
        }
    }

    private func openPreferences() -> NSTabViewController {
        menu.showPreferences(self)
        let tabs = NSApp.windows.filter { $0.isVisible }.compactMap { $0.contentViewController as? PreferencesTabViewController }.first!
        tabs.transitionOptions = []
        precondition(tabs.tabViewItems.count == 5)
        return tabs
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FunctionKeyOverrideController.shared.stop()
    }
}
