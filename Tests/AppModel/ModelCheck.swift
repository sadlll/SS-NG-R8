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
        precondition(profile.proxyTestSummary == "正在测试…")
        var success = ProxyTestResult(requestDuration: 123.456, failure: nil)
        success.connection = OverlayConnection(kind: .relay, source: "ZeroTier")
        profile.proxyTestState.complete(result: success, configuration: config, current: config)
        precondition(profile.proxyTestSummary.contains("PING 不可用"), "HTTPS duration must not be displayed as node RTT when ping is missing")
        precondition(profile.proxyTestTooltip?.contains("中继") == true)
        precondition(profile.proxyTestTooltip?.contains(ProxyProbe.target) == true)
        precondition(profile.proxyTestSummary.hasSuffix("RELAY · 可用"))
        success.ping = PingMeasurement(roundTripTime: 61.25, address: "192.0.2.1")
        profile.proxyTestState.complete(result: success, configuration: config, current: config)
        precondition(profile.proxyTestSummary == "61.25 ms · RELAY · 可用")
        precondition(profile.proxyTestTooltip?.contains("123.456 ms") == true)
        precondition(profile.proxyTestTooltip?.contains("192.0.2.1") == true)
        let item = NSMenuItem(title: profile.title() + " - " + profile.proxyTestSummary, action: nil, keyEquivalent: "")
        precondition(item.title.contains("RELAY"))
        var direct = ProxyTestResult(requestDuration: 42, failure: nil)
        direct.ping = PingMeasurement(roundTripTime: 12.5, address: "100.64.0.1")
        direct.connection = OverlayConnection.tailscale(["Online": true, "Active": true, "CurAddr": "203.0.113.7:41641", "Relay": "tok"])
        profile.proxyTestState.complete(result: direct, configuration: config, current: config)
        precondition(profile.proxyTestSummary.hasSuffix(" ms · UDP P2P · 可用"), profile.proxyTestSummary)
        direct.connection.isLAN = true
        profile.proxyTestState.complete(result: direct, configuration: config, current: config)
        precondition(profile.proxyTestSummary.hasSuffix(" ms · UDP LAN · 可用"))
        precondition(profile.proxyTestTooltip?.contains("局域网直连") == true)
        let restored = ServerProfile.fromDictionary(profile.toDictionary())
        precondition(restored.zeroTierPeerID == profile.zeroTierPeerID)
        precondition(restored.toJsonConfig()["ZeroTierPeerID"] == nil)
        precondition(restored.toJsonConfig()["_diagnostic_zerotier_peer"] == nil)
        profile.proxyTestState.begin(configuration: config)
        profile.proxyTestState.complete(result: ProxyTestResult(requestDuration: nil, failure: .request), configuration: config, current: config)
        precondition(profile.proxyTestSummary.hasSuffix("请求失败"))
        profile.proxyTestState.complete(result: ProxyTestResult(requestDuration: nil, failure: .startup), configuration: config, current: config)
        precondition(profile.proxyTestSummary.contains(ProxyTestFailure.startup.title), "Helper startup failures must retain their cause in the menu")
        var timeout = ProxyTestResult(requestDuration: nil, failure: .timeout)
        timeout.failureDetail = "curl exit 28: SSL connection timeout"
        profile.proxyTestState.complete(result: timeout, configuration: config, current: config)
        precondition(profile.proxyTestSummary.hasSuffix("请求超时"))
        precondition(profile.proxyTestTooltip?.contains("SSL connection timeout") == true)
        timeout.ping = PingMeasurement(roundTripTime: 25, address: "192.0.2.1")
        profile.proxyTestState.complete(result: timeout, configuration: config, current: config)
        precondition(profile.proxyTestSummary == "25 ms · UNKNOWN · 请求超时")
        profile.password = "edited-test-only"
        precondition(profile.currentProxyTestResult == nil)
        precondition(profile.proxyTestSummary.isEmpty)
        print("App model check passed: localized menu text, per-profile results, invalidation and ZeroTier persistence")
    }
}
