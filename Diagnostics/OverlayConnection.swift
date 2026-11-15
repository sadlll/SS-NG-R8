import Foundation
import Darwin

struct OverlayConnection {
    let kind: ConnectionKind
    let source: String

    static func tailscale(_ peer: [String: Any]) -> OverlayConnection {
        let unknown = OverlayConnection(kind: .unknown, source: "Tailscale")
        guard peer["Online"] as? Bool == true else { return unknown }
        if let relay = peer["PeerRelay"] as? String, !relay.isEmpty {
            return OverlayConnection(kind: .relay, source: "Tailscale Peer Relay")
        }
        if let relay = peer["PeerRelay"] as? [String: Any], !relay.isEmpty {
            return OverlayConnection(kind: .relay, source: "Tailscale Peer Relay")
        }
        if let endpoint = peer["CurAddr"] as? String, !endpoint.isEmpty {
            return OverlayConnection(kind: .direct, source: "Tailscale")
        }
        if peer["Active"] as? Bool == true, let relay = peer["Relay"] as? String, !relay.isEmpty {
            return OverlayConnection(kind: .relay, source: "Tailscale DERP (\(relay))")
        }
        return unknown
    }

    static func zeroTier(_ peer: [String: Any], reachable: Bool) -> OverlayConnection {
        guard peer["role"] as? String == "LEAF" else { return OverlayConnection(kind: .unknown, source: "ZeroTier") }
        let paths = peer["paths"] as? [[String: Any]] ?? []
        if paths.contains(where: { $0["active"] as? Bool == true && $0["expired"] as? Bool == false
            && !($0["address"] as? String ?? "").isEmpty }) {
            return OverlayConnection(kind: .direct, source: "ZeroTier")
        }
        // No path alone also describes an offline node; a successful request establishes reachability.
        return OverlayConnection(kind: reachable ? .relay : .unknown, source: "ZeroTier")
    }

    /// Inverse of ZeroTierOne node/MAC.hpp::fromAddress (not valid for bridged neighbors).
    static func zeroTierAddress(mac: String, networkID: String) -> String? {
        let parts = mac.split(separator: ":", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt64($0, radix: 16) }
        guard parts.count == 6, octets.count == 6, octets.allSatisfy({ $0 <= 255 }), networkID.count == 16,
              let network = UInt64(networkID, radix: 16) else { return nil }
        var first = (network & 0xfe) | 2
        if first == 0x52 { first = 0x32 }
        guard octets[0] == first else { return nil }
        var node: UInt64 = 0
        for index in 1...5 {
            node = (node << 8) | (octets[index] ^ ((network >> (index * 8)) & 0xff))
        }
        return String(format: "%010llx", node)
    }

    static func sameIP(_ lhs: String, _ rhs: String) -> Bool {
        for family in [AF_INET, AF_INET6] {
            var a = [UInt8](repeating: 0, count: 16)
            var b = [UInt8](repeating: 0, count: 16)
            if inet_pton(family, lhs, &a) == 1 && inet_pton(family, rhs, &b) == 1 { return a == b }
        }
        return false
    }

    static func zeroTierPeerID(override: String, mac: String?, networkID: String, peers: [[String: Any]]) -> String? {
        let automatic = mac.flatMap { zeroTierAddress(mac: $0, networkID: networkID) }
        let explicit = override.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !explicit.isEmpty {
            guard explicit.count == 10, UInt64(explicit, radix: 16) != nil,
                  automatic == nil || automatic == explicit,
                  peers.contains(where: { $0["address"] as? String == explicit && $0["role"] as? String == "LEAF" }) else { return nil }
            return explicit
        }
        return automatic
    }
}

final class OverlayInspector {
    private let cancellation: ProbeCancellation

    init(cancellation: ProbeCancellation = ProbeCancellation()) { self.cancellation = cancellation }

    static func tailscaleStatus(executable: String, cancellation: ProbeCancellation = ProbeCancellation(),
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: Any]? {
        // macOS bundles CLI and GUI in one executable. Finder lacks the shell variables used
        // for mode detection; without this override it can return GUI error text with exit 0.
        var cliEnvironment = environment
        cliEnvironment["TAILSCALE_BE_CLI"] = "1"
        let result = BoundedCommand.run(executable, arguments: ["status", "--json"], timeout: 3,
                                       cancellation: cancellation, environment: cliEnvironment)
        guard result.status == 0, !result.timedOut, let data = result.output.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func command(_ path: String, _ arguments: [String]) -> String? {
        let result = BoundedCommand.run(path, arguments: arguments, timeout: 3, cancellation: cancellation)
        return result.status == 0 && !result.timedOut ? result.output : nil
    }

    private func json(_ path: String?, _ arguments: [String]) -> Any? {
        guard let path = path, let output = command(path, arguments), let data = output.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func executable(_ paths: [String]) -> String? {
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func inspect(host: String, reachable: Bool, zeroTierPeerID: String = "") -> OverlayConnection {
        let unknown = OverlayConnection(kind: .unknown, source: "")
        guard !host.isEmpty, !cancellation.isCancelled else { return unknown }
        let addresses: [String]
        if OverlayConnection.sameIP(host, host) {
            addresses = [host]
        } else if let resolved = command("/usr/bin/dscacheutil", ["-q", "host", "-a", "name", host]) {
            addresses = resolved.components(separatedBy: .newlines).compactMap { line in
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                guard fields.count == 2, ["ip_address:", "ipv6_address:"].contains(String(fields[0])),
                      OverlayConnection.sameIP(String(fields[1]), String(fields[1])) else { return nil }
                return String(fields[1])
            }
        } else { return unknown }
        guard !addresses.isEmpty else { return unknown }

        let tailscaleCLI = executable(["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"])
        let status = tailscaleCLI.flatMap { Self.tailscaleStatus(executable: $0, cancellation: cancellation) }
        let peers = status?["BackendState"] as? String == "Running"
            ? ((status?["Peer"] as? [String: [String: Any]])?.values.map { $0 } ?? []) : []
        let zeroTierCLI = executable(["/usr/local/bin/zerotier-cli", "/opt/homebrew/bin/zerotier-cli"])
        let networks = json(zeroTierCLI, ["-j", "listnetworks"]) as? [[String: Any]] ?? []
        var zeroTierPeers: [[String: Any]]?
        var observations: [OverlayConnection] = []
        for address in addresses {
            if let peer = peers.first(where: { peer in
                (peer["TailscaleIPs"] as? [String] ?? []).contains { OverlayConnection.sameIP(address, $0) }
            }) {
                observations.append(OverlayConnection.tailscale(peer))
                continue
            }
            guard let route = command("/sbin/route", ["-n", "get", address]),
                  let line = route.components(separatedBy: .newlines).first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("interface:") }),
                  let interface = line.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) else {
                observations.append(unknown); continue
            }
            if let network = networks.first(where: { $0["portDeviceName"] as? String == interface }) {
                // A routed gateway/bridge is not the target node; do not label its path as the target's.
                guard network["status"] as? String == "OK", !route.contains("gateway:"),
                      let networkID = network["id"] as? String else {
                    observations.append(OverlayConnection(kind: .unknown, source: "ZeroTier")); continue
                }
                if zeroTierPeers == nil { zeroTierPeers = json(zeroTierCLI, ["-j", "peers"]) as? [[String: Any]] ?? [] }
                let neighbor = neighborMAC(address: address, interface: interface)
                if let node = OverlayConnection.zeroTierPeerID(override: zeroTierPeerID, mac: neighbor,
                                                               networkID: networkID, peers: zeroTierPeers ?? []),
                   let peer = zeroTierPeers?.first(where: { $0["address"] as? String == node }) {
                    let connection = OverlayConnection.zeroTier(peer, reachable: reachable)
                    observations.append(OverlayConnection(kind: connection.kind, source: "ZeroTier (\(node))"))
                } else { observations.append(OverlayConnection(kind: .unknown, source: "ZeroTier")) }
            } else if interface.hasPrefix("utun") || interface.hasPrefix("feth") || interface.hasPrefix("zt") {
                observations.append(unknown)
            } else {
                observations.append(OverlayConnection(kind: reachable ? .direct : .unknown, source: "TCP"))
            }
        }
        // A dual-stack hostname may use either route. Mixed evidence cannot identify the actual path.
        guard let first = observations.first, observations.allSatisfy({ $0.kind == first.kind && $0.source == first.source }) else { return unknown }
        return first
    }

    private func neighborMAC(address: String, interface: String) -> String? {
        let output: String?
        if address.contains(":") { output = command("/usr/sbin/ndp", ["-n", address]) }
        else { output = command("/usr/sbin/arp", ["-n", address]) }
        guard let output = output else { return nil }
        for line in output.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard fields.contains(interface) else { continue }
            if address.contains(":"), fields.count >= 3, fields[1].split(separator: ":").count == 6 { return fields[1] }
            if let at = fields.firstIndex(of: "at"), at + 1 < fields.count,
               fields[at + 1].split(separator: ":").count == 6 { return fields[at + 1] }
        }
        return nil
    }
}
