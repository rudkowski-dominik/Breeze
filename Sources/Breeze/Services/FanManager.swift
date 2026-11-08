import Foundation
import Combine
import AppKit

public enum TimerDuration: String, CaseIterable, Identifiable, Sendable {
    case indefinitely = "Indefinitely"
    case for15Mins = "For 15 minutes"
    case for30Mins = "For 30 minutes"
    case for1Hour = "For 1 hour"
    case for2Hours = "For 2 hours"
    case untilQuit = "Until app quits"

    public var id: String { rawValue }

    public var seconds: TimeInterval? {
        switch self {
        case .indefinitely, .untilQuit: return nil
        case .for15Mins: return 15 * 60
        case .for30Mins: return 30 * 60
        case .for1Hour: return 60 * 60
        case .for2Hours: return 120 * 60
        }
    }
}

public final class FanManager: ObservableObject, @unchecked Sendable {
    public static let shared = FanManager()

    @Published public var profiles: [FanProfile] = []
    @Published public var activeProfile: FanProfile
    @Published public var fans: [FanInfo] = []
    @Published public var currentTemperature: Float = 42.0
    @Published public var sensorReadings: [SensorReading] = []
    @Published public var statusMessage: String = "Monitoring · external manual control observed"
    @Published public var activeDuration: TimerDuration = .indefinitely
    @Published public var timerRemainingText: String? = nil
    @Published public var isHelperActive: Bool = false
    @Published public var isSystemSleeping: Bool = false

    private var monitorTimer: Timer?
    private var durationTimer: Timer?
    private var expiryDate: Date?

    // Slew rate controller & acoustic stabilization
    private var currentOutputRPM: Float?
    private var cooldownUntil: Date = Date.distantPast
    private let maxRampDownPerTick: Float = 75.0
    private let maxRampUpPerTick: Float = 150.0
    private let hysteresisHoldDuration: TimeInterval = 7.0

    private init() {
        let detectedFans = SMCEngine.shared.getFans()
        let hardwareMin = detectedFans.first?.minRPM ?? 1000.0
        let hardwareMax = detectedFans.first?.maxRPM ?? 4900.0

        let defaults = FanProfile.defaultProfiles(hardwareMin: hardwareMin, hardwareMax: hardwareMax)
        self.profiles = defaults
        self.activeProfile = defaults.first(where: { $0.type == .system }) ?? defaults[0]
        self.fans = detectedFans

        updateTelemetry()
        setupPowerAndSleepObservers()
        startAdaptiveMonitoringLoop()
    }

    // MARK: - Energy Optimization & Sleep Observers
    private func setupPowerAndSleepObservers() {
        let nc = NSWorkspace.shared.notificationCenter

        // 1. System Will Sleep -> Safe firmware handoff & pause timers
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isSystemSleeping = true
            self.monitorTimer?.invalidate()
            self.monitorTimer = nil

            // Release all fans back to native macOS firmware before sleep
            for fan in self.fans {
                _ = HelperClient.shared.resetToSystem(fanIndex: fan.id)
            }
        }

        // 2. System Did Wake -> Restore telemetry & reapply profile
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isSystemSleeping = false
            self.startAdaptiveMonitoringLoop()
            self.evaluateActiveProfile(force: true)
        }

        // 3. Screen Sleep -> Throttle polling to save energy
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, !self.isSystemSleeping else { return }
            self.restartMonitoringTimer(interval: 10.0) // 10s idle interval
        }

        // 4. Screen Wake -> Resume normal adaptive polling
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, !self.isSystemSleeping else { return }
            self.startAdaptiveMonitoringLoop()
        }
    }

    public func startAdaptiveMonitoringLoop() {
        // Adaptive polling interval: 4s when system manages, 1.5s when active curve regulates
        let interval: TimeInterval = (activeProfile.type == .system) ? 4.0 : 1.5
        restartMonitoringTimer(interval: interval)
    }

    private func restartMonitoringTimer(interval: TimeInterval) {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard !isSystemSleeping else { return }
        updateTelemetry()
        checkHelperStatus()
        evaluateActiveProfile()
        updateTimerStatus()
    }

    public func checkHelperStatus() {
        let running = HelperClient.shared.pingDaemon()
        if running != isHelperActive {
            DispatchQueue.main.async { self.isHelperActive = running }
        }
    }

    public func updateTelemetry() {
        let updatedFans = SMCEngine.shared.getFans()
        let temp = SMCEngine.shared.getPrimaryTemperature()
        let sensors = SMCEngine.shared.getTemperatureSensors()
        let loc = LocalizationManager.shared

        DispatchQueue.main.async {
            self.fans = updatedFans
            self.currentTemperature = temp
            self.sensorReadings = sensors

            if let fan = updatedFans.first {
                if self.activeProfile.type == .system {
                    self.statusMessage = fan.isManual ?
                        loc.text(.monitoringExternal) :
                        loc.text(.systemManaged)
                } else {
                    let tempStr = String(format: "%.1f", temp)
                    if let rem = self.timerRemainingText {
                        self.statusMessage = "\(self.activeProfile.name) (\(rem)) · SoC \(tempStr)°C"
                    } else {
                        self.statusMessage = loc.text(.activeProfileText(self.activeProfile.name, tempStr))
                    }
                }
            }
        }
    }

    public func selectProfile(_ profile: FanProfile) {
        activeProfile = profile
        currentOutputRPM = nil
        startAdaptiveMonitoringLoop() // Adjust interval dynamically
        evaluateActiveProfile(force: true)
    }

    public func selectDuration(_ duration: TimerDuration) {
        activeDuration = duration
        durationTimer?.invalidate()
        durationTimer = nil
        if let sec = duration.seconds {
            expiryDate = Date().addingTimeInterval(sec)
            durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.checkTimerExpiry()
            }
        } else {
            expiryDate = nil
            timerRemainingText = nil
        }
    }

    public func setCustomFixedSpeed(percentage: Float) {
        guard let fan = fans.first else { return }
        let clampedPct = max(0, min(100, percentage))
        let rpm = fan.minRPM + ((fan.maxRPM - fan.minRPM) * (clampedPct / 100.0))
        let custom = FanProfile(
            id: "custom_speed_\(Int(clampedPct))",
            name: "Custom (\(Int(clampedPct))%)",
            type: .custom,
            subtitle: "Fixed speed at \(Int(rpm)) RPM.",
            isManual: true,
            fixedRPM: rpm
        )
        selectProfile(custom)
    }

    public func setCustomRPM(_ rpm: Float) {
        guard let fan = fans.first else { return }
        let clamped = max(fan.minRPM, min(rpm, fan.maxRPM))
        let pct = Int(((clamped - fan.minRPM) / (fan.maxRPM - fan.minRPM)) * 100.0)
        let custom = FanProfile(
            id: "custom_rpm_\(Int(clamped))",
            name: "Custom (\(pct)%)",
            type: .custom,
            subtitle: "Fixed target at \(Int(clamped)) RPM.",
            isManual: true,
            fixedRPM: clamped
        )
        selectProfile(custom)
    }

    // MARK: - Multi-Fan Control Loop
    private func evaluateActiveProfile(force: Bool = false) {
        guard !fans.isEmpty else { return }

        // Thermal Runaway Watchdog: If any diode hits 86°C, ramp 100% on ALL fans
        if SMCEngine.shared.getInstantPeakTemperature() >= 86.0 && activeProfile.type != .system {
            applyTargetRPMToAll(maxAllFans: true)
            return
        }

        switch activeProfile.type {
        case .system:
            if fans.contains(where: { $0.isManual }) || force {
                for fan in fans {
                    _ = HelperClient.shared.resetToSystem(fanIndex: fan.id)
                }
                currentOutputRPM = nil
            }

        case .max:
            applyTargetRPMToAll(maxAllFans: true)

        case .systemPlus, .coolChassis, .gaming, .silent, .custom:
            var desiredRPM: Float
            if let fixed = activeProfile.fixedRPM {
                desiredRPM = fixed
            } else if let curve = activeProfile.curve {
                let firstFan = fans[0]
                desiredRPM = curve.calculateTargetRPM(
                    currentTemp: currentTemperature,
                    hardwareMin: firstFan.minRPM,
                    hardwareMax: firstFan.maxRPM
                )
            } else { return }

            let target = computeStabilizedRPM(desiredRPM: desiredRPM, currentActual: fans[0].actualRPM, force: force)
            applyTargetRPMToAll(targetRPM: target)
        }
    }

    private func computeStabilizedRPM(desiredRPM: Float, currentActual: Float, force: Bool) -> Float {
        guard let current = currentOutputRPM, !force else {
            currentOutputRPM = desiredRPM
            return desiredRPM
        }
        let diff = desiredRPM - current
        if abs(diff) < 50.0 { return current }
        let now = Date()
        if diff > 0 {
            cooldownUntil = now.addingTimeInterval(hysteresisHoldDuration)
            let next = current + min(diff, maxRampUpPerTick)
            currentOutputRPM = next
            return next
        } else {
            if now < cooldownUntil { return current }
            let next = current - min(abs(diff), maxRampDownPerTick)
            currentOutputRPM = next
            return next
        }
    }

    // Universal Multi-Fan Dispatch
    private func applyTargetRPMToAll(targetRPM: Float = 0, maxAllFans: Bool = false) {
        for fan in fans {
            let rpm = maxAllFans ? fan.maxRPM : max(fan.minRPM, min(targetRPM, fan.maxRPM))
            _ = HelperClient.shared.setFanSpeed(fanIndex: fan.id, targetRPM: rpm)
        }
    }

    private func checkTimerExpiry() {
        guard let expiry = expiryDate else { return }
        let rem = expiry.timeIntervalSinceNow
        if rem <= 0 {
            selectDuration(.indefinitely)
            if let sys = profiles.first(where: { $0.type == .system }) { selectProfile(sys) }
        } else {
            timerRemainingText = String(format: "%02d:%02d", Int(rem)/60, Int(rem)%60)
        }
    }

    private func updateTimerStatus() {
        if let expiry = expiryDate {
            let rem = expiry.timeIntervalSinceNow
            if rem > 0 { timerRemainingText = String(format: "%02d:%02d", Int(rem)/60, Int(rem)%60) }
        }
    }

    public func shutdown() {
        monitorTimer?.invalidate()
        durationTimer?.invalidate()
        for fan in fans {
            _ = HelperClient.shared.resetToSystem(fanIndex: fan.id)
        }
    }
}
