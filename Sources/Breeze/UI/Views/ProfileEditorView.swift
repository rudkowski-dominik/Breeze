import SwiftUI

public final class ProfileEditorViewModel: ObservableObject {
    @Published public var selectedProfileId: String = "system"
    @Published public var isCreatingCustom: Bool = false

    // New profile form state
    @Published public var newName: String = "My Cooling Curve"
    @Published public var newStartTemp: Float = 45.0
    @Published public var newMaxTemp: Float = 75.0
    @Published public var newBaseRPM: Float = 1800.0
    @Published public var newMaxRPM: Float = 4500.0

    public init() {}
}

public struct ProfileEditorView: View {
    @ObservedObject var manager = FanManager.shared
    @ObservedObject var viewModel: ProfileEditorViewModel

    public init(viewModel: ProfileEditorViewModel = ProfileEditorViewModel()) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Profile List Sidebar
            VStack(alignment: .leading, spacing: 6) {
                Text("PROFILES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(manager.profiles) { profile in
                            let isSelected = (viewModel.selectedProfileId == profile.id)
                            Button(action: {
                                viewModel.selectedProfileId = profile.id
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(isSelected ? .white : .primary)
                                        Text(profile.type.rawValue)
                                            .font(.system(size: 10))
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                    }
                                    Spacer()
                                    if manager.activeProfile.id == profile.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(isSelected ? .white : .accentColor)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                }

                Divider()

                Button(action: { viewModel.isCreatingCustom.toggle() }) {
                    Label("Add Custom Profile", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .padding(12)
            }
            .frame(width: 200)

            Divider()

            // Profile Detail & Curve Editor
            VStack(alignment: .leading, spacing: 16) {
                if let profile = manager.profiles.first(where: { $0.id == viewModel.selectedProfileId }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(profile.name)
                                .font(.system(size: 20, weight: .bold))
                            Spacer()
                            Button("Activate Profile") {
                                manager.selectProfile(profile)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Text(profile.subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    if let curve = profile.curve {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cooling Curve Parameters")
                                .font(.system(size: 14, weight: .semibold))

                            // Curve Visualization
                            CurveGraphView(curve: curve)
                                .frame(height: 120)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                                GridRow {
                                    Text("Ramp Start Temp:")
                                        .foregroundColor(.secondary)
                                    Text("\(Int(curve.startTemp)) °C")
                                        .fontWeight(.medium)
                                }
                                GridRow {
                                    Text("Max Fan Speed Temp:")
                                        .foregroundColor(.secondary)
                                    Text("\(Int(curve.maxTemp)) °C")
                                        .fontWeight(.medium)
                                }
                                GridRow {
                                    Text("Base Idle Speed:")
                                        .foregroundColor(.secondary)
                                    Text("\(Int(curve.baseRPM)) RPM")
                                        .fontWeight(.medium)
                                }
                                GridRow {
                                    Text("Target Peak Speed:")
                                        .foregroundColor(.secondary)
                                    Text("\(Int(curve.maxRPM)) RPM")
                                        .fontWeight(.medium)
                                }
                            }
                            .font(.system(size: 12))
                        }
                    } else if profile.type == .system {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apple Silicon Hardware Management")
                                .font(.system(size: 14, weight: .semibold))
                            Text("In System mode, the Apple Silicon SMC and CLPC (Closed Loop Performance Controller) determine fan speeds dynamically based on hundreds of internal thermal diode matrices.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    } else if profile.type == .max {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maximum Airflow Override")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Forces the fan to 100% duty cycle (4900 RPM) for rapid cooling after extreme workloads or benchmark runs.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                } else {
                    Text("Select a profile to view details.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(20)
            .sheet(isPresented: Binding(
                get: { viewModel.isCreatingCustom },
                set: { viewModel.isCreatingCustom = $0 }
            )) {
                createCustomProfileSheet
            }
        }
    }

    private var createCustomProfileSheet: some View {
        VStack(spacing: 16) {
            Text("Create Custom Profile")
                .font(.headline)

            Form {
                TextField("Profile Name:", text: Binding(
                    get: { viewModel.newName },
                    set: { viewModel.newName = $0 }
                ))

                Slider(value: Binding(
                    get: { viewModel.newStartTemp },
                    set: { viewModel.newStartTemp = $0 }
                ), in: 30...70, step: 1) {
                    Text("Start Temp: \(Int(viewModel.newStartTemp)) °C")
                }

                Slider(value: Binding(
                    get: { viewModel.newMaxTemp },
                    set: { viewModel.newMaxTemp = $0 }
                ), in: 60...95, step: 1) {
                    Text("Max Temp: \(Int(viewModel.newMaxTemp)) °C")
                }

                Slider(value: Binding(
                    get: { viewModel.newBaseRPM },
                    set: { viewModel.newBaseRPM = $0 }
                ), in: 1000...3000, step: 50) {
                    Text("Base RPM: \(Int(viewModel.newBaseRPM))")
                }

                Slider(value: Binding(
                    get: { viewModel.newMaxRPM },
                    set: { viewModel.newMaxRPM = $0 }
                ), in: 3000...4900, step: 50) {
                    Text("Max RPM: \(Int(viewModel.newMaxRPM))")
                }
            }
            .padding()

            HStack {
                Button("Cancel") { viewModel.isCreatingCustom = false }
                Spacer()
                Button("Save Profile") {
                    let custom = FanProfile(
                        id: "custom_\(UUID().uuidString.prefix(6))",
                        name: viewModel.newName,
                        type: .custom,
                        subtitle: "Custom curve: \(Int(viewModel.newBaseRPM))-\(Int(viewModel.newMaxRPM)) RPM",
                        isManual: true,
                        curve: CoolingCurve(
                            startTemp: viewModel.newStartTemp,
                            maxTemp: viewModel.newMaxTemp,
                            baseRPM: viewModel.newBaseRPM,
                            maxRPM: viewModel.newMaxRPM
                        )
                    )
                    manager.profiles.append(custom)
                    manager.selectProfile(custom)
                    viewModel.selectedProfileId = custom.id
                    viewModel.isCreatingCustom = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 380, height: 340)
    }
}

// Curve Graph visualizer
public struct CurveGraphView: View {
    public let curve: CoolingCurve

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Path { path in
                let points = 50
                for i in 0...points {
                    let temp = 30.0 + (Float(i) / Float(points)) * 65.0 // 30°C to 95°C
                    let rpm = curve.calculateTargetRPM(currentTemp: temp, hardwareMin: 1000, hardwareMax: 4900)

                    let x = CGFloat((temp - 30.0) / 65.0) * w
                    let y = h - CGFloat((rpm - 1000.0) / 3900.0) * h

                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, lineWidth: 2.5)

            // Current temperature marker
            let curTemp = FanManager.shared.currentTemperature
            let curX = max(0, min(w, CGFloat((curTemp - 30.0) / 65.0) * w))
            Path { path in
                path.move(to: CGPoint(x: curX, y: 0))
                path.addLine(to: CGPoint(x: curX, y: h))
            }
            .stroke(Color.red.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .padding(8)
    }
}
