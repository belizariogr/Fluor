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
            let controls = descendants(keysView).compactMap { $0 as? NSPopUpButton }
            precondition(controls.count == 12)
            for control in controls {
                let rect = keysView.convert(control.bounds, from: control)
                precondition(keysView.bounds.insetBy(dx: -1, dy: -1).contains(rect), "Clipped F-key control: \(control.tag), \(rect), \(keysView.bounds)")
                precondition(control.numberOfItems == 3 && control.indexOfSelectedItem == 0)
            }
            for (number, choice) in [(5, 1), (10, 2)] {
                let control = controls.first { $0.tag == number }!
                control.selectItem(at: choice)
                control.sendAction(control.action!, to: control.target)
            }
            precondition(FunctionKeyOverrideController.shared.overrides == [.f5: .function, .f10: .media])
            let reset = descendants(keysView).compactMap { $0 as? NSButton }.first { $0.title == FKeyLocalized("Reset all to follow mode") }!
            reset.performClick(nil)
            precondition(FunctionKeyOverrideController.shared.overrides.isEmpty)
            NSLog("UI PASS cycle %d: five tabs, twelve visible controls, immediate edits and reset", cycle)
            tabs.view.window?.close()
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
