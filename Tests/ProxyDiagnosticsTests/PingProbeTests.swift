import XCTest
@testable import ProxyDiagnostics

final class PingProbeTests: XCTestCase {
    func testIPv4AndIPv6StatisticsUseAverageNotMinimumOrMaximum() {
        let v4 = "3 packets transmitted, 3 packets received\nround-trip min/avg/max/stddev = 80.100/91.250/110.400/12.300 ms"
        let v6 = "round-trip min/avg/max/std-dev = 0.077/0.108/0.138/0.025 ms"
        XCTAssertEqual(PingProbe.roundTripTime(from: CommandResult(status: 0, output: v4, timedOut: false)), 91.250)
        XCTAssertEqual(PingProbe.roundTripTime(from: CommandResult(status: 0, output: v6, timedOut: false)), 0.108)
    }

    func testMissingRepliesAndInvalidStatisticsNeverProduceLatency() {
        for output in ["3 packets transmitted, 0 packets received, 100.0% packet loss", "", "round-trip min/avg/max/stddev = 1/NaN/3/0 ms", "round-trip min/avg/max/stddev = 1/-2/3/0 ms"] {
            XCTAssertNil(PingProbe.roundTripTime(from: CommandResult(status: 0, output: output, timedOut: false)))
        }
        let text = "round-trip min/avg/max/stddev = 1/2/3/0 ms"
        XCTAssertNil(PingProbe.roundTripTime(from: CommandResult(status: 0, output: text, timedOut: true)))
        XCTAssertNil(PingProbe.roundTripTime(from: CommandResult(status: 1, output: text, timedOut: false)))
    }

    func testSingleEchoWithUndefinedDeviationStillHasAValidRTT() {
        // Darwin can round a single sample's variance below zero and print nan for deviation.
        let text = "round-trip min/avg/max/stddev = 0.032/0.032/0.032/nan ms"
        XCTAssertEqual(PingProbe.roundTripTime(from: CommandResult(status: 0, output: text, timedOut: false)), 0.032)
    }

    func testRealLoopbackEchoWorksForBothAddressFamilies() {
        for address in ["127.0.0.1", "::1"] {
            let result = PingProbe().measure(host: address)
            XCTAssertEqual(result.address, address)
            if result.roundTripTime == nil {
                let executable = address.contains(":") ? "/sbin/ping6" : "/sbin/ping"
                let diagnostic = BoundedCommand.run(executable, arguments: ["-n", "-q", "-c", "1", address], timeout: 2)
                XCTFail("\(address): status=\(diagnostic.status), timeout=\(diagnostic.timedOut), stdout=\(diagnostic.output), stderr=\(diagnostic.errorOutput)")
            }
            XCTAssertGreaterThanOrEqual(result.roundTripTime ?? -1, 0)
        }
    }

    func testInvalidHostsAndCancellationDoNotLaunchPing() {
        for host in ["", "-c", "example.com;touch /tmp/should-not-exist"] {
            XCTAssertNil(PingProbe().measure(host: host).roundTripTime)
        }
        let token = ProbeCancellation(); token.cancel()
        XCTAssertNil(PingProbe(cancellation: token).measure(host: "127.0.0.1").roundTripTime)
    }

    func testSelectionUsesPingAndRequiresIndependentProxySuccess() {
        var quickPing = ProxyTestResult(requestDuration: 2100, failure: nil)
        quickPing.ping = PingMeasurement(roundTripTime: 40, address: "192.0.2.1")
        var quickRequest = ProxyTestResult(requestDuration: 100, failure: nil)
        quickRequest.ping = PingMeasurement(roundTripTime: 90, address: "192.0.2.2")
        XCTAssertLessThan(quickPing.usableLatency!, quickRequest.usableLatency!)
        var failed = ProxyTestResult(requestDuration: nil, failure: .timeout)
        failed.ping = PingMeasurement(roundTripTime: 1, address: "192.0.2.3")
        XCTAssertEqual(failed.networkLatency, 1)
        XCTAssertNil(failed.usableLatency)
        XCTAssertFalse(failed.isProxyAvailable)
        let noICMP = ProxyTestResult(requestDuration: 200, failure: nil)
        XCTAssertTrue(noICMP.isProxyAvailable)
        XCTAssertNil(noICMP.usableLatency)
    }
}
