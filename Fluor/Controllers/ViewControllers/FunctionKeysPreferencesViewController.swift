import Cocoa

final class FunctionKeysPreferencesViewController: NSViewController {
    // Match the current-app selector: default, media, function. Keep this
    // presentation order separate from the persisted override values.
    private static let choices: [(mode: FunctionKeyOverride, asset: String)] = [
        (.followMode, "DefaultMode"), (.media, "AppleMode"), (.function, "OtherMode")
    ]
    private var controls: [FunctionKey: NSSegmentedControl] = [:]
    private let statusView = NSTextView()
    private var resetButton: NSButton!
    private var observer: NSObjectProtocol?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 420))
        let description = NSTextField(wrappingLabelWithString: FKeyLocalized("Applies to all apps, even with Fn/Globe held."))
        description.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
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

        let legend = NSStackView()
        legend.orientation = .horizontal
        legend.alignment = .centerY
        legend.distribution = .fill
        legend.spacing = 20
        for choice in Self.choices {
            let image = NSImageView(image: choiceImage(asset: choice.asset, mode: choice.mode) ?? NSImage())
            image.widthAnchor.constraint(equalToConstant: 16).isActive = true
            image.heightAnchor.constraint(equalToConstant: 16).isActive = true
            let label = NSTextField(labelWithString: choice.mode.title)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            let item = NSStackView(views: [image, label])
            item.distribution = .fill
            item.spacing = 6
            item.alignment = .centerY
            legend.addArrangedSubview(item)
        }
        stack.addArrangedSubview(legend)

        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 32
        for keys in [Array(FunctionKey.allCases.prefix(6)), Array(FunctionKey.allCases.suffix(6))] {
            let rows = NSStackView()
            rows.orientation = .vertical
            rows.alignment = .leading
            rows.spacing = 8
            for key in keys {
                let label = NSTextField(labelWithString: key.label)
                label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
                label.widthAnchor.constraint(equalToConstant: 30).isActive = true
                let control = NSSegmentedControl()
                control.segmentCount = Self.choices.count
                control.segmentStyle = .roundRect
                control.controlSize = .small
                control.trackingMode = .selectOne
                for (index, choice) in Self.choices.enumerated() {
                    control.setImage(choiceImage(asset: choice.asset, mode: choice.mode), forSegment: index)
                    control.setImageScaling(.scaleProportionallyDown, forSegment: index)
                    control.setToolTip(choice.mode.title, forSegment: index)
                    control.setWidth(32, forSegment: index)
                }
                control.tag = key.rawValue
                control.target = self
                control.action = #selector(changeOverride(_:))
                control.setAccessibilityLabel(String(format: FKeyLocalized("Behavior for %@"), key.label))
                control.setAccessibilityIdentifier("functionKey.\(key.rawValue)")
                controls[key] = control
                let row = NSStackView(views: [label, control])
                row.orientation = .horizontal
                row.alignment = .centerY
                row.spacing = 12
                rows.addArrangedSubview(row)
            }
            columns.addArrangedSubview(rows)
        }
        stack.addArrangedSubview(columns)
        columns.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

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
        statusView.textContainer?.containerSize = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
        statusView.setAccessibilityLabel(FKeyLocalized("Keyboard status"))
        statusScroll.documentView = statusView
        stack.addArrangedSubview(statusScroll)
        NSLayoutConstraint.activate([
            statusScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusScroll.heightAnchor.constraint(equalToConstant: 52)
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

    private func choiceImage(asset: String, mode: FunctionKeyOverride) -> NSImage? {
        let image = NSImage(named: NSImage.Name(asset))?.copy() as? NSImage
        image?.accessibilityDescription = mode.title
        return image
    }

    private func updateControls() {
        let controller = FunctionKeyOverrideController.shared
        for (key, control) in controls {
            let mode = controller.overrides[key] ?? .followMode
            control.selectedSegment = Self.choices.firstIndex { $0.mode == mode } ?? 0
        }
        resetButton.isEnabled = !controller.overrides.isEmpty
        statusView.string = controller.statusText
    }

    @objc private func changeOverride(_ sender: NSSegmentedControl) {
        guard let key = FunctionKey(rawValue: sender.tag),
              Self.choices.indices.contains(sender.selectedSegment) else { return }
        FunctionKeyOverrideController.shared.setOverride(Self.choices[sender.selectedSegment].mode, for: key)
    }

    @objc private func resetOverrides(_ sender: NSButton) {
        FunctionKeyOverrideController.shared.reset()
    }
}
