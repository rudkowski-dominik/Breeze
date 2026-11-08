import SwiftUI
import AppKit

public enum IconThemeChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic = "auto"
    case dark = "dark"
    case light = "light"

    public var id: String { rawValue }
}

public final class SettingsViewModel: ObservableObject {
    @Published public var selectedTab: SettingsTab = .profiles
    public let profileEditorVM = ProfileEditorViewModel()
    @Published public var isInstallingHelper: Bool = false
    @Published public var installMessage: String? = nil
    @Published public var launchAtLogin: Bool = true

    @Published public var selectedLanguage: AppLanguage = LocalizationManager.shared.currentLanguage {
        didSet {
            LocalizationManager.shared.currentLanguage = selectedLanguage
            MenuBarController.shared.buildMenu()
        }
    }

    @Published public var selectedIconTheme: IconThemeChoice = .automatic {
        didSet {
            UserDefaults.standard.set(selectedIconTheme.rawValue, forKey: "breeze_icon_theme")
            applyIconTheme()
        }
    }

    @Published public var selectedMenuStyle: MenuBarDisplayStyle = MenuBarController.shared.displayStyle {
        didSet {
            MenuBarController.shared.displayStyle = selectedMenuStyle
        }
    }

    public init(initialTab: SettingsTab = .profiles) {
        self.selectedTab = initialTab

        if let savedTheme = UserDefaults.standard.string(forKey: "breeze_icon_theme"),
           let theme = IconThemeChoice(rawValue: savedTheme) {
            self.selectedIconTheme = theme
        }
        applyIconTheme()
    }

    public func applyIconTheme() {
        let isDark: Bool
        switch selectedIconTheme {
        case .automatic:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        case .dark:
            isDark = true
        case .light:
            isDark = false
        }

        let iconName = isDark ? "AppIcon-Dark.png" : "AppIcon-Light.png"
        let resourcePath = Bundle.main.bundlePath + "/Contents/Resources/" + iconName
        let fallbackPath = "/Users/dominik/.gemini/antigravity/scratch/Breeze/assets/" + iconName

        let path = FileManager.default.fileExists(atPath: resourcePath) ? resourcePath : fallbackPath
        if let iconImage = NSImage(contentsOfFile: path) {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }
}

public enum SettingsTab: String, CaseIterable, Identifiable {
    case profiles = "Profiles"
    case sensors = "Hardware Sensors"
    case helper = "Privileged Helper"
    case general = "General"

    public var id: String { rawValue }

    public func localizedTitle(loc: LocalizationManager) -> String {
        switch self {
        case .profiles: return loc.text(.tabProfiles)
        case .sensors: return loc.text(.tabSensors)
        case .helper: return loc.text(.tabHelper)
        case .general: return loc.text(.tabGeneral)
        }
    }

    public var icon: String {
        switch self {
        case .profiles: return "slider.horizontal.3"
        case .sensors: return "gauge.with.needle"
        case .helper: return "lock.shield"
        case .general: return "gearshape"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var manager = FanManager.shared
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var loc = LocalizationManager.shared

    public init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Header - rigidly locked at the top
            Picker("", selection: Binding(
                get: { viewModel.selectedTab },
                set: { viewModel.selectedTab = $0 }
            )) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.localizedTitle(loc: loc), systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // Content Container - fills exact remaining frame from top-left
            ZStack(alignment: .topLeading) {
                switch viewModel.selectedTab {
                case .profiles:
                    ProfileEditorView(viewModel: viewModel.profileEditorVM)
                case .sensors:
                    sensorsTab
                case .helper:
                    helperTab
                case .general:
                    generalTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 660, height: 480, alignment: .top)
    }

    private var sensorsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Silicon (\(manager.fans.count) \(manager.fans.count > 1 ? "Fans" : "Fan"))")
                        .font(.system(size: 16, weight: .bold))
                    Text("Real-time telemetry via AppleSMC and IOKit hardware clients.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                GroupBox(label: Label("Cooling Fans (\(manager.fans.count))", systemImage: "fanblades")) {
                    ForEach(manager.fans) { fan in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Fan \(fan.id)")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(fan.actualRPM)) RPM (\(Int(fan.percentage))%)")
                                    .font(.system(.body, design: .monospaced))
                            }
                            ProgressView(value: Double(fan.percentage), total: 100)
                            HStack {
                                Text("Min: \(Int(fan.minRPM)) RPM")
                                Spacer()
                                Text("Target: \(Int(fan.targetRPM)) RPM")
                                Spacer()
                                Text("Max: \(Int(fan.maxRPM)) RPM")
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                GroupBox(label: Label("Thermal Diode Matrix", systemImage: "thermometer.medium")) {
                    VStack(spacing: 8) {
                        ForEach(manager.sensorReadings) { sensor in
                            HStack {
                                Text(sensor.name)
                                    .font(.system(size: 12))
                                Spacer()
                                Text(sensor.key)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.trailing, 8)
                                Text("\(String(format: "%.1f", sensor.temperature)) °C")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(sensor.temperature > 75 ? .red : .primary)
                            }
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var helperTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: manager.isHelperActive ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 38))
                    .foregroundColor(manager.isHelperActive ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.isHelperActive ? loc.text(.helperActive) : loc.text(.helperInactive))
                        .font(.system(size: 16, weight: .bold))
                    Text("Low-level Apple Silicon SMC fan control via /var/run/breeze.sock")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            GroupBox(label: Label("Universal Multi-Fan & Watchdog Safety", systemImage: "shield.lefthalf.filled")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Breeze includes a background launchd helper daemon (`com.breeze.helper`). It manages all system fans (MacBook Pro dual fans, Mac mini, Mac Studio). A 30-second hardware watchdog automatically restores macOS native firmware control if the user application disconnects or crashes.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                        .padding(.vertical, 4)
                }
            }

            Spacer()

            if let msg = viewModel.installMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }

            HStack {
                Spacer()
                Button(action: installHelper) {
                    if viewModel.isInstallingHelper {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(manager.isHelperActive ? loc.text(.helperReinstallBtn) : loc.text(.helperInstallBtn))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isInstallingHelper)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Language Selection (EN, PL, ES)
                GroupBox(label: Label(loc.text(.language), systemImage: "globe")) {
                    Picker("", selection: Binding(
                        get: { viewModel.selectedLanguage },
                        set: { viewModel.selectedLanguage = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 6)
                }

                // 2. App Icon Theme Selector (Automatic, Dark Glass, Frosted White)
                GroupBox(label: Label(loc.text(.iconTheme), systemImage: "app.badge")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: Binding(
                            get: { viewModel.selectedIconTheme },
                            set: { viewModel.selectedIconTheme = $0 }
                        )) {
                            Text(loc.text(.iconThemeAuto)).tag(IconThemeChoice.automatic)
                            Text(loc.text(.iconThemeDark)).tag(IconThemeChoice.dark)
                            Text(loc.text(.iconThemeLight)).tag(IconThemeChoice.light)
                        }
                        .pickerStyle(.radioGroup)
                    }
                    .padding(.vertical, 4)
                }

                // 3. Menu Bar Display Style Selector
                GroupBox(label: Label(loc.text(.menuBarStyle), systemImage: "menubar.rectangle")) {
                    Picker("", selection: Binding(
                        get: { viewModel.selectedMenuStyle },
                        set: { viewModel.selectedMenuStyle = $0 }
                    )) {
                        Text(loc.text(.menuBarIconOnly)).tag(MenuBarDisplayStyle.iconOnly)
                        Text(loc.text(.menuBarIconTemp)).tag(MenuBarDisplayStyle.iconAndTemp)
                        Text(loc.text(.menuBarIconRPM)).tag(MenuBarDisplayStyle.iconAndRPM)
                    }
                    .pickerStyle(.radioGroup)
                    .padding(.vertical, 4)
                }

                // 4. Energy Optimization & Safety
                GroupBox(label: Label(loc.text(.energyOptimization), systemImage: "leaf")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc.text(.energyDesc))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Divider()
                        HStack {
                            Text(loc.text(.failsafeThreshold))
                            Spacer()
                            Text("86.0 °C")
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                        Text(loc.text(.failsafeDesc))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func installHelper() {
        viewModel.isInstallingHelper = true
        viewModel.installMessage = "Requesting administrator approval..."

        let helperBinaryPath = Bundle.main.bundlePath + "/Contents/Library/LaunchServices/breeze-helper"
        let fallbackPath = "/Users/dominik/.gemini/antigravity/scratch/Breeze/breeze-helper"
        let sourcePath = FileManager.default.fileExists(atPath: helperBinaryPath) ? helperBinaryPath : fallbackPath

        HelperClient.shared.triggerPrivilegedInstall(helperBinaryPath: sourcePath) { success in
            viewModel.isInstallingHelper = false
            if success {
                viewModel.installMessage = "Helper daemon installed successfully!"
                manager.checkHelperStatus()
            } else {
                viewModel.installMessage = "Installation failed or was cancelled."
            }
        }
    }
}
