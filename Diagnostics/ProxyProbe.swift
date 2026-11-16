import Foundation
import Darwin

struct CommandResult {
    let status: Int32
    let output: String
    let timedOut: Bool
    var errorOutput: String = ""
}

final class ProbeCancellation {
    private let lock = NSLock()
    private var cancelled = false
    private var processes: [ObjectIdentifier: Process] = [:]

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func launch(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw ProxyTestFailure.cancelled }
        try process.run()
        processes[ObjectIdentifier(process)] = process
    }

    func finished(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes.removeValue(forKey: ObjectIdentifier(process))
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let children = Array(processes.values)
        lock.unlock()
        for process in children where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

enum BoundedCommand {
    /// File-backed stdout avoids pipe capacity deadlocks with large overlay status responses.
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval,
                    cancellation: ProbeCancellation = ProbeCancellation(),
                    environment: [String: String]? = nil) -> CommandResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ss-probe-command-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let outputURL = directory.appendingPathComponent("stdout")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            let errorURL = directory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let errors = try FileHandle(forWritingTo: errorURL)
            defer { try? errors.close() }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            // Setting nil explicitly clears the child environment on macOS. Leave the
            // property untouched to inherit HOME and the CLI's local authentication context.
            if let environment = environment { task.environment = environment }
            task.standardOutput = output
            task.standardError = errors
            let ended = DispatchSemaphore(value: 0)
            task.terminationHandler = { _ in ended.signal() }
            try cancellation.launch(task)
            defer { cancellation.finished(task) }
            let timedOut = ended.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                _ = ended.wait(timeout: .now() + 2)
            }
            let status = task.isRunning ? -1 : task.terminationStatus
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
            return CommandResult(status: status, output: String(data: data, encoding: .utf8) ?? "", timedOut: timedOut,
                                 errorOutput: String(data: errorData, encoding: .utf8) ?? "")
        } catch {
            return CommandResult(status: -1, output: "", timedOut: false)
        }
    }
}

final class ProxyProbe {
    static let target = "https://www.gstatic.com/generate_204"
    private let helperURL: URL
    private let cancellation: ProbeCancellation

    init(helperURL: URL, cancellation: ProbeCancellation = ProbeCancellation()) {
        self.helperURL = helperURL
        self.cancellation = cancellation
    }

    static func curlArguments(port: UInt16) -> [String] {
        return ["--disable", "--silent", "--show-error", "--noproxy", "",
                "--proxy", "socks5h://127.0.0.1:\(port)",
                // curl's connect timeout includes SOCKS negotiation and the entire TLS handshake.
                // Relay retransmissions can exceed five seconds even when the proxy works.
                "--connect-timeout", "15", "--max-time", "25", "--retry", "0",
                "--output", "/dev/null", "--write-out", "%{http_code} %{time_total}", "--url", target]
    }

    static func latency(from result: CommandResult) -> Double? {
        let fields = result.output.split(whereSeparator: { $0.isWhitespace })
        guard result.status == 0, !result.timedOut, fields.count == 2, fields[0] == "204",
              let seconds = Double(fields[1]), seconds.isFinite, seconds > 0 else { return nil }
        return seconds * 1000
    }

    func test(configuration: [String: Any]) -> ProxyTestResult {
        guard !cancellation.isCancelled else { return ProxyTestResult(latency: nil, failure: .cancelled) }
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            return ProxyTestResult(latency: nil, failure: .helperUnavailable)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ss-proxy-test-" + UUID().uuidString)
        let helper = Process()
        let ended = DispatchSemaphore(value: 0)
        helper.terminationHandler = { _ in ended.signal() }
        var launched = false
        defer {
            if launched {
                if helper.isRunning { kill(helper.processIdentifier, SIGKILL) }
                _ = ended.wait(timeout: .now() + 2)
                cancellation.finished(helper)
            }
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let port = try Self.freeLoopbackPort()
            var config = configuration
            config.removeValue(forKey: "_diagnostic_zerotier_peer")
            config["local_address"] = "127.0.0.1"
            config["local_port"] = Int(port)
            config["timeout"] = 10
            let configURL = directory.appendingPathComponent("config.json")
            let data = try JSONSerialization.data(withJSONObject: config)
            try data.write(to: configURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            helper.executableURL = helperURL
            // Credentials stay in a private file, never in argv or logs. No ACL/direct fallback.
            helper.arguments = ["-c", configURL.path]
            helper.currentDirectoryURL = helperURL.deletingLastPathComponent()
            var environment = ProcessInfo.processInfo.environment
            environment["DYLD_LIBRARY_PATH"] = helperURL.deletingLastPathComponent().path
            helper.environment = environment
            helper.standardOutput = FileHandle.nullDevice
            helper.standardError = FileHandle.nullDevice
            try cancellation.launch(helper)
            launched = true
            let startupDeadline = Date().addingTimeInterval(2)
            var ready = false
            while helper.isRunning && !cancellation.isCancelled && Date() < startupDeadline {
                if Self.canConnect(port: port) { ready = true; break }
                Thread.sleep(forTimeInterval: 0.025)
            }
            guard ready else {
                return ProxyTestResult(latency: nil, failure: cancellation.isCancelled ? .cancelled : .startup)
            }
            var failure = ProxyTestResult(latency: nil, failure: .request)
            for _ in 0..<2 {
                guard !cancellation.isCancelled else { return ProxyTestResult(latency: nil, failure: .cancelled) }
                let response = BoundedCommand.run("/usr/bin/curl", arguments: Self.curlArguments(port: port),
                                                  timeout: 27, cancellation: cancellation)
                if let latency = Self.latency(from: response) {
                    return ProxyTestResult(latency: latency, failure: nil)
                }
                failure = Self.failedRequest(response)
            }
            return cancellation.isCancelled ? ProxyTestResult(latency: nil, failure: .cancelled) : failure
        } catch {
            return ProxyTestResult(latency: nil, failure: cancellation.isCancelled ? .cancelled : .startup)
        }
    }

    static func failedRequest(_ response: CommandResult) -> ProxyTestResult {
        var result = ProxyTestResult(latency: nil, failure: response.timedOut || response.status == 28 ? .timeout : .request)
        // Only curl's controlled HTTPS probe reaches this formatter. Never include helper
        // logs or its configuration, which may contain protocol credentials.
        let error = response.errorOutput.components(separatedBy: .newlines).joined(separator: " ")
        let detail = error.isEmpty ? response.output : error
        result.failureDetail = "curl exit \(response.status): " + String(detail.prefix(240))
        return result
    }

    private static func freeLoopbackPort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProxyTestFailure.startup }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw ProxyTestFailure.startup }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let gotAddress = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
        }
        guard gotAddress == 0 else { throw ProxyTestFailure.startup }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func canConnect(port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
}
