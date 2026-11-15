import Cocoa

extension String {
    var localized: String { NSLocalizedString(self, comment: "") }
}

@main
enum ModelCheck {
    static func main() {
        UserDefaults.standard.register(defaults: [USERDEFAULTS_LOCAL_SOCKS5_LISTEN_PORT: 1086,
                                                  USERDEFAULTS_LOCAL_SOCKS5_LISTEN_ADDRESS: "127.0.0.1",
                                                  USERDEFAULTS_LOCAL_SOCKS5_TIMEOUT: 60])
        let profile = ServerProfile()
        profile.serverHost = "example.internal"
        profile.password = "test-only"
        profile.zeroTierPeerID = "0123456789"
        precondition(profile.proxyTestSummary.isEmpty)
        let config = profile.proxyTestConfiguration()
        profile.proxyTestState.begin(configuration: config)
        precondition(profile.proxyTestSummary == "正在测试代理…")
        var success = ProxyTestResult(latency: 123.456, failure: nil)
        success.connection = OverlayConnection(kind: .relay, source: "ZeroTier")
        profile.proxyTestState.complete(result: success, configuration: config, current: config)
        precondition(profile.proxyTestSummary.hasSuffix(" ms · RELAY"))
        precondition(profile.proxyTestTooltip?.contains("中继") == true)
        precondition(profile.proxyTestTooltip?.contains(ProxyProbe.target) == true)
        let item = NSMenuItem(title: profile.title() + " - " + profile.proxyTestSummary, action: nil, keyEquivalent: "")
        precondition(item.title.contains("RELAY"))
        var direct = ProxyTestResult(latency: 42, failure: nil)
        direct.connection = OverlayConnection.tailscale(["Online": true, "Active": true, "CurAddr": "203.0.113.7:41641", "Relay": "tok"])
        profile.proxyTestState.complete(result: direct, configuration: config, current: config)
        precondition(profile.proxyTestSummary.hasSuffix(" ms · UDP P2P"), profile.proxyTestSummary)
        direct.connection.isLAN = true
        profile.proxyTestState.complete(result: direct, configuration: config, current: config)
        precondition(profile.proxyTestSummary.hasSuffix(" ms · UDP LAN"))
        precondition(profile.proxyTestTooltip?.contains("局域网直连") == true)
        let restored = ServerProfile.fromDictionary(profile.toDictionary())
        precondition(restored.zeroTierPeerID == profile.zeroTierPeerID)
        precondition(restored.toJsonConfig()["ZeroTierPeerID"] == nil)
        precondition(restored.toJsonConfig()["_diagnostic_zerotier_peer"] == nil)
        profile.proxyTestState.begin(configuration: config)
        profile.proxyTestState.complete(result: ProxyTestResult(latency: nil, failure: .request), configuration: config, current: config)
        precondition(profile.proxyTestSummary.hasPrefix("请求失败"))
        profile.password = "edited-test-only"
        precondition(profile.currentProxyTestResult == nil)
        precondition(profile.proxyTestSummary.isEmpty)
        print("App model check passed: localized menu text, per-profile results, invalidation and ZeroTier persistence")
    }
}
