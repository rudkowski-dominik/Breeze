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
