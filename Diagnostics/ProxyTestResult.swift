import Foundation

enum ConnectionKind: String {
    case direct, relay, unknown

    var title: String {
        switch self {
        case .direct: return NSLocalizedString("Direct", comment: "Connection path")
        case .relay: return NSLocalizedString("Relay", comment: "Connection path")
        case .unknown: return NSLocalizedString("Path unknown", comment: "Connection path")
        }
    }
}

enum ProxyTestFailure: String, Error {
    case helperUnavailable = "Proxy helper unavailable"
    case startup = "Proxy helper failed to start"
    case request = "Proxy HTTPS request failed"
    case cancelled = "Proxy test cancelled"

    var title: String { NSLocalizedString(rawValue, comment: "Proxy test failure") }
}

struct ProxyTestResult {
    let latency: Double?
    let failure: ProxyTestFailure?
    var connection = OverlayConnection(kind: .unknown, source: "")
    let testedAt = Date()
}

struct ProfileProxyTestState {
    private(set) var isTesting = false
    private var configuration: NSDictionary?
    private var result: ProxyTestResult?

    mutating func begin(configuration: [String: Any]) {
        isTesting = true
        self.configuration = NSDictionary(dictionary: configuration)
        result = nil
    }

    mutating func complete(result: ProxyTestResult, configuration: [String: Any], current: [String: Any]) {
        isTesting = false
        guard NSDictionary(dictionary: configuration).isEqual(to: current) else {
            self.configuration = nil
            self.result = nil
            return
        }
        self.configuration = NSDictionary(dictionary: configuration)
        self.result = result
    }

    func currentResult(configuration: [String: Any]) -> ProxyTestResult? {
        guard !isTesting, self.configuration?.isEqual(to: configuration) == true else { return nil }
        return result
    }
}

enum ProfileOrder {
    static func restoredIndices(currentIDs: [String], savedIDs: [String]) -> [Int] {
        var ranks: [String: Int] = [:]
        for (index, id) in savedIDs.enumerated() where ranks[id] == nil { ranks[id] = index }
        return currentIDs.indices.sorted {
            let lhs = ranks[currentIDs[$0]] ?? Int.max
            let rhs = ranks[currentIDs[$1]] ?? Int.max
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
    }
}

/// All callbacks are delivered on the main queue, including empty/all-failure runs.
final class ProxyTestBatch {
    private let queue = OperationQueue()
    private let cancellation = ProbeCancellation()

    init() {
        queue.name = "Proxy HTTPS diagnostics"
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
    }

    func start(configurations: [[String: Any]], helperURL: URL, inspectPaths: Bool = true,
               update: @escaping (Int, ProxyTestResult) -> Void, completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for (index, configuration) in configurations.enumerated() {
            group.enter()
            queue.addOperation {
                let probe = ProxyProbe(helperURL: helperURL, cancellation: self.cancellation)
                var result = probe.test(configuration: configuration)
                if inspectPaths && !self.cancellation.isCancelled {
                    result.connection = OverlayInspector(cancellation: self.cancellation).inspect(
                        host: configuration["server"] as? String ?? "", reachable: result.latency != nil,
                        zeroTierPeerID: configuration["_diagnostic_zerotier_peer"] as? String ?? "")
                }
                let completedResult = result
                DispatchQueue.main.async { update(index, completedResult) }
                group.leave()
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    func cancel() {
        cancellation.cancel()
        // Workers never wait for the main queue. Reap helpers and remove private configs before quit.
        queue.waitUntilAllOperationsAreFinished()
    }
}
