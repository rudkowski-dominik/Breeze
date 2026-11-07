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
