# Pełny Kod Źródłowy Aplikacji Breeze (Apple Silicon Fan Control)
Wygenerowano dla celów audytu i skanowania kodu przez zewnętrznego agenta.

---
## Plik: `Sources/Breeze/AppDelegate.swift`
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory app (hidden from Dock, visible in status bar)
        NSApp.setActivationPolicy(.accessory)

        // Register safety signal handlers to ensure fans always revert to System mode
        signal(SIGINT) { _ in
            FanManager.shared.shutdown()
            exit(0)
        }
        signal(SIGTERM) { _ in
            FanManager.shared.shutdown()
            exit(0)
        }
        signal(SIGHUP) { _ in
            FanManager.shared.shutdown()
            exit(0)
        }

        // Initialize status bar controller
        MenuBarController.shared.setup()

        // Initialize telemetry
        FanManager.shared.updateTelemetry()
    }

    func applicationWillTerminate(_ notification: Notification) {
        FanManager.shared.shutdown()
    }
}
```

---
## Plik: `Sources/Breeze/Models/FanProfile.swift`
```swift
import Foundation

public enum ProfileType: String, Codable, CaseIterable, Sendable {
    case system = "System"
    case max = "Max"
    case systemPlus = "System+"
    case coolChassis = "Cool Chassis"
    case gaming = "Gaming"
    case silent = "Silent"
    case custom = "Custom"

    public var bestForDescription: String {
        switch self {
        case .system:
            return "Lets macOS manage the fans."
        case .max:
            return "Runs each fan at its maximum."
        case .systemPlus:
            return "Gentle, earlier airflow for everyday use."
        case .coolChassis:
            return "Keeps the typing area cool and comfortable."
        case .gaming:
            return "Very early and stronger cooling during sustained loads."
        case .silent:
            return "Keeps the fans slower for quiet environments."
        case .custom:
            return "Create your own cooling curves and temperature targets."
        }
    }
}

public struct CoolingCurve: Codable, Equatable, Sendable {
    public var startTemp: Float      // Temperature where fan begins ramping above floor (°C)
    public var maxTemp: Float        // Temperature where fan hits curve max RPM (°C)
    public var baseRPM: Float        // Baseline idle RPM floor
    public var maxRPM: Float         // Target peak RPM

    public init(startTemp: Float, maxTemp: Float, baseRPM: Float, maxRPM: Float) {
        self.startTemp = startTemp
        self.maxTemp = maxTemp
        self.baseRPM = baseRPM
        self.maxRPM = maxRPM
    }

    public func calculateTargetRPM(currentTemp: Float, hardwareMin: Float, hardwareMax: Float) -> Float {
        let effBase = max(hardwareMin, min(baseRPM, hardwareMax))
        let effMax = max(effBase, min(hardwareMax, maxRPM))

        if currentTemp <= startTemp {
            return effBase
        } else if currentTemp >= maxTemp {
            return effMax
        } else {
            let progress = (currentTemp - startTemp) / max(1.0, (maxTemp - startTemp))
            // Smooth S-curve (cubic hermite interpolation) to avoid sharp acoustic inflection points
            let smoothed = progress * progress * (3.0 - 2.0 * progress)
            return effBase + smoothed * (effMax - effBase)
        }
    }
}

public struct FanProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var type: ProfileType
    public var subtitle: String
    public var isManual: Bool
    public var fixedRPM: Float?
    public var curve: CoolingCurve?

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: ProfileType,
        subtitle: String,
        isManual: Bool = true,
        fixedRPM: Float? = nil,
        curve: CoolingCurve? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.subtitle = subtitle
        self.isManual = isManual
        self.fixedRPM = fixedRPM
        self.curve = curve
    }

    public static func defaultProfiles(hardwareMin: Float = 1000.0, hardwareMax: Float = 4900.0) -> [FanProfile] {
        return [
            FanProfile(
                id: "system",
                name: "System",
                type: .system,
                subtitle: "Lets macOS manage the fans.",
                isManual: false
            ),
            FanProfile(
                id: "max",
                name: "Max",
                type: .max,
                subtitle: "Runs each fan at its maximum.",
                isManual: true,
                fixedRPM: hardwareMax
            ),
            FanProfile(
                id: "system_plus",
                name: "System+",
                type: .systemPlus,
                subtitle: "Gentle, earlier airflow for everyday use.",
                isManual: true,
                curve: CoolingCurve(
                    startTemp: 58.0,
                    maxTemp: 84.0,
                    baseRPM: 1700.0, // Quiet gentle airflow, inaudible on Mac mini
                    maxRPM: 3400.0
                )
            ),
            FanProfile(
                id: "cool_chassis",
                name: "Cool Chassis",
                type: .coolChassis,
                subtitle: "Keeps the typing area cool and comfortable.",
                isManual: true,
                curve: CoolingCurve(
                    startTemp: 50.0,
                    maxTemp: 78.0,
                    baseRPM: 2400.0,
                    maxRPM: 4000.0
                )
            ),
            FanProfile(
                id: "gaming",
                name: "Gaming",
                type: .gaming,
                subtitle: "Very early and stronger cooling during sustained loads.",
                isManual: true,
                curve: CoolingCurve(
                    startTemp: 45.0,
                    maxTemp: 74.0,
                    baseRPM: 3400.0,
                    maxRPM: hardwareMax
                )
            ),
            FanProfile(
                id: "silent",
                name: "Silent",
                type: .silent,
                subtitle: "Keeps the fans slower for quiet environments.",
                isManual: true,
                curve: CoolingCurve(
                    startTemp: 76.0,
                    maxTemp: 90.0,
                    baseRPM: hardwareMin,
                    maxRPM: 2800.0
                )
            )
        ]
    }
}
```

---
## Plik: `Sources/Breeze/SMC/SMCEngine.swift`
```swift
import Foundation
import IOKit

public struct FanInfo: Identifiable, Sendable {
    public let id: Int
    public var actualRPM: Float
    public var targetRPM: Float
    public var minRPM: Float
    public var maxRPM: Float
    public var isManual: Bool

    public var percentage: Float {
        guard maxRPM > minRPM else { return 0 }
        let clamped = max(minRPM, min(actualRPM, maxRPM))
        return ((clamped - minRPM) / (maxRPM - minRPM)) * 100.0
    }
}

public struct SensorReading: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let temperature: Float
}

public final class SMCEngine: @unchecked Sendable {
    public static let shared = SMCEngine()

    private var connection: io_connect_t = 0
    private let lock = NSLock()

    // Low-pass filtered temperature state to prevent fan oscillation
    private var smoothedTemperature: Float?
    private let smoothingFactor: Float = 0.20 // EMA alpha: smooths over ~8-10 seconds

    // SMC internal struct definitions
    private struct SMCKeyData_vers {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCKeyData_pLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyData_keyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCKeyData_vers()
        var pLimitData = SMCKeyData_pLimitData()
        var keyInfo = SMCKeyData_keyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private init() {
        _ = openConnection()
    }

    deinit {
        closeConnection()
    }

    public func openConnection() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            return true
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }

        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        return kr == KERN_SUCCESS
    }

    public func closeConnection() {
        lock.lock()
        defer { lock.unlock() }

        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    private func fourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for char in str.utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    private func fourCharCodeToString(_ code: UInt32) -> String {
        let b1 = Character(UnicodeScalar((code >> 24) & 0xFF)!)
        let b2 = Character(UnicodeScalar((code >> 16) & 0xFF)!)
        let b3 = Character(UnicodeScalar((code >> 8) & 0xFF)!)
        let b4 = Character(UnicodeScalar(code & 0xFF)!)
        return "\(b1)\(b2)\(b3)\(b4)"
    }

    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        guard connection != 0 || openConnection() else { return KERN_FAILURE }
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        return IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
    }

    private func getKeyInfo(keyStr: String) -> (dataType: UInt32, dataSize: UInt32)? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = 9 // SMC_CMD_READ_KEYINFO
        let res = callSMC(input: &input, output: &output)
        if res == KERN_SUCCESS && output.result == 0 {
            return (output.keyInfo.dataType, output.keyInfo.dataSize)
        }
        return nil
    }

    public func readBytes(keyStr: String) -> (dataType: String, bytes: [UInt8])? {
        lock.lock()
        defer { lock.unlock() }

        guard let info = getKeyInfo(keyStr: keyStr) else { return nil }
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5 // SMC_CMD_READ_BYTES
        let res = callSMC(input: &input, output: &output)
        guard res == KERN_SUCCESS && output.result == 0 else { return nil }

        let mirror = Mirror(reflecting: output.bytes)
        var bytes = [UInt8]()
        for (_, child) in mirror.children {
            if bytes.count < Int(info.dataSize) {
                bytes.append(child as! UInt8)
            }
        }
        return (fourCharCodeToString(info.dataType), bytes)
    }

    public func readFloat(keyStr: String) -> Float? {
        guard let result = readBytes(keyStr: keyStr) else { return nil }
        if result.dataType == "flt " && result.bytes.count >= 4 {
            return result.bytes.withUnsafeBytes { $0.load(as: Float.self) }
        } else if result.dataType == "sp78" && result.bytes.count >= 2 {
            return Float(Int16(result.bytes[0]) << 8 | Int16(result.bytes[1])) / 256.0
        }
        return nil
    }

    public func readUInt8(keyStr: String) -> UInt8? {
        guard let result = readBytes(keyStr: keyStr), !result.bytes.isEmpty else { return nil }
        return result.bytes[0]
    }

    public func writeBytes(keyStr: String, bytes: [UInt8]) -> (kern_return_t, UInt8) {
        lock.lock()
        defer { lock.unlock() }

        guard let info = getKeyInfo(keyStr: keyStr) else { return (KERN_FAILURE, 255) }
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = 6 // SMC_CMD_WRITE_BYTES
        input.keyInfo.dataSize = info.dataSize

        withUnsafeMutableBytes(of: &input.bytes) { rawPtr in
            for i in 0..<min(bytes.count, Int(info.dataSize)) {
                rawPtr[i] = bytes[i]
            }
        }

        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let res = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
        return (res, output.result)
    }

    public func writeFloat(keyStr: String, value: Float) -> Bool {
        var val = value
        let bytes = withUnsafeBytes(of: &val) { Array($0) }
        let (kr, smcRes) = writeBytes(keyStr: keyStr, bytes: bytes)
        return kr == KERN_SUCCESS && smcRes == 0
    }

    public func writeUInt8(keyStr: String, value: UInt8) -> Bool {
        let (kr, smcRes) = writeBytes(keyStr: keyStr, bytes: [value])
        return kr == KERN_SUCCESS && smcRes == 0
    }

    public func getFanCount() -> Int {
        if let count = readUInt8(keyStr: "FNum") {
            return Int(count)
        }
        return 0
    }

    public func getFans() -> [FanInfo] {
        let count = getFanCount()
        var fans: [FanInfo] = []

        for i in 0..<count {
            let actual = readFloat(keyStr: "F\(i)Ac") ?? 0
            let target = readFloat(keyStr: "F\(i)Tg") ?? actual
            let minRpm = readFloat(keyStr: "F\(i)Mn") ?? 1000
            let maxRpm = readFloat(keyStr: "F\(i)Mx") ?? 4900
            let mode = readUInt8(keyStr: "F\(i)md") ?? readUInt8(keyStr: "F\(i)Md") ?? 0
            let isManual = (mode != 0)

            fans.append(FanInfo(
                id: i,
                actualRPM: actual,
                targetRPM: target,
                minRPM: minRpm,
                maxRPM: maxRpm,
                isManual: isManual
            ))
        }
        return fans
    }

    public func getTemperatureSensors() -> [SensorReading] {
        let sensorMap: [(key: String, name: String)] = [
            ("TCMb", "SoC / CPU Package"),
            ("TPD0", "Power Delivery (PMU)"),
            ("TM0p", "Unified Memory"),
            ("TH0a", "Heatsink Primary"),
            ("TH0b", "Chassis Exhaust"),
            ("TN00", "PCIe Controller"),
            ("TPCP", "SoC Power Rail")
        ]

        var readings: [SensorReading] = []
        for sensor in sensorMap {
            if let temp = readFloat(keyStr: sensor.key), temp > 15.0 && temp < 120.0 {
                readings.append(SensorReading(key: sensor.key, name: sensor.name, temperature: temp))
            }
        }
        return readings
    }

    /// Returns a thermally stable, low-pass filtered temperature.
    /// This combines SoC silicon temperature with Heatsink temperature and applies EMA smoothing,
    /// preventing sudden fan revving / hunting caused by transient microbursts.
    public func getPrimaryTemperature() -> Float {
        let tcmb = readFloat(keyStr: "TCMb") ?? 45.0
        let heatsink = readFloat(keyStr: "TH0a") ?? (tcmb - 15.0)

        // Balanced thermal metric: 40% SoC core junction + 60% heatsink thermal mass
        // This accurately represents actual thermal load without reacting wildly to 100ms spikes
        let rawWeighted = (tcmb * 0.40) + (max(heatsink + 12.0, tcmb * 0.70) * 0.60)

        if let prev = smoothedTemperature {
            let smoothed = (smoothingFactor * rawWeighted) + ((1.0 - smoothingFactor) * prev)
            smoothedTemperature = smoothed
            return smoothed
        } else {
            smoothedTemperature = rawWeighted
            return rawWeighted
        }
    }

    /// Instant raw peak temperature across all core diodes (used for emergency safety checks)
    public func getInstantPeakTemperature() -> Float {
        let tcmb = readFloat(keyStr: "TCMb") ?? 0
        let tpd0 = readFloat(keyStr: "TPD0") ?? 0
        return max(tcmb, tpd0)
    }
}
```

---
## Plik: `Sources/Breeze/Services/FanManager.swift`
```swift
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
```

---
## Plik: `Sources/Breeze/Services/HelperClient.swift`
```swift
import Foundation

public final class HelperClient: @unchecked Sendable {
    public static let shared = HelperClient()

    private let socketPath = "/var/run/breeze.sock"
    private let installedHelperPath = "/Library/PrivilegedHelperTools/com.breeze.helper"
    private let lock = NSLock()

    private init() {}

    public var isDaemonRunning: Bool {
        return pingDaemon()
    }

    public var isHelperBinaryInstalled: Bool {
        return FileManager.default.fileExists(atPath: installedHelperPath)
    }

    public func pingDaemon() -> Bool {
        guard let response = sendSocketMessage("PING\n") else { return false }
        return response.contains("PONG")
    }

    public func setFanSpeed(fanIndex: Int, targetRPM: Float) -> Bool {
        // Try socket daemon first (instant, 0 password prompts)
        if let response = sendSocketMessage("SET_SPEED \(fanIndex) \(String(format: "%.0f", targetRPM))\n") {
            if response.contains("OK") { return true }
        }

        // Try direct SMC write if we happen to run with privileges
        if SMCEngine.shared.writeUInt8(keyStr: "F\(fanIndex)md", value: 1) &&
           SMCEngine.shared.writeFloat(keyStr: "F\(fanIndex)Tg", value: targetRPM) {
            return true
        }

        return false
    }

    public func resetToSystem(fanIndex: Int) -> Bool {
        if let response = sendSocketMessage("SET_SYSTEM \(fanIndex)\n") {
            if response.contains("OK") { return true }
        }

        if SMCEngine.shared.writeUInt8(keyStr: "F\(fanIndex)md", value: 0) {
            return true
        }

        return false
    }

    private func sendSocketMessage(_ message: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }

        let clientFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard clientFd >= 0 else { return nil }
        defer { close(clientFd) }

        // Set 500ms timeout
        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            socketPath.withCString { cstr in
                _ = strcpy(raw.assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                connect(clientFd, saPtr, addrLen)
            }
        }

        guard connectRes == 0 else { return nil }

        guard message.withCString({ write(clientFd, $0, strlen($0)) }) > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = read(clientFd, &buffer, 256)
        if bytesRead > 0 {
            return String(bytes: buffer.prefix(bytesRead), encoding: .utf8)
        }

        return nil
    }

    public func triggerPrivilegedInstall(helperBinaryPath: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.breeze.helper</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/Library/PrivilegedHelperTools/com.breeze.helper</string>
                    <string>daemon</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
            </dict>
            </plist>
            """

            let tempPlistPath = "/tmp/com.breeze.helper.plist"
            try? plistContent.write(toFile: tempPlistPath, atomically: true, encoding: .utf8)

            let script = """
            mkdir -p /Library/PrivilegedHelperTools
            cp "\(helperBinaryPath)" /Library/PrivilegedHelperTools/com.breeze.helper
            chmod 755 /Library/PrivilegedHelperTools/com.breeze.helper
            chown root:wheel /Library/PrivilegedHelperTools/com.breeze.helper
            cp "\(tempPlistPath)" /Library/LaunchDaemons/com.breeze.helper.plist
            chmod 644 /Library/LaunchDaemons/com.breeze.helper.plist
            chown root:wheel /Library/LaunchDaemons/com.breeze.helper.plist
            launchctl unload /Library/LaunchDaemons/com.breeze.helper.plist 2>/dev/null || true
            launchctl load -w /Library/LaunchDaemons/com.breeze.helper.plist
            """

            let appleScript = "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: appleScript) {
                scriptObject.executeAndReturnError(&error)
            }

            // Sleep a moment to allow daemon to bind
            Thread.sleep(forTimeInterval: 0.8)
            let running = self.pingDaemon()
            DispatchQueue.main.async {
                completion(running)
            }
        }
    }
}
```

---
## Plik: `Sources/Breeze/UI/GaugeMenuItemView.swift`
```swift
import AppKit
import SwiftUI

public struct FanGaugeSwiftUIView: View {
    @ObservedObject var manager = FanManager.shared

    public init() {}

    public var body: some View {
        let fan = manager.fans.first
        let pct = fan?.percentage ?? 0
        let rpm = fan?.actualRPM ?? 0

        VStack(spacing: 7) {
            // Sleek horizontal progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.secondary.opacity(0.25))

                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.85),
                                    Color.white.opacity(0.95)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width * CGFloat(pct / 100.0), geo.size.width)))
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 24)

            // Fan Speed & RPM readout
            Text("\(Int(round(pct)))% · \(Int(round(rpm))) RPM")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            // Status message
            Text(manager.statusMessage)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .frame(width: 250)
    }
}

public final class GaugeMenuItem: NSMenuItem {
    private let hostingView: NSHostingView<FanGaugeSwiftUIView>

    public init() {
        let swiftUIView = FanGaugeSwiftUIView()
        self.hostingView = NSHostingView(rootView: swiftUIView)
        super.init(title: "", action: nil, keyEquivalent: "")
        self.hostingView.frame = NSRect(x: 0, y: 0, width: 250, height: 74)
        self.view = hostingView
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

---
## Plik: `Sources/Breeze/UI/MenuBarController.swift`
```swift
import AppKit
import SwiftUI

public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var gaugeMenuItem: GaugeMenuItem!
    private var refreshTimer: Timer?

    private override init() {
        super.init()
    }

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = createAppleStyleFanIcon()
            button.imagePosition = .imageOnly
        }

        buildMenu()
        statusItem.menu = menu

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateMenuState()
        }
    }

    /// Creates an ultra-clean, Apple-minimalist vector fan icon for the macOS Menu Bar.
    /// Perfectly aligned to the 18x18pt optical grid with native line weight and template vibrancy.
    private func createAppleStyleFanIcon() -> NSImage {
        // Try the refined native SF Symbol "fan" with precise Apple proportions
        if let sfImage = NSImage(systemSymbolName: "fan", accessibilityDescription: "Breeze Fan Control") {
            let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .regular)
            if let configured = sfImage.withSymbolConfiguration(config) {
                configured.isTemplate = true
                return configured
            }
        }

        // Custom high-precision vector drawing fallback
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: 9, y: 9)
            let hubRadius: CGFloat = 1.75
            let bladeRadius: CGFloat = 6.2

            ctx.setStrokeColor(NSColor.labelColor.cgColor)
            ctx.setFillColor(NSColor.labelColor.cgColor)
            ctx.setLineWidth(1.25)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Draw 3 elegant Apple-style aerodynamic blades
            for i in 0..<3 {
                let angle = CGFloat(i) * (2.0 * CGFloat.pi / 3.0) - (CGFloat.pi / 2.0)
                let endAngle = angle + 0.65

                let startX = center.x + hubRadius * cos(angle)
                let startY = center.y + hubRadius * sin(angle)
                let tipX = center.x + bladeRadius * cos(endAngle)
                let tipY = center.y + bladeRadius * sin(endAngle)

                let cpX = center.x + (bladeRadius * 0.7) * cos(angle + 0.35)
                let cpY = center.y + (bladeRadius * 0.7) * sin(angle + 0.35)

                let path = CGMutablePath()
                path.move(to: CGPoint(x: startX, y: startY))
                path.addQuadCurve(to: CGPoint(x: tipX, y: tipY), control: CGPoint(x: cpX, y: cpY))
                path.addArc(center: center, radius: bladeRadius, startAngle: endAngle, endAngle: endAngle + 0.25, clockwise: false)
                path.addLine(to: CGPoint(x: center.x + hubRadius * cos(angle + 0.4), y: center.y + hubRadius * sin(angle + 0.4)))
                path.closeSubpath()

                ctx.addPath(path)
                ctx.fillPath()
            }

            // Draw central hub
            ctx.addArc(center: center, radius: hubRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.fillPath()

            return true
        }

        image.isTemplate = true
        return image
    }

    public func buildMenu() {
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        // 1. Predefined Profiles
        for profile in FanManager.shared.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(didSelectProfileItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile
            item.state = (FanManager.shared.activeProfile.id == profile.id) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Custom Fan Speed submenu
        let customSpeedItem = NSMenuItem(title: "Custom Fan Speed", action: nil, keyEquivalent: "")
        let speedSubmenu = NSMenu(title: "Custom Fan Speed")

        let speeds: [(title: String, pct: Float)] = [
            ("Min Speed (0% · 1000 RPM)", 0),
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
        let promptRpmItem = NSMenuItem(title: "Enter Custom RPM...", action: #selector(didClickCustomRPM), keyEquivalent: "")
        promptRpmItem.target = self
        speedSubmenu.addItem(promptRpmItem)

        customSpeedItem.submenu = speedSubmenu
        menu.addItem(customSpeedItem)

        // 3. Activate for/until submenu
        let timerItem = NSMenuItem(title: "Activate for/until", action: nil, keyEquivalent: "")
        let timerSubmenu = NSMenu(title: "Activate for/until")

        for duration in TimerDuration.allCases {
            let item = NSMenuItem(title: duration.rawValue, action: #selector(didSelectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = duration
            item.state = (FanManager.shared.activeDuration == duration) ? .on : .off
            timerSubmenu.addItem(item)
        }

        timerItem.submenu = timerSubmenu
        menu.addItem(timerItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Live Fan Gauge (Progress bar, RPM, % readout, status text)
        gaugeMenuItem = GaugeMenuItem()
        menu.addItem(gaugeMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Actions: Edit Profiles..., Settings..., Quit
        let editProfilesItem = NSMenuItem(title: "Edit Profiles...", action: #selector(openEditProfiles), keyEquivalent: "")
        editProfilesItem.target = self
        menu.addItem(editProfilesItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    public func updateMenuState() {
        guard let menu = menu else { return }

        for item in menu.items {
            if let profile = item.representedObject as? FanProfile {
                item.state = (FanManager.shared.activeProfile.id == profile.id) ? .on : .off
            }
            if item.title == "Activate for/until", let submenu = item.submenu {
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
        let alert = NSAlert()
        alert.messageText = "Set Custom Fan Speed"
        alert.informativeText = "Enter target RPM (Mac mini M5 Pro range: 1000 - 4900 RPM):"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Apply")
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
```

---
## Plik: `Sources/Breeze/UI/SettingsWindowController.swift`
```swift
import AppKit
import SwiftUI

public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var viewModel = SettingsViewModel()

    public func show(tab: SettingsTab = .profiles) {
        viewModel.selectedTab = tab

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.center()
        newWindow.title = "Breeze Settings"
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
```

---
## Plik: `Sources/Breeze/UI/Views/ProfileEditorView.swift`
```swift
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
```

---
## Plik: `Sources/Breeze/UI/Views/SettingsView.swift`
```swift
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
```

---
## Plik: `Sources/Breeze/main.swift`
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

---
## Plik: `Sources/Helper/main.swift`
```swift
import Foundation
import IOKit

// SMC Structures for standalone helper binary
struct SMCKeyData_vers {
    var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0
}
struct SMCKeyData_pLimitData {
    var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
}
struct SMCKeyData_keyInfo {
    var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0
}
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCKeyData_vers()
    var pLimitData = SMCKeyData_pLimitData()
    var keyInfo = SMCKeyData_keyInfo()
    var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0; var data8: UInt8 = 0; var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

func fourCharCode(_ str: String) -> UInt32 {
    var result: UInt32 = 0
    for char in str.utf8 { result = (result << 8) | UInt32(char) }
    return result
}

final class DirectSMCWriter {
    static let shared = DirectSMCWriter()
    private var connection: io_connect_t = 0

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service != 0 {
            IOServiceOpen(service, mach_task_self_, 0, &connection)
            IOObjectRelease(service)
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    private func getKeyInfo(keyStr: String) -> (dataType: UInt32, dataSize: UInt32)? {
        guard connection != 0 else { return nil }
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = 9
        let inSize = MemoryLayout<SMCParamStruct>.stride
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let res = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        if res == KERN_SUCCESS && output.result == 0 {
            return (output.keyInfo.dataType, output.keyInfo.dataSize)
        }
        return nil
    }

    func writeBytes(keyStr: String, bytes: [UInt8]) -> Bool {
        guard connection != 0, let info = getKeyInfo(keyStr: keyStr) else { return false }
        var input = SMCParamStruct()
        var output = SMCParamStruct()
        input.key = fourCharCode(keyStr)
        input.data8 = 6 // SMC_CMD_WRITE_BYTES
        input.keyInfo.dataSize = info.dataSize

        withUnsafeMutableBytes(of: &input.bytes) { rawPtr in
            for i in 0..<min(bytes.count, Int(info.dataSize)) {
                rawPtr[i] = bytes[i]
            }
        }

        let inSize = MemoryLayout<SMCParamStruct>.stride
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let res = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        return res == KERN_SUCCESS && output.result == 0
    }

    func setFanMode(fanIndex: Int, manual: Bool) -> Bool {
        let val: UInt8 = manual ? 1 : 0
        let r1 = writeBytes(keyStr: "F\(fanIndex)md", bytes: [val])
        let r2 = writeBytes(keyStr: "F\(fanIndex)Md", bytes: [val])
        return r1 || r2
    }

    func setFanSpeed(fanIndex: Int, targetRPM: Float) -> Bool {
        _ = setFanMode(fanIndex: fanIndex, manual: true)
        var val = targetRPM
        let bytes = withUnsafeBytes(of: &val) { Array($0) }
        return writeBytes(keyStr: "F\(fanIndex)Tg", bytes: bytes)
    }

    func resetToSystem(fanIndex: Int) -> Bool {
        return setFanMode(fanIndex: fanIndex, manual: false)
    }
}

// Unix Domain Socket Daemon with 30s Safety Watchdog
final class BreezeDaemon {
    private let socketPath = "/var/run/breeze.sock"
    private var lastHeartbeat = Date()
    private var isManualOverrideActive = false

    func start() {
        unlink(socketPath)

        // Setup clean shutdown on SIGINT and SIGTERM
        signal(SIGINT) { _ in
            _ = DirectSMCWriter.shared.resetToSystem(fanIndex: 0)
            exit(0)
        }
        signal(SIGTERM) { _ in
            _ = DirectSMCWriter.shared.resetToSystem(fanIndex: 0)
            exit(0)
        }

        let serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            perror("socket")
            exit(1)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            socketPath.withCString { cstr in
                _ = strcpy(raw.assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(serverFd, saPtr, addrLen)
            }
        }

        guard bindRes == 0 else {
            perror("bind")
            exit(1)
        }

        chmod(socketPath, 0o666)

        guard listen(serverFd, 10) == 0 else {
            perror("listen")
            exit(1)
        }

        print("BreezeHelper daemon running on \(socketPath)")

        // Background safety watchdog timer:
        // If client app crashes or disconnects while in manual mode,
        // automatically restore macOS system thermal governance after 30s
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 5.0)
                guard let self = self else { return }
                if self.isManualOverrideActive && Date().timeIntervalSince(self.lastHeartbeat) > 30.0 {
                    print("[Safety Watchdog] Client timeout (>30s) - restoring System fan control")
                    _ = DirectSMCWriter.shared.resetToSystem(fanIndex: 0)
                    self.isManualOverrideActive = false
                }
            }
        }

        while true {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else { continue }

            var buffer = [UInt8](repeating: 0, count: 1024)
            let bytesRead = read(clientFd, &buffer, 1024)
            if bytesRead > 0 {
                if let commandStr = String(bytes: buffer.prefix(bytesRead), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let parts = commandStr.components(separatedBy: " ")
                    var response = "ERROR\n"

                    if parts.first == "SET_SPEED", parts.count >= 3,
                       let fanIdx = Int(parts[1]), let rpm = Float(parts[2]) {
                        self.lastHeartbeat = Date()
                        self.isManualOverrideActive = true
                        let success = DirectSMCWriter.shared.setFanSpeed(fanIndex: fanIdx, targetRPM: rpm)
                        response = success ? "OK\n" : "FAIL_SMC\n"
                    } else if parts.first == "SET_SYSTEM", parts.count >= 2,
                              let fanIdx = Int(parts[1]) {
                        self.isManualOverrideActive = false
                        let success = DirectSMCWriter.shared.resetToSystem(fanIndex: fanIdx)
                        response = success ? "OK\n" : "FAIL_SMC\n"
                    } else if parts.first == "HEARTBEAT" || parts.first == "PING" {
                        self.lastHeartbeat = Date()
                        response = "PONG\n"
                    }

                    _ = response.withCString { cstr in
                        write(clientFd, cstr, strlen(cstr))
                    }
                }
            }
            close(clientFd)
        }
    }
}

// CLI handler
let args = CommandLine.arguments
if args.count > 1 {
    switch args[1] {
    case "daemon":
        BreezeDaemon().start()
    case "set-speed":
        if args.count >= 4, let fanIdx = Int(args[2]), let rpm = Float(args[3]) {
            let ok = DirectSMCWriter.shared.setFanSpeed(fanIndex: fanIdx, targetRPM: rpm)
            print(ok ? "SUCCESS" : "ERROR")
            exit(ok ? 0 : 1)
        }
    case "set-system":
        if args.count >= 3, let fanIdx = Int(args[2]) {
            let ok = DirectSMCWriter.shared.resetToSystem(fanIndex: fanIdx)
            print(ok ? "SUCCESS" : "ERROR")
            exit(ok ? 0 : 1)
        }
    case "ping":
        print("BreezeHelper OK")
        exit(0)
    default:
        print("Usage: breeze-helper [daemon | set-speed <fan> <rpm> | set-system <fan> | ping]")
    }
} else {
    BreezeDaemon().start()
}
```

---
## Skrypt: `scripts/build.sh`
```bash
#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$ROOT_DIR/Breeze.app"

echo "=== Building Breeze for Apple Silicon (Mac mini M5 Pro) ==="

# 1. Process user icons if needed
if [ ! -f "$ROOT_DIR/AppIcon.icns" ] || [ ! -f "$ROOT_DIR/assets/AppIcon-Light.png" ]; then
    echo "Processing Liquid Glass user icons..."
    swift "$SCRIPT_DIR/process_user_icons.swift"
    iconutil -c icns "$ROOT_DIR/AppIcon.iconset" -o "$ROOT_DIR/AppIcon.icns"
    iconutil -c icns "$ROOT_DIR/AppIcon-Dark.iconset" -o "$ROOT_DIR/assets/AppIcon-Dark.icns"
    iconutil -c icns "$ROOT_DIR/AppIcon-Light.iconset" -o "$ROOT_DIR/assets/AppIcon-Light.icns"
    rm -rf "$ROOT_DIR"/*.iconset
fi

# 2. Compile Privileged Helper
echo "Compiling breeze-helper..."
swiftc -O -framework IOKit -framework Foundation \
    -o "$ROOT_DIR/breeze-helper" \
    "$ROOT_DIR/Sources/Helper/main.swift"

# 3. Compile Main App
echo "Compiling Breeze main application..."
swiftc -O -framework Cocoa -framework SwiftUI -framework IOKit \
    -o "$ROOT_DIR/Breeze" \
    "$ROOT_DIR/Sources/Breeze/SMC/SMCEngine.swift" \
    "$ROOT_DIR/Sources/Breeze/Models/FanProfile.swift" \
    "$ROOT_DIR/Sources/Breeze/Services/HelperClient.swift" \
    "$ROOT_DIR/Sources/Breeze/Services/FanManager.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/GaugeMenuItemView.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/MenuBarController.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/Views/ProfileEditorView.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/Views/SettingsView.swift" \
    "$ROOT_DIR/Sources/Breeze/UI/SettingsWindowController.swift" \
    "$ROOT_DIR/Sources/Breeze/AppDelegate.swift" \
    "$ROOT_DIR/Sources/Breeze/main.swift"

# 4. Create macOS .app Bundle
echo "Assembling Breeze.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Library/LaunchServices"

cp "$ROOT_DIR/Breeze" "$APP_DIR/Contents/MacOS/Breeze"
cp "$ROOT_DIR/breeze-helper" "$APP_DIR/Contents/Library/LaunchServices/breeze-helper"
cp "$ROOT_DIR/breeze-helper" "$APP_DIR/Contents/MacOS/breeze-helper"
cp "$ROOT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/assets/AppIcon-Light.png" "$APP_DIR/Contents/Resources/AppIcon-Light.png"
cp "$ROOT_DIR/assets/AppIcon-Dark.png" "$APP_DIR/Contents/Resources/AppIcon-Dark.png"

# 5. Generate Info.plist
cat << 'PLIST' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Breeze</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.breeze.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Breeze</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "=== Build Complete! Application created at: $APP_DIR ==="
```

---
## Skrypt: `scripts/create-dmg.sh`
```bash
#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DMG_NAME="Breeze-1.0.0.dmg"
DMG_PATH="$ROOT_DIR/$DMG_NAME"
STAGING_DIR="$ROOT_DIR/dmg_staging"

echo "=== Building Distributable DMG: $DMG_NAME ==="

# Ensure app is built
if [ ! -d "$ROOT_DIR/Breeze.app" ]; then
    "$SCRIPT_DIR/build.sh"
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 1. Copy Breeze.app
echo "Copying Breeze.app to staging..."
cp -R "$ROOT_DIR/Breeze.app" "$STAGING_DIR/"

# 2. Create symlink to /Applications
echo "Creating /Applications link..."
ln -s /Applications "$STAGING_DIR/Applications"

# 3. Add one-click helper installer script directly inside DMG
cat << 'EOF' > "$STAGING_DIR/Install Privileged Helper.command"
#!/bin/zsh
echo "=== Installing Breeze Privileged Helper Daemon ==="
echo "This installs com.breeze.helper to enable seamless fan control."
echo ""
sudo mkdir -p /Library/PrivilegedHelperTools
HELPER_SRC="$(dirname "$0")/Breeze.app/Contents/Library/LaunchServices/breeze-helper"
if [ ! -f "$HELPER_SRC" ]; then
    HELPER_SRC="/Applications/Breeze.app/Contents/Library/LaunchServices/breeze-helper"
fi
sudo cp "$HELPER_SRC" /Library/PrivilegedHelperTools/com.breeze.helper
sudo chown root:wheel /Library/PrivilegedHelperTools/com.breeze.helper
sudo chmod 755 /Library/PrivilegedHelperTools/com.breeze.helper

cat << 'PLIST' | sudo tee /Library/LaunchDaemons/com.breeze.helper.plist > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.breeze.helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.breeze.helper</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

sudo chown root:wheel /Library/LaunchDaemons/com.breeze.helper.plist
sudo chmod 644 /Library/LaunchDaemons/com.breeze.helper.plist
sudo launchctl unload /Library/LaunchDaemons/com.breeze.helper.plist 2>/dev/null || true
sudo launchctl load -w /Library/LaunchDaemons/com.breeze.helper.plist

echo ""
echo "✅ Privileged Helper successfully installed! You can now close this window."
EOF
chmod +x "$STAGING_DIR/Install Privileged Helper.command"

# 4. Create DMG image
echo "Creating compressed UDZO disk image with hdiutil..."
rm -f "$DMG_PATH"
hdiutil create -volname "Breeze" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "=== DMG Build Complete: $DMG_PATH ==="
ls -lh "$DMG_PATH"
```

---
## Skrypt: `scripts/export_sources.sh`
```bash
#!/bin/zsh
set -e
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_FILE="$ROOT_DIR/FULL_SOURCE_EXPORT.md"

echo "# Pełny Kod Źródłowy Aplikacji Breeze (Apple Silicon Fan Control)" > "$EXPORT_FILE"
echo "Wygenerowano dla celów audytu i skanowania kodu przez zewnętrznego agenta." >> "$EXPORT_FILE"
echo "" >> "$EXPORT_FILE"

find "$ROOT_DIR/Sources" -type f -name "*.swift" | sort | while read -r file; do
    rel="${file#$ROOT_DIR/}"
    echo "---" >> "$EXPORT_FILE"
    echo "## Plik: \`$rel\`" >> "$EXPORT_FILE"
    echo '```swift' >> "$EXPORT_FILE"
    cat "$file" >> "$EXPORT_FILE"
    echo '```' >> "$EXPORT_FILE"
    echo "" >> "$EXPORT_FILE"
done

for script in "$ROOT_DIR/scripts"/*.sh "$ROOT_DIR/scripts"/*.swift; do
    rel="${script#$ROOT_DIR/}"
    echo "---" >> "$EXPORT_FILE"
    echo "## Skrypt: \`$rel\`" >> "$EXPORT_FILE"
    echo '```bash' >> "$EXPORT_FILE"
    cat "$script" >> "$EXPORT_FILE"
    echo '```' >> "$EXPORT_FILE"
    echo "" >> "$EXPORT_FILE"
done

echo "Plik eksportu gotowy: $EXPORT_FILE"
```

---
## Skrypt: `scripts/install-helper.sh`
```bash
#!/bin/zsh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HELPER_BIN="$ROOT_DIR/breeze-helper"

if [ ! -f "$HELPER_BIN" ]; then
    echo "breeze-helper not found. Compiling first..."
    "$SCRIPT_DIR/build.sh"
fi

echo "=== Installing Breeze Privileged Helper Daemon ==="
echo "This requires administrator privileges to place the helper in /Library/PrivilegedHelperTools."

sudo mkdir -p /Library/PrivilegedHelperTools
sudo cp "$HELPER_BIN" /Library/PrivilegedHelperTools/com.breeze.helper
sudo chown root:wheel /Library/PrivilegedHelperTools/com.breeze.helper
sudo chmod 755 /Library/PrivilegedHelperTools/com.breeze.helper

# Create launchd plist daemon
PLIST_PATH="/Library/LaunchDaemons/com.breeze.helper.plist"
sudo cat << 'EOF' > /tmp/com.breeze.helper.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.breeze.helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/PrivilegedHelperTools/com.breeze.helper</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

sudo mv /tmp/com.breeze.helper.plist "$PLIST_PATH"
sudo chown root:wheel "$PLIST_PATH"
sudo chmod 644 "$PLIST_PATH"

sudo launchctl unload "$PLIST_PATH" 2>/dev/null || true
sudo launchctl load -w "$PLIST_PATH"

echo "=== Helper daemon successfully installed and started! ==="
echo "Socket: /var/run/breeze.sock"
```

---
## Skrypt: `scripts/generate_icon.swift`
```bash
import AppKit
import CoreGraphics

func renderLiquidGlassIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    ctx.saveGState()

    // Dimensions
    let padding = size * 0.08
    let iconRect = CGRect(x: padding, y: padding, width: size - (2 * padding), height: size - (2 * padding))
    let cornerRadius = iconRect.width * 0.2237 // Apple standard squircle ratio

    // 1. Drop shadow for the squircle
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.04), blur: size * 0.08, color: NSColor.black.withAlphaComponent(0.40).cgColor)

    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()

    ctx.restoreGState()
    ctx.saveGState()

    // Clip to squircle
    ctx.addPath(squirclePath)
    ctx.clip()

    // 2. Liquid Glass Deep Cyan/Ice Gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let deepNavy = NSColor(red: 0.04, green: 0.12, blue: 0.28, alpha: 1.0).cgColor
    let vibrantAzure = NSColor(red: 0.0, green: 0.48, blue: 0.95, alpha: 1.0).cgColor
    let iceTurquoise = NSColor(red: 0.10, green: 0.82, blue: 0.92, alpha: 1.0).cgColor
    let gradientColors = [deepNavy, vibrantAzure, iceTurquoise] as CFArray
    let gradientLocations: [CGFloat] = [0.0, 0.65, 1.0]

    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: gradientLocations) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: iconRect.midX, y: iconRect.minY), end: CGPoint(x: iconRect.midX, y: iconRect.maxY), options: [])
    }

    // 3. Frosted Glass Inner Glow & Vignette
    if let radialGrad = CGGradient(colorsSpace: colorSpace, colors: [NSColor.white.withAlphaComponent(0.25).cgColor, NSColor.clear.cgColor] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(radialGrad, startCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY * 0.85), startRadius: 0, endCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY * 0.85), endRadius: iconRect.width * 0.6, options: [])
    }

    // 4. Draw Precision Aerodynamic Glass Fan Propeller
    let center = CGPoint(x: iconRect.midX, y: iconRect.midY)
    let hubRadius = iconRect.width * 0.11
    let bladeLength = iconRect.width * 0.35

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.35).cgColor)

    // Draw 3 curved 3D glass blades
    for i in 0..<3 {
        let baseAngle = CGFloat(i) * (2.0 * CGFloat.pi / 3.0) + (CGFloat.pi / 6.0)
        let bladePath = CGMutablePath()

        let startP = CGPoint(
            x: center.x + hubRadius * cos(baseAngle - 0.2),
            y: center.y + hubRadius * sin(baseAngle - 0.2)
        )
        let tipP = CGPoint(
            x: center.x + bladeLength * cos(baseAngle + 0.55),
            y: center.y + bladeLength * sin(baseAngle + 0.55)
        )
        let ctrlP1 = CGPoint(
            x: center.x + (bladeLength * 0.65) * cos(baseAngle + 0.15),
            y: center.y + (bladeLength * 0.65) * sin(baseAngle + 0.15)
        )
        let endTipP = CGPoint(
            x: center.x + bladeLength * cos(baseAngle + 0.80),
            y: center.y + bladeLength * sin(baseAngle + 0.80)
        )
        let endP = CGPoint(
            x: center.x + hubRadius * cos(baseAngle + 0.35),
            y: center.y + hubRadius * sin(baseAngle + 0.35)
        )
        let ctrlP2 = CGPoint(
            x: center.x + (bladeLength * 0.55) * cos(baseAngle + 0.95),
            y: center.y + (bladeLength * 0.55) * sin(baseAngle + 0.95)
        )

        bladePath.move(to: startP)
        bladePath.addQuadCurve(to: tipP, control: ctrlP1)
        bladePath.addLine(to: endTipP)
        bladePath.addQuadCurve(to: endP, control: ctrlP2)
        bladePath.closeSubpath()

        // Fill blade with translucent frosted glass gradient
        ctx.saveGState()
        ctx.addPath(bladePath)
        ctx.clip()

        let bladeGradColors = [
            NSColor.white.withAlphaComponent(0.95).cgColor,
            NSColor(red: 0.80, green: 0.95, blue: 1.0, alpha: 0.65).cgColor,
            NSColor(red: 0.50, green: 0.85, blue: 1.0, alpha: 0.40).cgColor
        ] as CFArray
        if let bladeGrad = CGGradient(colorsSpace: colorSpace, colors: bladeGradColors, locations: [0.0, 0.5, 1.0]) {
            ctx.drawLinearGradient(bladeGrad, start: startP, end: endTipP, options: [])
        }
        ctx.restoreGState()

        // Blade Bevel Outline
        ctx.addPath(bladePath)
        ctx.setLineWidth(size * 0.007)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.strokePath()
    }

    // 5. Central Hub with glossy metal/glass jewel ring
    let hubPath = CGMutablePath()
    hubPath.addArc(center: center, radius: hubRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)

    ctx.saveGState()
    ctx.addPath(hubPath)
    ctx.clip()
    let hubColors = [
        NSColor.white.withAlphaComponent(0.98).cgColor,
        NSColor(red: 0.82, green: 0.94, blue: 1.0, alpha: 0.85).cgColor,
        NSColor(red: 0.30, green: 0.65, blue: 0.95, alpha: 0.90).cgColor
    ] as CFArray
    if let hubGrad = CGGradient(colorsSpace: colorSpace, colors: hubColors, locations: [0.0, 0.4, 1.0]) {
        ctx.drawLinearGradient(hubGrad, start: CGPoint(x: center.x - hubRadius, y: center.y + hubRadius), end: CGPoint(x: center.x + hubRadius, y: center.y - hubRadius), options: [])
    }
    ctx.restoreGState()

    // Hub Bevel Rim
    ctx.addPath(hubPath)
    ctx.setLineWidth(size * 0.008)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    ctx.strokePath()

    // Inner Hub Dot
    let innerDotPath = CGMutablePath()
    innerDotPath.addArc(center: center, radius: hubRadius * 0.4, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.setFillColor(NSColor(red: 0.02, green: 0.25, blue: 0.55, alpha: 0.85).cgColor)
    ctx.addPath(innerDotPath)
    ctx.fillPath()

    ctx.restoreGState() // Restore shadow

    // 6. Liquid Glass Top Specular Glare (Apple Glass Reflection)
    let glarePath = CGMutablePath()
    let glareRect = CGRect(x: iconRect.minX, y: iconRect.midY - (iconRect.height * 0.1), width: iconRect.width, height: iconRect.height * 0.6)
    glarePath.addEllipse(in: glareRect)

    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    if let glareGrad = CGGradient(colorsSpace: colorSpace, colors: [NSColor.white.withAlphaComponent(0.35).cgColor, NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(glareGrad, start: CGPoint(x: iconRect.midX, y: iconRect.maxY), end: CGPoint(x: iconRect.midX, y: iconRect.midY), options: [])
    }
    ctx.restoreGState()

    // 7. Outer Glass Rim Stroke
    ctx.addPath(squirclePath)
    ctx.setLineWidth(size * 0.012)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.45).cgColor)
    ctx.strokePath()

    ctx.restoreGState()

    img.unlockFocus()
    return img
}

// Generate the complete iconset
let fm = FileManager.default
let iconsetPath = "/Users/dominik/.gemini/antigravity/scratch/Breeze/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, size) in iconSizes {
    let img = renderLiquidGlassIcon(size: size)
    if let tiff = img.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: "\(iconsetPath)/\(filename)")
        try! png.write(to: url)
    }
}
print("Generated all icon sizes in \(iconsetPath)")
```

---
## Skrypt: `scripts/process_user_icons.swift`
```bash
import AppKit
import CoreGraphics

let inputPath = "/Users/dominik/.gemini/antigravity/brain/279c540e-fa02-4786-ba13-c3af16ead743/.user_uploaded/media_1794164265924_01a1d535.jpg"
guard let sourceImage = NSImage(contentsOfFile: inputPath),
      let tiffData = sourceImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let cgImage = bitmap.cgImage else {
    print("Failed to load source image")
    exit(1)
}

func cropAndClean(centerX: CGFloat, centerY: CGFloat, size: CGFloat, isDark: Bool) -> CGImage {
    let cropRect = CGRect(x: centerX - size/2, y: centerY - size/2, width: size, height: size)
    let croppedCg = cgImage.cropping(to: cropRect)!
    
    let w = croppedCg.width
    let h = croppedCg.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
        return croppedCg
    }
    
    ctx.draw(croppedCg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let pixelBuffer = ctx.data else { return croppedCg }
    let ptr = pixelBuffer.bindMemory(to: UInt8.self, capacity: w * h * 4)
    
    let center = CGPoint(x: CGFloat(w)/2.0, y: CGFloat(h)/2.0)
    let squircleR: CGFloat = size * 0.415
    
    for y in 0..<h {
        for x in 0..<w {
            let offset = (y * w + x) * 4
            let r = Float(ptr[offset]) / 255.0
            let g = Float(ptr[offset + 1]) / 255.0
            let b = Float(ptr[offset + 2]) / 255.0
            
            let dx = abs(CGFloat(x) - center.x)
            let dy = abs(CGFloat(y) - center.y)
            let dist = max(dx, dy)
            
            // Only process outside / shadow boundary
            if dist > squircleR - 18 {
                let minC = min(r, min(g, b))
                if minC > 0.985 {
                    // Pure white background -> transparent
                    ptr[offset + 3] = 0
                    ptr[offset] = 0
                    ptr[offset + 1] = 0
                    ptr[offset + 2] = 0
                } else if minC > 0.85 {
                    // Outer shadow feathering
                    let alpha = max(0.0, min(1.0, (1.0 - minC) * 3.2))
                    let newA = UInt8(alpha * 255.0)
                    ptr[offset + 3] = newA
                    if isDark {
                        ptr[offset] = UInt8(Float(ptr[offset]) * 0.12 * alpha)
                        ptr[offset + 1] = UInt8(Float(ptr[offset + 1]) * 0.18 * alpha)
                        ptr[offset + 2] = UInt8(Float(ptr[offset + 2]) * 0.35 * alpha)
                    } else {
                        ptr[offset] = UInt8(Float(ptr[offset]) * 0.20 * alpha)
                        ptr[offset + 1] = UInt8(Float(ptr[offset + 1]) * 0.25 * alpha)
                        ptr[offset + 2] = UInt8(Float(ptr[offset + 2]) * 0.40 * alpha)
                    }
                }
            }
        }
    }
    
    return ctx.makeImage() ?? croppedCg
}

func renderCanvas(cgImage: CGImage, targetSize: CGFloat) -> NSImage {
    let outImg = NSImage(size: NSSize(width: targetSize, height: targetSize))
    outImg.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        outImg.unlockFocus()
        return outImg
    }
    ctx.interpolationQuality = .high
    
    // Scale squircle to occupy ~82% of macOS app icon canvas (Apple standard icon grid)
    let iconSize = targetSize * 0.84
    let origin = (targetSize - iconSize) / 2.0
    let targetRect = CGRect(x: origin, y: origin, width: iconSize, height: iconSize)
    
    ctx.draw(cgImage, in: targetRect)
    outImg.unlockFocus()
    return outImg
}

let lightCg = cropAndClean(centerX: 280.5, centerY: 265, size: 480, isDark: false)
let darkCg = cropAndClean(centerX: 751.0, centerY: 265, size: 480, isDark: true)

let rootDir = "/Users/dominik/.gemini/antigravity/scratch/Breeze"
let assetsDir = "\(rootDir)/assets"
try? FileManager.default.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

// Save high-resolution PNGs
let light1024 = renderCanvas(cgImage: lightCg, targetSize: 1024)
let dark1024 = renderCanvas(cgImage: darkCg, targetSize: 1024)

func savePNG(image: NSImage, path: String) {
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

savePNG(image: light1024, path: "\(assetsDir)/AppIcon-Light.png")
savePNG(image: dark1024, path: "\(assetsDir)/AppIcon-Dark.png")
savePNG(image: dark1024, path: "\(rootDir)/AppIcon_preview.png")

// Create iconset for icns generation
func generateIconset(image: NSImage, iconsetName: String) {
    let fm = FileManager.default
    let iconsetPath = "\(rootDir)/\(iconsetName).iconset"
    try? fm.removeItem(atPath: iconsetPath)
    try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    let sizes: [(String, CGFloat)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for (name, size) in sizes {
        let resized = NSImage(size: NSSize(width: size, height: size))
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        resized.unlockFocus()
        savePNG(image: resized, path: "\(iconsetPath)/\(name)")
    }
}

generateIconset(image: dark1024, iconsetName: "AppIcon-Dark")
generateIconset(image: light1024, iconsetName: "AppIcon-Light")
generateIconset(image: dark1024, iconsetName: "AppIcon")

print("Generated iconsets for Dark, Light, and default AppIcon.")
```

