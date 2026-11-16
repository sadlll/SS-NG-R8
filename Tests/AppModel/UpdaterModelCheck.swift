import Cocoa
import Sparkle

@main enum UpdaterModelCheck {
    static func main() {
        _ = NSApplication.shared
        let checker = VersionChecker.shared
        let menu = NSMenuItem(title: "Check Updates", action: nil, keyEquivalent: "")
        checker.configure(menuItem: menu)
        precondition(menu.target === checker.updaterController)
        precondition(menu.action == #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        precondition(menu.title == "检查并安装更新…")
        let info = Bundle.main.infoDictionary!
        precondition(info["SUFeedURL"] as? String == "https://github.com/sadlll/SS-NG-R8/releases/latest/download/appcast.xml")
        precondition(Data(base64Encoded: info["SUPublicEDKey"] as! String)?.count == 32)
        precondition(info["SURequireSignedFeed"] as? Bool == true)
        precondition(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        precondition(!checker.updaterController.updater.automaticallyDownloadsUpdates)
        print("Updater model check passed: localized menu, standard install action, pinned feed and key, signed pre-extraction verification")
    }
}
