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
