import Foundation
import Combine

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

    private var monitorTimer: Timer?
    private var durationTimer: Timer?
    private var expiryDate: Date?

    // Acoustic Stabilization & Slew Rate Controller:
    // Prevents fan surging, hunting, and revving
    private var currentOutputRPM: Float?
    private var cooldownUntil: Date = Date.distantPast
    private let maxRampDownPerTick: Float = 75.0 // RPM per 1.5s (~50 RPM/s)
    private let maxRampUpPerTick: Float = 150.0  // Smooth ramp up
    private let hysteresisHoldDuration: TimeInterval = 7.0 // Hold high speed 7s before ramping down

    private init() {
        let detectedFans = SMCEngine.shared.getFans()
        let hardwareMin = detectedFans.first?.minRPM ?? 1000.0
        let hardwareMax = detectedFans.first?.maxRPM ?? 4900.0

        let defaults = FanProfile.defaultProfiles(hardwareMin: hardwareMin, hardwareMax: hardwareMax)
        self.profiles = defaults
        self.activeProfile = defaults.first(where: { $0.type == .system }) ?? defaults[0]
        self.fans = detectedFans

        updateTelemetry()
        startMonitoringLoop()
    }

    public func startMonitoringLoop() {
        monitorTimer?.invalidate()
        // Run loop every 1.5s
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        updateTelemetry()
        checkHelperStatus()
        evaluateActiveProfile()
        updateTimerStatus()
    }

    public func checkHelperStatus() {
        let running = HelperClient.shared.pingDaemon()
        if running != isHelperActive {
            DispatchQueue.main.async {
                self.isHelperActive = running
            }
        }
    }

    public func updateTelemetry() {
        let updatedFans = SMCEngine.shared.getFans()
        let temp = SMCEngine.shared.getPrimaryTemperature()
        let sensors = SMCEngine.shared.getTemperatureSensors()

        DispatchQueue.main.async {
            self.fans = updatedFans
            self.currentTemperature = temp
            self.sensorReadings = sensors

            if let fan = updatedFans.first {
                if self.activeProfile.type == .system {
                    if fan.isManual {
                        self.statusMessage = "Monitoring · external manual control observed"
                    } else {
                        self.statusMessage = "System Managed · macOS Thermal Governance"
                    }
                } else {
                    if let remaining = self.timerRemainingText {
                        self.statusMessage = "\(self.activeProfile.name) (\(remaining)) · SoC \(String(format: "%.1f", temp))°C"
                    } else {
                        self.statusMessage = "\(self.activeProfile.name) Active · SoC \(String(format: "%.1f", temp))°C"
                    }
                }
            }
        }
    }

    public func selectProfile(_ profile: FanProfile) {
        activeProfile = profile
        currentOutputRPM = nil
        evaluateActiveProfile(force: true)
    }

    public func selectDuration(_ duration: TimerDuration) {
        activeDuration = duration
        durationTimer?.invalidate()
        durationTimer = nil

        if let seconds = duration.seconds {
            expiryDate = Date().addingTimeInterval(seconds)
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
        let customProfile = FanProfile(
            id: "custom_speed_\(Int(clampedPct))",
            name: "Custom (\(Int(clampedPct))%)",
            type: .custom,
            subtitle: "Fixed speed at \(Int(rpm)) RPM.",
            isManual: true,
            fixedRPM: rpm
        )
        selectProfile(customProfile)
    }

    public func setCustomRPM(_ rpm: Float) {
        guard let fan = fans.first else { return }
        let clamped = max(fan.minRPM, min(rpm, fan.maxRPM))
        let pct = Int(((clamped - fan.minRPM) / (fan.maxRPM - fan.minRPM)) * 100.0)
        let customProfile = FanProfile(
            id: "custom_rpm_\(Int(clamped))",
            name: "Custom (\(pct)%)",
            type: .custom,
            subtitle: "Fixed target at \(Int(clamped)) RPM.",
            isManual: true,
            fixedRPM: clamped
        )
        selectProfile(customProfile)
    }

    private func evaluateActiveProfile(force: Bool = false) {
        guard let fan = fans.first else { return }

        // Thermal Runaway Safety Watchdog:
        // If peak diode temperature hits 86°C, immediately force 100% cooling to protect hardware
        let peakTemp = SMCEngine.shared.getInstantPeakTemperature()
        if peakTemp >= 86.0 && activeProfile.type != .system {
            applyTargetRPM(fan.maxRPM, fanIndex: fan.id)
            return
        }

        switch activeProfile.type {
        case .system:
            if fan.isManual || force {
                _ = HelperClient.shared.resetToSystem(fanIndex: fan.id)
                currentOutputRPM = nil
            }

        case .max:
            applyTargetRPM(fan.maxRPM, fanIndex: fan.id)

        case .systemPlus, .coolChassis, .gaming, .silent, .custom:
            var desiredRPM: Float
            if let fixed = activeProfile.fixedRPM {
                desiredRPM = fixed
            } else if let curve = activeProfile.curve {
                desiredRPM = curve.calculateTargetRPM(
                    currentTemp: currentTemperature,
                    hardwareMin: fan.minRPM,
                    hardwareMax: fan.maxRPM
                )
            } else {
                return
            }

            // Apply acoustic stabilization with slew-rate limiting and cooldown hold
            let target = computeStabilizedRPM(desiredRPM: desiredRPM, currentActual: fan.actualRPM, force: force)
            applyTargetRPM(target, fanIndex: fan.id)
        }
    }

    /// Acoustic Stabilization Algorithm:
    /// Clamps rate of change so fans never jerk or jump abruptly
    private func computeStabilizedRPM(desiredRPM: Float, currentActual: Float, force: Bool) -> Float {
        guard let current = currentOutputRPM, !force else {
            currentOutputRPM = desiredRPM
            return desiredRPM
        }

        let diff = desiredRPM - current

        // Deadband: Ignore small jitter < 50 RPM
        if abs(diff) < 50.0 {
            return current
        }

        let now = Date()

        if diff > 0 {
            // Temperature is rising: ramp up smoothly
            cooldownUntil = now.addingTimeInterval(hysteresisHoldDuration)
            let step = min(diff, maxRampUpPerTick)
            let nextRPM = current + step
            currentOutputRPM = nextRPM
            return nextRPM
        } else {
            // Temperature is falling: apply hysteresis cooldown delay
            if now < cooldownUntil {
                // Hold higher speed until cooldown expires
                return current
            }
            // Ramp down gently like a whisper
            let step = min(abs(diff), maxRampDownPerTick)
            let nextRPM = current - step
            currentOutputRPM = nextRPM
            return nextRPM
        }
    }

    private func applyTargetRPM(_ rpm: Float, fanIndex: Int) {
        // Strict hardware bounds clamping
        guard let fan = fans.first(where: { $0.id == fanIndex }) ?? fans.first else { return }
        let clamped = max(fan.minRPM, min(rpm, fan.maxRPM))
        _ = HelperClient.shared.setFanSpeed(fanIndex: fanIndex, targetRPM: clamped)
    }

    private func checkTimerExpiry() {
        guard let expiry = expiryDate else { return }
        let remaining = expiry.timeIntervalSinceNow
        if remaining <= 0 {
            selectDuration(.indefinitely)
            if let sys = profiles.first(where: { $0.type == .system }) {
                selectProfile(sys)
            }
        } else {
            let mins = Int(remaining) / 60
            let secs = Int(remaining) % 60
            timerRemainingText = String(format: "%02d:%02d", mins, secs)
        }
    }

    private func updateTimerStatus() {
        if let expiry = expiryDate {
            let remaining = expiry.timeIntervalSinceNow
            if remaining > 0 {
                let mins = Int(remaining) / 60
                let secs = Int(remaining) % 60
                timerRemainingText = String(format: "%02d:%02d", mins, secs)
            }
        }
    }

    public func shutdown() {
        monitorTimer?.invalidate()
        durationTimer?.invalidate()
        // Safe exit: Hand control back to macOS firmware
        for fan in fans {
            _ = HelperClient.shared.resetToSystem(fanIndex: fan.id)
        }
    }
}
