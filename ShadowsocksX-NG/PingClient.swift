import Foundation

var isTesting = false
var neverSpeedTestBefore = true

final class ConnectTestigManager {
    static let shared = ConnectTestigManager()
    private var batch: ProxyTestBatch?

    func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.start() }
            return
        }
        guard !isTesting else { return }
        let profiles = ServerProfileManager.instance.profiles
        guard !profiles.isEmpty else { return }
        let configurations = profiles.map { $0.proxyTestConfiguration() }
        let ids = profiles.map { $0.uuid }
        for (profile, configuration) in zip(profiles, configurations) {
            profile.proxyTestState.begin(configuration: configuration)
            profile.latency = NSNumber(value: Double.infinity)
        }
        neverSpeedTestBefore = false
        isTesting = true
        UserDefaults.standard.removeObject(forKey: USERDEFAULTS_FASTEST_NODE)
        NotificationCenter.default.post(name: NOTIFY_UPDATE_MAINMENU, object: nil)

        let installed = URL(fileURLWithPath: NSHomeDirectory() + APP_SUPPORT_DIR + "ss-local")
        let helper = FileManager.default.isExecutableFile(atPath: installed.path) ? installed
            : (Bundle.main.url(forResource: "ss-local", withExtension: nil) ?? installed)
        let batch = ProxyTestBatch()
        self.batch = batch
        batch.start(configurations: configurations, helperURL: helper, update: { index, result in
            // Sorting/subscriptions may replace the original profile objects or their array positions.
            if let profile = ServerProfileManager.instance.profiles.first(where: { $0.uuid == ids[index] }) {
                profile.proxyTestState.complete(result: result, configuration: configurations[index], current: profile.proxyTestConfiguration())
                profile.latency = NSNumber(value: profile.currentProxyTestResult?.latency ?? .infinity)
            }
            NotificationCenter.default.post(name: NOTIFY_UPDATE_MAINMENU, object: nil)
        }, completion: {
            isTesting = false
            self.batch = nil
            let valid = ServerProfileManager.instance.profiles.filter { $0.currentProxyTestResult?.latency != nil }
            if let fastest = valid.min(by: { $0.latency.doubleValue < $1.latency.doubleValue }) {
                let time = NumberFormatter.three(fastest.latency)
                UserDefaults.standard.set(time, forKey: USERDEFAULTS_FASTEST_NODE)
                postUserNotification(title: "Proxy test completed".localized + " · \(time) ms", subtitle: fastest.title())
            } else {
                UserDefaults.standard.removeObject(forKey: USERDEFAULTS_FASTEST_NODE)
                postUserNotification(title: "Proxy test completed".localized, subtitle: "No proxy request succeeded".localized)
            }
            NotificationCenter.default.post(name: NOTIFY_UPDATE_MAINMENU, object: nil)
        })
    }

    func cancel() { batch?.cancel() }
}
