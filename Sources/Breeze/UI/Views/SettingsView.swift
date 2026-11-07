import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case profiles = "Profiles"
    case sensors = "Hardware Sensors"
    case helper = "Privileged Helper"
    case general = "General"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .profiles: return "slider.horizontal.3"
        case .sensors: return "gauge.with.needle"
        case .helper: return "lock.shield"
        case .general: return "gearshape"
        }
    }
}

public final class SettingsViewModel: ObservableObject {
    @Published public var selectedTab: SettingsTab = .profiles
    @Published public var isInstallingHelper: Bool = false
    @Published public var installMessage: String? = nil
    @Published public var launchAtLogin: Bool = true
    @Published public var showRPMInMenuBar: Bool = false
    @Published public var showTempInMenuBar: Bool = false

    public init(initialTab: SettingsTab = .profiles) {
        self.selectedTab = initialTab
    }
}

public struct SettingsView: View {
    @ObservedObject var manager = FanManager.shared
    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Apple-style tab bar header
            Picker("", selection: Binding(
                get: { viewModel.selectedTab },
                set: { viewModel.selectedTab = $0 }
            )) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Tab Content
            Group {
                switch viewModel.selectedTab {
                case .profiles:
                    ProfileEditorView()
                case .sensors:
                    sensorsTab
                case .helper:
                    helperTab
                case .general:
                    generalTab
                }
            }
        }
        .frame(width: 620, height: 440)
    }

    // Hardware Sensors Tab
    private var sensorsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header hardware info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac mini (Apple M5 Pro)")
                        .font(.system(size: 16, weight: .bold))
                    Text("Real-time telemetry polled via AppleSMC and IOKit hardware clients.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                // Fan Telemetry Box
                GroupBox(label: Label("Cooling Fans", systemImage: "fanblades")) {
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

                // Temperatures Box
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
            .padding(20)
        }
    }

    // Privileged Helper Tool Tab
    private var helperTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: manager.isHelperActive ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 36))
                    .foregroundColor(manager.isHelperActive ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isHelperActive ? "Privileged Helper Daemon is Active" : "Helper Daemon Not Installed / Inactive")
                        .font(.system(size: 15, weight: .bold))
                    Text(manager.isHelperActive ? "Low-level SMC fan speed override is fully operational." : "Apple Silicon requires root privileges to modify fan SMC keys.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Text("How Apple Silicon Fan Control Works")
                .font(.system(size: 13, weight: .semibold))

            Text("On Apple Silicon (M1, M2, M3, M4, M5), macOS restricts writing to SMC fan control registers (F0Tg, F0md) to root (UID 0). Reading fan speeds and temperatures does not require privileges.\n\nBreeze uses a lightweight background helper daemon (`com.breeze.helper`) communicating through a local Unix domain socket. Once installed, you will never be prompted for your password again when changing fan profiles.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(3)

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
                        Text(manager.isHelperActive ? "Reinstall Helper Daemon" : "Install Privileged Helper...")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isInstallingHelper)
            }
        }
        .padding(24)
    }

    // General Settings Tab
    private var generalTab: some View {
        Form {
            Section(header: Text("Appearance").font(.headline)) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.launchAtLogin = $0 }
                ))
                Toggle("Show Live RPM in Menu Bar", isOn: Binding(
                    get: { viewModel.showRPMInMenuBar },
                    set: { viewModel.showRPMInMenuBar = $0 }
                ))
                Toggle("Show SoC Temperature in Menu Bar", isOn: Binding(
                    get: { viewModel.showTempInMenuBar },
                    set: { viewModel.showTempInMenuBar = $0 }
                ))
            }

            Section(header: Text("Safety & Thermal Governance").font(.headline)) {
                HStack {
                    Text("Emergency Failsafe Threshold:")
                    Spacer()
                    Text("88.0 °C")
                        .foregroundColor(.secondary)
                }
                Text("If the SoC temperature exceeds 88°C, Breeze will automatically override any active profile and ramp fans to maximum.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
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
                viewModel.installMessage = "Installation failed or was cancelled. You can also run the install script in Terminal."
            }
        }
    }
}
