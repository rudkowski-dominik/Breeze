import AppKit

public final class ControlCenterSlider: NSControl {
    public var percentage: Float = 0.0 {
        didSet {
            let clamped = max(0, min(100, percentage))
            if clamped != oldValue {
                needsDisplay = true
            }
        }
    }

    public var isDragging: Bool = false
    public var onValueChanged: ((Float) -> Void)?

    public override var isFlipped: Bool { true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let cornerRadius: CGFloat = bounds.height / 2.0
        let trackPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
        trackPath.fill()

        let fillWidth = max(0, min(bounds.width * CGFloat(percentage / 100.0), bounds.width))
        if fillWidth > 0 {
            let fillRect = NSRect(x: 0, y: 0, width: fillWidth, height: bounds.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)

            ctx.saveGState()
            fillPath.addClip()
            let gradient = NSGradient(
                starting: NSColor.systemCyan.withAlphaComponent(0.85),
                ending: NSColor.systemBlue.withAlphaComponent(0.95)
            )
            gradient?.draw(in: fillRect, angle: 0)
            ctx.restoreGState()
        }

        // Apple fan icon inside track
        if let fanIcon = NSImage(systemSymbolName: "fan", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            let configured = fanIcon.withSymbolConfiguration(config)
            let iconRect = NSRect(x: 5, y: (bounds.height - 12) / 2.0, width: 12, height: 12)
            configured?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: fillWidth > 18 ? 1.0 : 0.45)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateFromEvent(event)

        while isDragging {
            guard let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if nextEvent.type == .leftMouseUp {
                isDragging = false
                updateFromEvent(nextEvent)
                break
            } else {
                updateFromEvent(nextEvent)
            }
        }
    }

    private func updateFromEvent(_ event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let newPct = Float(max(0, min(100, (loc.x / bounds.width) * 100.0)))
        percentage = newPct
        onValueChanged?(newPct)
    }
}

public final class FanControlView: NSView {
    public override var isFlipped: Bool { true }

    public let slider = ControlCenterSlider(frame: NSRect(x: 38, y: 12, width: 184, height: 18))
    private let minusButton = NSButton(frame: NSRect(x: 12, y: 11, width: 20, height: 20))
    private let plusButton = NSButton(frame: NSRect(x: 228, y: 11, width: 20, height: 20))
    public let valueLabel = NSTextField(labelWithString: "0% · 1000 RPM")
    public let statusLabel = NSTextField(labelWithString: "System Managed · macOS Thermal Governance")

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        // Stepper Minus button
        minusButton.bezelStyle = .circular
        minusButton.isBordered = false
        minusButton.image = NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Decrease Fan Speed")
        minusButton.contentTintColor = .secondaryLabelColor
        minusButton.target = self
        minusButton.action = #selector(didClickMinus)
        addSubview(minusButton)

        // Stepper Plus button
        plusButton.bezelStyle = .circular
        plusButton.isBordered = false
        plusButton.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Increase Fan Speed")
        plusButton.contentTintColor = .secondaryLabelColor
        plusButton.target = self
        plusButton.action = #selector(didClickPlus)
        addSubview(plusButton)

        // Slider
        slider.onValueChanged = { [weak self] newPct in
            FanManager.shared.setCustomFixedSpeed(percentage: newPct)
            self?.updateLabelsOnly(pct: newPct)
        }
        addSubview(slider)

        // Value & RPM Readout
        valueLabel.frame = NSRect(x: 10, y: 37, width: 240, height: 18)
        valueLabel.alignment = .center
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        valueLabel.textColor = .labelColor
        addSubview(valueLabel)

        // Status description
        statusLabel.frame = NSRect(x: 8, y: 57, width: 244, height: 16)
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        addSubview(statusLabel)

        update()
    }

    @objc private func didClickMinus() {
        let newPct = max(0, slider.percentage - 5)
        slider.percentage = newPct
        FanManager.shared.setCustomFixedSpeed(percentage: newPct)
        updateLabelsOnly(pct: newPct)
    }

    @objc private func didClickPlus() {
        let newPct = min(100, slider.percentage + 5)
        slider.percentage = newPct
        FanManager.shared.setCustomFixedSpeed(percentage: newPct)
        updateLabelsOnly(pct: newPct)
    }

    private func updateLabelsOnly(pct: Float) {
        let hardwareMin: Float = 1000.0
        let hardwareMax: Float = 4900.0
        let targetRPM = hardwareMin + (pct / 100.0) * (hardwareMax - hardwareMin)
        let fanCountSuffix = FanManager.shared.fans.count > 1 ? " (\(FanManager.shared.fans.count) Fans)" : ""
        valueLabel.stringValue = "\(Int(round(pct)))% · \(Int(round(targetRPM))) RPM\(fanCountSuffix)"
        statusLabel.stringValue = LocalizationManager.shared.text(.profileCustomDesc)
    }

    public func update() {
        guard !slider.isDragging else { return }
        let fan = FanManager.shared.fans.first
        let pct = fan?.percentage ?? 0
        let rpm = fan?.actualRPM ?? 0

        slider.percentage = pct
        let fanCountSuffix = FanManager.shared.fans.count > 1 ? " (\(FanManager.shared.fans.count) Fans)" : ""
        valueLabel.stringValue = "\(Int(round(pct)))% · \(Int(round(rpm))) RPM\(fanCountSuffix)"
        statusLabel.stringValue = FanManager.shared.statusMessage
    }
}

public final class GaugeMenuItem: NSMenuItem {
    public let controlView: FanControlView

    public init() {
        self.controlView = FanControlView(frame: NSRect(x: 0, y: 0, width: 260, height: 86))
        super.init(title: "", action: nil, keyEquivalent: "")
        self.view = controlView
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateTelemetry() {
        controlView.update()
    }
}
