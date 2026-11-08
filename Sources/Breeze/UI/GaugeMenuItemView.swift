import AppKit
import SwiftUI

public struct FanGaugeSwiftUIView: View {
    @ObservedObject var manager = FanManager.shared
    @ObservedObject var loc = LocalizationManager.shared

    public init() {}

    public var body: some View {
        let fan = manager.fans.first
        let pct = fan?.percentage ?? 0
        let rpm = fan?.actualRPM ?? 0

        VStack(spacing: 9) {
            // Sleek horizontal progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.secondary.opacity(0.25))

                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.85),
                                    Color.blue.opacity(0.95)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width * CGFloat(pct / 100.0), geo.size.width)))
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 22)

            // Fan Speed & RPM readout
            HStack(spacing: 6) {
                Text("\(Int(round(pct)))% · \(Int(round(rpm))) RPM")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                if manager.fans.count > 1 {
                    Text("(\(manager.fans.count) Fans)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            // Interactive Apple Control Center Style Slider
            HStack(spacing: 10) {
                Image(systemName: "fan")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { Double(pct) },
                    set: { newVal in
                        manager.setCustomFixedSpeed(percentage: Float(newVal))
                    }
                ), in: 0...100)
                .controlSize(.small)

                Image(systemName: "fan.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)

            // Status message
            Text(manager.statusMessage)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 14)
        }
        .padding(.vertical, 8)
        .frame(width: 260)
    }
}

public final class GaugeMenuItem: NSMenuItem {
    private let hostingView: NSHostingView<FanGaugeSwiftUIView>

    public init() {
        let swiftUIView = FanGaugeSwiftUIView()
        self.hostingView = NSHostingView(rootView: swiftUIView)
        super.init(title: "", action: nil, keyEquivalent: "")
        self.hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 102)
        self.view = hostingView
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
