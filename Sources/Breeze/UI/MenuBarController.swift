import AppKit
import SwiftUI

public enum MenuBarDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case iconOnly = "iconOnly"
    case iconAndTemp = "iconAndTemp"
    case iconAndRPM = "iconAndRPM"

    public var id: String { rawValue }
}

public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var gaugeMenuItem: GaugeMenuItem!
    private var refreshTimer: Timer?

    public var displayStyle: MenuBarDisplayStyle = .iconOnly {
        didSet {
            UserDefaults.standard.set(displayStyle.rawValue, forKey: "breeze_menu_bar_style")
            updateStatusItemButton()
        }
    }

    private override init() {
        super.init()
        if let saved = UserDefaults.standard.string(forKey: "breeze_menu_bar_style"),
           let style = MenuBarDisplayStyle(rawValue: saved) {
            self.displayStyle = style
        }
    }

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemButton()

        buildMenu()
        statusItem.menu = menu

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateMenuState()
            self?.updateStatusItemButton()
        }
    }

    public func updateStatusItemButton() {
        guard let button = statusItem?.button else { return }

        button.image = createAppleStyleFanIcon()
        button.imagePosition = .imageLeading

        switch displayStyle {
        case .iconOnly:
            button.title = ""
        case .iconAndTemp:
            let temp = Int(round(FanManager.shared.currentTemperature))
            button.title = " \(temp)°C"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        case .iconAndRPM:
            let rpm = Int(round(FanManager.shared.fans.first?.actualRPM ?? 0))
            if rpm >= 1000 {
                let kRPM = String(format: "%.1fk", Float(rpm) / 1000.0)
                button.title = " \(kRPM)"
            } else {
                button.title = " \(rpm)"
            }
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        }
    }

    private func createAppleStyleFanIcon() -> NSImage {
        if let sfImage = NSImage(systemSymbolName: "fan", accessibilityDescription: "Breeze") {
            let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .regular)
            if let configured = sfImage.withSymbolConfiguration(config) {
                configured.isTemplate = true
                return configured
            }
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: 9, y: 9)
            let hubRadius: CGFloat = 1.75
            let bladeRadius: CGFloat = 6.2

            ctx.setFillColor(NSColor.labelColor.cgColor)
            for i in 0..<3 {
                let angle = CGFloat(i) * (2.0 * CGFloat.pi / 3.0) - (CGFloat.pi / 2.0)
                let endAngle = angle + 0.65
                let path = CGMutablePath()
                path.move(to: CGPoint(x: center.x + hubRadius * cos(angle), y: center.y + hubRadius * sin(angle)))
                path.addQuadCurve(to: CGPoint(x: center.x + bladeRadius * cos(endAngle), y: center.y + bladeRadius * sin(endAngle)),
                                  control: CGPoint(x: center.x + (bladeRadius * 0.7) * cos(angle + 0.35), y: center.y + (bladeRadius * 0.7) * sin(angle + 0.35)))
                path.addArc(center: center, radius: bladeRadius, startAngle: endAngle, endAngle: endAngle + 0.25, clockwise: false)
                path.addLine(to: CGPoint(x: center.x + hubRadius * cos(angle + 0.4), y: center.y + hubRadius * sin(angle + 0.4)))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()
            }
            ctx.addArc(center: center, radius: hubRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }

    public func buildMenu() {
        let loc = LocalizationManager.shared
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // 1. Predefined Profiles
        for profile in FanManager.shared.profiles {
            let item = NSMenuItem(title: profile.localizedName, action: #selector(didSelectProfileItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile
            item.state = (FanManager.shared.activeProfile.id == profile.id) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Custom Fan Speed submenu
        let customSpeedItem = NSMenuItem(title: loc.text(.customFanSpeed), action: nil, keyEquivalent: "")
        let speedSubmenu = NSMenu(title: loc.text(.customFanSpeed))

        let speeds: [(title: String, pct: Float)] = [
            ("Min (0% · 1000 RPM)", 0),
            ("25% · 1975 RPM", 25),
            ("40% · 2560 RPM", 40),
            ("50% · 2950 RPM", 50),
            ("70% · 3730 RPM", 70),
            ("85% · 4315 RPM", 85),
            ("100% · 4900 RPM (Max)", 100)
        ]

        for speed in speeds {
            let item = NSMenuItem(title: speed.title, action: #selector(didSelectCustomSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed.pct
            speedSubmenu.addItem(item)
        }

        speedSubmenu.addItem(NSMenuItem.separator())
        let promptRpmItem = NSMenuItem(title: loc.text(.enterCustomRPM), action: #selector(didClickCustomRPM), keyEquivalent: "")
        promptRpmItem.target = self
        speedSubmenu.addItem(promptRpmItem)

        customSpeedItem.submenu = speedSubmenu
        menu.addItem(customSpeedItem)

        // 3. Activate for/until submenu
        let timerItem = NSMenuItem(title: loc.text(.activateForUntil), action: nil, keyEquivalent: "")
        let timerSubmenu = NSMenu(title: loc.text(.activateForUntil))

        for duration in TimerDuration.allCases {
            let item = NSMenuItem(title: duration.localizedTitle, action: #selector(didSelectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = duration
            item.state = (FanManager.shared.activeDuration == duration) ? .on : .off
            timerSubmenu.addItem(item)
        }

        timerItem.submenu = timerSubmenu
        menu.addItem(timerItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Live Fan Gauge & Control Center Slider View
        gaugeMenuItem = GaugeMenuItem()
        menu.addItem(gaugeMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Actions: Edit Profiles..., Settings..., Quit
        let editProfilesItem = NSMenuItem(title: loc.text(.editProfiles), action: #selector(openEditProfiles), keyEquivalent: "")
        editProfilesItem.target = self
        menu.addItem(editProfilesItem)

        let settingsItem = NSMenuItem(title: loc.text(.settings), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: loc.text(.quit), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    public func updateMenuState() {
        guard let menu = menu else { return }

        for item in menu.items {
            if let profile = item.representedObject as? FanProfile {
                item.state = (FanManager.shared.activeProfile.id == profile.id) ? .on : .off
            }
            if let submenu = item.submenu {
                for sub in submenu.items {
                    if let duration = sub.representedObject as? TimerDuration {
                        sub.state = (FanManager.shared.activeDuration == duration) ? .on : .off
                    }
                }
            }
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        FanManager.shared.updateTelemetry()
        FanManager.shared.checkHelperStatus()
        updateMenuState()
    }

    @objc private func didSelectProfileItem(_ sender: NSMenuItem) {
        if let profile = sender.representedObject as? FanProfile {
            FanManager.shared.selectProfile(profile)
            updateMenuState()
        }
    }

    @objc private func didSelectCustomSpeed(_ sender: NSMenuItem) {
        if let pct = sender.representedObject as? Float {
            FanManager.shared.setCustomFixedSpeed(percentage: pct)
            updateMenuState()
        }
    }

    @objc private func didSelectDuration(_ sender: NSMenuItem) {
        if let duration = sender.representedObject as? TimerDuration {
            FanManager.shared.selectDuration(duration)
            updateMenuState()
        }
    }

    @objc private func didClickCustomRPM() {
        let loc = LocalizationManager.shared
        let alert = NSAlert()
        alert.messageText = loc.text(.customFanSpeed)
        alert.informativeText = loc.text(.enterRPMDetails)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = "2500"
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let rpm = Float(input.stringValue) {
                FanManager.shared.setCustomRPM(rpm)
                updateMenuState()
            }
        }
    }

    @objc private func openEditProfiles() {
        SettingsWindowController.shared.show(tab: .profiles)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show(tab: .general)
    }

    @objc private func quitApp() {
        FanManager.shared.shutdown()
        NSApplication.shared.terminate(nil)
    }
}
