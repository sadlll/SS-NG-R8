// Compile with Diagnostics/*.swift. Reads preferences; never writes or switches the active profile.
import Foundation

@main
enum CheckProfiles {
    static func main() throws {
        let preferencesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.qiuyuzhou.ShadowsocksX-NG.plist")
        let data = try Data(contentsOf: preferencesURL)
        let preferences = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
        let profiles = preferences["ServerProfiles"] as? [[String: Any]] ?? []
        var associations: [String: String] = [:]
        for argument in CommandLine.arguments.dropFirst(2) {
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { associations[parts[0]] = parts[1] }
        }
        let configurations: [[String: Any]] = profiles.map { profile in
            var config: [String: Any] = ["server": profile["ServerHost"] ?? "", "server_port": profile["ServerPort"] ?? 0,
                                         "password": profile["Password"] ?? "", "method": profile["Method"] ?? "aes-256-cfb"]
            for (key, option) in [("ssrProtocol", "protocol"), ("ssrProtocolParam", "protocol_param"),
                                  ("ssrObfs", "obfs"), ("ssrObfsParam", "obfs_param")] {
                config[option] = profile[key]
            }
            if config["obfs"] as? String == "tls1.2_ticket_fastauth" { config["obfs"] = "tls1.2_ticket_auth" }
            let host = profile["ServerHost"] as? String ?? ""
            config["_diagnostic_zerotier_peer"] = associations[host] ?? (profile["ZeroTierPeerID"] as? String ?? "")
            return config
        }
        let helper = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ShadowsocksX-NG-R8/ss-local")
        let batch = ProxyTestBatch()
        var completed = false
        var rows: [[String: Any]] = []
        batch.start(configurations: configurations, helperURL: helper, update: { index, result in
            let host = profiles[index]["ServerHost"] as? String ?? ""
            let delay = result.latency.map { String(format: "%.3f ms", $0) } ?? "failed"
            print("\(host): \(delay) · \(result.connection.badge) (\(result.connection.source))")
            rows.append(["host": host, "latency_ms": result.latency as Any? ?? NSNull(),
                         "path": result.connection.kind.rawValue, "badge": result.connection.badge, "source": result.connection.source,
                         "failure": result.failure?.rawValue as Any? ?? NSNull()])
        }, completion: { completed = true })
        let deadline = Date().addingTimeInterval(180)
        while !completed && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        if !completed { batch.cancel(); throw ProxyTestFailure.cancelled }
        if CommandLine.arguments.count > 1 {
            let output = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
    }
}
