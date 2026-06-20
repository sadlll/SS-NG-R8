//
//  UserRulesController.swift
//  ShadowsocksX-NG
//
//  Standalone editor for the PAC user custom rules (user-rule.txt).
//  Restores the "编辑 PAC 用户自定规则..." feature from earlier versions.
//

import Cocoa

class UserRulesController: NSWindowController, NSWindowDelegate {

    private var textView: NSTextView!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "User Rules".localized
        window.center()
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let window = self.window, let contentView = window.contentView else { return }
        window.delegate = self

        let buttonHeight: CGFloat = 32
        let margin: CGFloat = 16
        let buttonAreaHeight = buttonHeight + margin * 2

        let scrollView = NSScrollView(frame: NSRect(
            x: margin,
            y: buttonAreaHeight,
            width: contentView.bounds.width - margin * 2,
            height: contentView.bounds.height - buttonAreaHeight - margin))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tv = NSTextView(frame: scrollView.bounds)
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.isRichText = false
        tv.font = NSFont.userFixedPitchFont(ofSize: 12)
        tv.textContainer?.containerSize = NSSize(width: scrollView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        scrollView.documentView = tv
        self.textView = tv

        let okButton = NSButton(title: "OK".localized, target: self, action: #selector(confirmTap(_:)))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.frame = NSRect(x: contentView.bounds.width - margin - 110, y: margin, width: 110, height: buttonHeight)
        okButton.autoresizingMask = [.minXMargin]

        let cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelTap(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: contentView.bounds.width - margin - 110 - 8 - 110, y: margin, width: 110, height: buttonHeight)
        cancelButton.autoresizingMask = [.minXMargin]

        contentView.addSubview(scrollView)
        contentView.addSubview(okButton)
        contentView.addSubview(cancelButton)

        loadUserRule()
    }

    private func loadUserRule() {
        let fileMgr = FileManager.default
        if !fileMgr.fileExists(atPath: PACUserRuleFilePath) {
            if let src = Bundle.main.path(forResource: "user-rule", ofType: "txt") {
                do {
                    try fileMgr.createDirectory(atPath: PACRulesDirPath, withIntermediateDirectories: true, attributes: nil)
                    try fileMgr.copyItem(atPath: src, toPath: PACUserRuleFilePath)
                } catch {}
            }
        }
        let str = try? String(contentsOfFile: PACUserRuleFilePath, encoding: .utf8)
        textView.string = str ?? ""
    }

    @objc func cancelTap(_ sender: NSButton) {
        window?.close()
    }

    @objc func confirmTap(_ sender: NSButton) {
        let str = textView.string
        do {
            try str.data(using: .utf8)?.write(to: URL(fileURLWithPath: PACUserRuleFilePath), options: .atomic)
            if GeneratePACFile() {
                DispatchQueue.main.async {
                    postUserNotification(title: "PAC has been updated by User Rules.".localized)
                    NotificationCenter.default.post(name: NOTIFY_ADV_CONF_CHANGED, object: nil)
                }
            } else {
                postUserNotification(title: "It's failed to update PAC by User Rules.".localized)
            }
        } catch {
            postUserNotification(title: "It's failed to update PAC by User Rules.".localized)
        }
        window?.close()
    }
}
