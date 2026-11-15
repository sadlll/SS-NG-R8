import XCTest
@testable import ProxyDiagnostics

final class DiagnosticsTests: XCTestCase {
    func testNewFailureReplacesCachedSuccessAndAnEditedProfileRejectsOldResults() {
        var state = ProfileProxyTestState()
        let original: [String: Any] = ["server": "example.com", "password": "first"]
        let edited: [String: Any] = ["server": "example.com", "password": "second"]
        state.begin(configuration: original)
        state.complete(result: ProxyTestResult(latency: 100, failure: nil), configuration: original, current: original)
        XCTAssertEqual(state.currentResult(configuration: original)?.latency, 100)
        XCTAssertNil(state.currentResult(configuration: edited))
        state.begin(configuration: original)
        XCTAssertNil(state.currentResult(configuration: original))
        state.complete(result: ProxyTestResult(latency: nil, failure: .request), configuration: original, current: original)
        XCTAssertNil(state.currentResult(configuration: original)?.latency)
        XCTAssertEqual(state.currentResult(configuration: original)?.failure, .request)
        state.begin(configuration: original)
        state.complete(result: ProxyTestResult(latency: 100, failure: nil), configuration: original, current: edited)
        XCTAssertFalse(state.isTesting)
        XCTAssertNil(state.currentResult(configuration: edited))
    }

    func testProxyResponseRequiresSuccessfulCurlAndExact204() {
        XCTAssertEqual(ProxyProbe.latency(from: CommandResult(status: 0, output: "204 0.125", timedOut: false)), 125)
        for result in [CommandResult(status: 0, output: "200 0.1", timedOut: false),
                       CommandResult(status: 0, output: "302 0.1", timedOut: false),
                       CommandResult(status: 28, output: "204 0.1", timedOut: false),
                       CommandResult(status: 0, output: "204 NaN", timedOut: false),
                       CommandResult(status: 0, output: "204 -1", timedOut: false),
                       CommandResult(status: 0, output: "204 0.1", timedOut: true)] {
            XCTAssertNil(ProxyProbe.latency(from: result))
        }
    }

    func testCurlCannotUseEnvironmentBypassOrCurlRC() {
        let args = ProxyProbe.curlArguments(port: 12345)
        XCTAssertEqual(args.first, "--disable")
        XCTAssertEqual(args[args.firstIndex(of: "--proxy")! + 1], "socks5h://127.0.0.1:12345")
        XCTAssertEqual(args[args.firstIndex(of: "--noproxy")! + 1], "")
        XCTAssertEqual(args[args.firstIndex(of: "--max-time")! + 1], "10")
        XCTAssertFalse(args.contains("--insecure"))
        XCTAssertTrue(args.contains("https://www.gstatic.com/generate_204"))
    }

    func testBoundedCommandTimesOutAndReapsChild() throws {
        let start = Date()
        let result = BoundedCommand.run("/bin/sleep", arguments: ["10"], timeout: 0.1)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testBoundedCommandDrainsLargeOutputWithoutPipeDeadlock() {
        let result = BoundedCommand.run("/usr/bin/awk", arguments: ["BEGIN {for(i=0;i<50000;i++) print \"example\"}"], timeout: 3)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.count, 400000)
        XCTAssertFalse(result.timedOut)
    }

    func testMissingExecutableReturnsFailure() {
        XCTAssertNotEqual(BoundedCommand.run("/does/not/exist", arguments: [], timeout: 1).status, 0)
    }

    func testTailscaleHomeDERPDoesNotOverrideDirectEndpoint() {
        let peer: [String: Any] = ["Online": true, "Active": true, "CurAddr": "1.2.3.4:41641", "Relay": "tok"]
        XCTAssertEqual(OverlayConnection.tailscale(peer).kind, .direct)
    }

    func testTailscaleActiveDERPIsRelayButIdleAndOfflineAreUnknown() {
        XCTAssertEqual(OverlayConnection.tailscale(["Online": true, "Active": true, "CurAddr": "", "Relay": "tok"]).kind, .relay)
        XCTAssertEqual(OverlayConnection.tailscale(["Online": true, "Active": false, "CurAddr": "", "Relay": "tok"]).kind, .unknown)
        XCTAssertEqual(OverlayConnection.tailscale(["Online": false, "CurAddr": "1.2.3.4:41641"]).kind, .unknown)
        XCTAssertEqual(OverlayConnection.tailscale([:]).kind, .unknown)
    }

    func testTailscalePeerRelayHasPriorityOverAnEndpoint() {
        XCTAssertEqual(OverlayConnection.tailscale(["Online": true, "Active": true, "CurAddr": "1.2.3.4:1234", "PeerRelay": "relay-node"]).kind, .relay)
    }

    func testZeroTierMACMapsToRealNodeInsteadOfHostname() {
        XCTAssertEqual(OverlayConnection.zeroTierAddress(mac: "ee:cc:88:cc:00:cc", networkID: "0123456789abcdef"), "0123456789")
        XCTAssertEqual(OverlayConnection.zeroTierAddress(mac: "ee:66:66:66:66:66", networkID: "0123456789abcdef"), "abcdef0123")
        XCTAssertNil(OverlayConnection.zeroTierAddress(mac: "00:11:22:33:44:55", networkID: "0123456789abcdef"))
        XCTAssertNil(OverlayConnection.zeroTierAddress(mac: "incomplete", networkID: "invalid"))
        XCTAssertNil(OverlayConnection.zeroTierAddress(mac: "ee:cc:invalid:ee:ee:ee:ee", networkID: "0123456789abcdef"))
    }

    func testRestoringConfiguredOrderKeepsLiveDraftsAndDoesNotRecreateDeletedProfiles() {
        // Rendering after each completed probe must not reload stored profiles over live edits.
        XCTAssertEqual(ProfileOrder.restoredIndices(currentIDs: ["b", "draft", "a"], savedIDs: ["a", "deleted", "b"]), [2, 0, 1])
        XCTAssertEqual(ProfileOrder.restoredIndices(currentIDs: ["draft2", "draft1"], savedIDs: []), [0, 1])
        XCTAssertEqual(ProfileOrder.restoredIndices(currentIDs: ["a"], savedIDs: ["a", "a"]), [0])
    }

    func testExplicitZeroTierAssociationWorksWhenOSRedactsNeighborMAC() {
        let peers: [[String: Any]] = [["address": "0123456789", "role": "LEAF", "paths": []]]
        XCTAssertEqual(OverlayConnection.zeroTierPeerID(override: "0123456789", mac: nil, networkID: "0123456789abcdef", peers: peers), "0123456789")
        XCTAssertNil(OverlayConnection.zeroTierPeerID(override: "bad", mac: nil, networkID: "0123456789abcdef", peers: peers))
        XCTAssertNil(OverlayConnection.zeroTierPeerID(override: "0000000000", mac: nil, networkID: "0123456789abcdef", peers: peers))
        // Conflicting live neighbor evidence invalidates a stale/manual association.
        XCTAssertNil(OverlayConnection.zeroTierPeerID(override: "abcdef0123", mac: "ee:cc:88:cc:00:cc", networkID: "0123456789abcdef", peers: peers))
    }

    func testZeroTierDirectRequiresActiveUnexpiredPath() {
        XCTAssertEqual(OverlayConnection.zeroTier(["role": "LEAF", "paths": [["active": true, "expired": false, "address": "1.2.3.4/9993"]]], reachable: true).kind, .direct)
        XCTAssertEqual(OverlayConnection.zeroTier(["role": "LEAF", "paths": [["active": true, "expired": true]]], reachable: true).kind, .relay)
        XCTAssertEqual(OverlayConnection.zeroTier(["role": "LEAF", "paths": []], reachable: true).kind, .relay)
        XCTAssertEqual(OverlayConnection.zeroTier(["role": "LEAF", "paths": []], reachable: false).kind, .unknown)
        XCTAssertEqual(OverlayConnection.zeroTier(["role": "PLANET", "paths": []], reachable: true).kind, .unknown)
    }

    func testIPv6AddressesAreComparedByBytes() {
        XCTAssertTrue(OverlayConnection.sameIP("fd7a:115c:a1e0::1", "fd7a:115c:a1e0:0:0:0:0:1"))
        XCTAssertFalse(OverlayConnection.sameIP("100.64.1.1", "100.64.1.2"))
    }

    func testMissingHelperFailsWithoutCreatingConfigOrCrashing() {
        let result = ProxyProbe(helperURL: URL(fileURLWithPath: "/missing/ss-local")).test(configuration: ["server": "127.0.0.1"])
        XCTAssertNil(result.latency)
        XCTAssertEqual(result.failure, .helperUnavailable)
    }

    func testHelperReceivesPrivateFullSSRConfigAndStartupFailureCleansIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        let record = directory.appendingPathComponent("received.json")
        let metadata = directory.appendingPathComponent("metadata")
        let script = """
        #!/bin/sh
        /bin/cp "$2" "\(record.path)"
        /usr/bin/stat -f '%Lp' "$2" > "\(metadata.path)"
        /usr/bin/dirname "$2" >> "\(metadata.path)"
        exit 1
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let config: [String: Any] = ["server": "example.com", "server_port": 8989, "password": "test-only",
                                   "protocol": "auth_sha1_v4", "protocol_param": "1:test", "obfs": "http_simple",
                                   "obfs_param": "example.net", "local_address": "0.0.0.0", "local_port": 1086]
        XCTAssertEqual(ProxyProbe(helperURL: helper).test(configuration: config).failure, .startup)
        let received = try JSONSerialization.jsonObject(with: Data(contentsOf: record)) as! [String: Any]
        for key in ["server", "password", "protocol", "protocol_param", "obfs", "obfs_param"] {
            XCTAssertEqual(received[key] as? String, config[key] as? String)
        }
        XCTAssertEqual(received["local_address"] as? String, "127.0.0.1")
        XCTAssertNotEqual(received["local_port"] as? Int, 1086)
        let lines = try String(contentsOf: metadata).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "600")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lines[1]))
    }

    func testCancellationStopsRunningCommandAndRejectsFurtherLaunches() {
        let token = ProbeCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { token.cancel() }
        let start = Date()
        let result = BoundedCommand.run("/bin/sleep", arguments: ["10"], timeout: 12, cancellation: token)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertNotEqual(BoundedCommand.run("/usr/bin/true", arguments: [], timeout: 1, cancellation: token).status, 0)
    }

    func testRealSSLocalRejectsUnusableProxyEvenWithReachableLoopbackServer() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper = root.appendingPathComponent("ShadowsocksX-NG/ss-local")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw XCTSkip("Bundled helper unavailable") }
        let result = ProxyProbe(helperURL: helper).test(configuration: ["server": "127.0.0.1", "server_port": 1,
                                                                       "method": "aes-256-cfb", "password": "test-only",
                                                                       "protocol": "origin", "obfs": "plain"])
        XCTAssertNil(result.latency)
        XCTAssertEqual(result.failure, .request)
    }

    func testAllFailedAndEmptyBatchesStillCompleteOnMainQueue() {
        for count in [0, 3] {
            let done = expectation(description: "batch \(count)")
            let batch = ProxyTestBatch()
            batch.start(configurations: Array(repeating: ["server": "127.0.0.1"], count: count),
                        helperURL: URL(fileURLWithPath: "/missing/ss-local"),
                        inspectPaths: false, update: { _, result in XCTAssertNil(result.latency) },
                        completion: {
                            XCTAssertTrue(Thread.isMainThread)
                            done.fulfill()
                        })
            wait(for: [done], timeout: 3)
        }
    }
}
