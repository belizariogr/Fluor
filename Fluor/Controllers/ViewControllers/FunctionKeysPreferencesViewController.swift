import Cocoa

final class FunctionKeysPreferencesViewController: NSViewController {
    private var controls: [FunctionKey: NSPopUpButton] = [:]
    private let statusView = NSTextView()
    private var resetButton: NSButton!
    private var observer: NSObjectProtocol?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 620))
        let description = NSTextField(wrappingLabelWithString: FKeyLocalized("Choose exceptions for all apps and compatible keyboards. Fixed keys keep their action even while Fn/Globe is held."))
        description.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        stack.addArrangedSubview(description)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            description.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 4
        for key in FunctionKey.allCases {
            let label = NSTextField(labelWithString: key.label)
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            label.widthAnchor.constraint(equalToConstant: 40).isActive = true
            let control = NSPopUpButton(frame: .zero, pullsDown: false)
            control.controlSize = .small
            control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            control.addItems(withTitles: FunctionKeyOverride.allCases.map { $0.title })
            control.tag = key.rawValue
            control.target = self
            control.action = #selector(changeOverride(_:))
            control.setAccessibilityLabel(String(format: FKeyLocalized("Behavior for %@"), key.label))
            control.setAccessibilityIdentifier("functionKey.\(key.rawValue)")
            control.widthAnchor.constraint(equalToConstant: 290).isActive = true
            controls[key] = control
            let row = NSStackView(views: [label, control])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            rows.addArrangedSubview(row)
        }
        stack.addArrangedSubview(rows)

        let mediaHelp = NSTextField(wrappingLabelWithString: FKeyLocalized("Media uses the keyboard’s original action, such as brightness, Dictation or volume."))
        mediaHelp.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        mediaHelp.textColor = .secondaryLabelColor
        stack.addArrangedSubview(mediaHelp)
        mediaHelp.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        resetButton = NSButton(title: FKeyLocalized("Reset all to follow mode"), target: self, action: #selector(resetOverrides(_:)))
        stack.addArrangedSubview(resetButton)

        let statusScroll = NSScrollView()
        statusScroll.hasVerticalScroller = true
        statusScroll.drawsBackground = false
        statusScroll.borderType = .noBorder
        statusView.isEditable = false
        statusView.isSelectable = true
        statusView.drawsBackground = false
        statusView.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusView.textColor = .secondaryLabelColor
        statusView.isVerticallyResizable = true
        statusView.autoresizingMask = [.width]
        statusView.textContainer?.widthTracksTextView = true
        statusView.textContainer?.containerSize = NSSize(width: 540, height: CGFloat.greatestFiniteMagnitude)
        statusView.setAccessibilityLabel(FKeyLocalized("Keyboard status"))
        statusScroll.documentView = statusView
        stack.addArrangedSubview(statusScroll)
        NSLayoutConstraint.activate([
            statusScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusScroll.heightAnchor.constraint(equalToConstant: 60)
        ])

        observer = NotificationCenter.default.addObserver(forName: .functionKeyOverridesDidChange,
                                                         object: FunctionKeyOverrideController.shared, queue: .main) { [weak self] _ in
            self?.updateControls()
        }
        updateControls()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        FunctionKeyOverrideController.shared.refresh()
        updateControls()
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func updateControls() {
        let controller = FunctionKeyOverrideController.shared
        for (key, control) in controls {
            let mode = controller.overrides[key] ?? .followMode
            control.selectItem(at: FunctionKeyOverride.allCases.firstIndex(of: mode) ?? 0)
        }
        resetButton.isEnabled = !controller.overrides.isEmpty
        statusView.string = controller.statusText
    }

    @objc private func changeOverride(_ sender: NSPopUpButton) {
        guard let key = FunctionKey(rawValue: sender.tag),
              FunctionKeyOverride.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        FunctionKeyOverrideController.shared.setOverride(FunctionKeyOverride.allCases[sender.indexOfSelectedItem], for: key)
    }

    @objc private func resetOverrides(_ sender: NSButton) {
        FunctionKeyOverrideController.shared.reset()
    }
}
