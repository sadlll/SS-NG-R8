import Foundation

struct PingMeasurement {
    let roundTripTime: Double?
    let address: String?
}

/// ICMP RTT to the node, independent of the HTTPS proxy request.
final class PingProbe {
    private let cancellation: ProbeCancellation

    init(cancellation: ProbeCancellation = ProbeCancellation()) { self.cancellation = cancellation }

    static func roundTripTime(from result: CommandResult) -> Double? {
        guard result.status == 0, !result.timedOut,
              let line = result.output.components(separatedBy: .newlines).first(where: { $0.hasPrefix("round-trip ") }),
              let statistics = line.split(separator: "=", maxSplits: 1).last else { return nil }
        let fields = statistics.trimmingCharacters(in: .whitespaces).split(separator: " ").first?
            .split(separator: "/") ?? []
        // Deviation is unused and Darwin can print nan for a single echo's variance.
        let values = fields.prefix(3).compactMap { Double($0) }
        guard fields.count == 4, values.count == 3, values.allSatisfy({ $0.isFinite && $0 >= 0 }),
              values[0] <= values[1], values[1] <= values[2] else { return nil }
        return values[1]
    }

    func measure(host: String) -> PingMeasurement {
        guard !cancellation.isCancelled, let address = resolve(host) else {
            return PingMeasurement(roundTripTime: nil, address: nil)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        let executable = address.contains(":") ? "/sbin/ping6" : "/sbin/ping"
        var samples: [Double] = []
        // Separate single echoes preserve successful samples when other echoes time out.
        // ping6's -W means a different operation on macOS, so use the common outer deadline.
        for _ in 0..<3 {
            guard !cancellation.isCancelled else { return PingMeasurement(roundTripTime: nil, address: address) }
            let result = BoundedCommand.run(executable, arguments: ["-n", "-q", "-c", "1", address],
                                            timeout: 1.5, cancellation: cancellation, environment: environment)
            if let sample = Self.roundTripTime(from: result) { samples.append(sample) }
        }
        return PingMeasurement(roundTripTime: samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count), address: address)
    }

    private func resolve(_ host: String) -> String? {
        if OverlayConnection.sameIP(host, host) { return host }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("-"),
              host.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let result = BoundedCommand.run("/usr/bin/dscacheutil", arguments: ["-q", "host", "-a", "name", host],
                                        timeout: 2, cancellation: cancellation)
        guard result.status == 0, !result.timedOut else { return nil }
        let addresses = result.output.components(separatedBy: .newlines).compactMap { line -> String? in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, ["ip_address:", "ipv6_address:"].contains(String(fields[0])),
                  OverlayConnection.sameIP(String(fields[1]), String(fields[1])) else { return nil }
            return String(fields[1])
        }
        return addresses.first(where: { !$0.contains(":") }) ?? addresses.first
    }
}
