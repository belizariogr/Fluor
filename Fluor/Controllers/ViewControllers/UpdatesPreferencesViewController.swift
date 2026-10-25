import Cocoa
import Sparkle

final class UpdatesPreferencesViewController: NSViewController {
    // SUUpdater may return an existing singleton from init. Keep it out of
    // storyboard decoding, which requires each decoded object to keep its identity.
    @objc dynamic let updater: SUUpdater = SUUpdater.shared()

    @IBAction func checkForUpdates(_ sender: Any) {
        updater.checkForUpdates(sender)
    }
}
