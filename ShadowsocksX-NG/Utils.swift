//
//  Utils.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/7.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Foundation
import UserNotifications
import CryptoKit


/// Post a user notification using the modern UserNotifications framework.
/// Replaces the deprecated/removed NSUserNotification API (gone since macOS 11+).
func postUserNotification(title: String, subtitle: String = "", body: String = "", sound: Bool = false) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        if !body.isEmpty { content.body = body }
        if sound { content.sound = .default }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}


extension String {
    var localized: String {
        return NSLocalizedString(self, tableName: nil, bundle: Bundle.main, value: "", comment: "")
    }
}


extension Data {
    func sha1() -> String {
        let digest = Insecure.SHA1.hash(data: self)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

func splitProfile(url: String, max: Int) -> [String] {
    let ssrregexp = "ssr://([A-Za-z0-9_-]+)"
    let ssregexp = "ss://([A-Za-z0-9_-]+"

    
    if url.hasPrefix("ss://"){
        return splitor(url: url, regexp: ssregexp)
    }else if url.hasPrefix("ssr://"){
        return splitor(url: url, regexp: ssrregexp)
    }
    return [""]
}

func splitor(url: String, regexp: String) -> [String] {
    var ret: [String] = []
    var ssrUrl = url
    while ssrUrl.range(of:regexp, options: .regularExpression) != nil {
        if let range = ssrUrl.range(of:regexp, options: .regularExpression) {
            let result = String(ssrUrl[range])
            ssrUrl.replaceSubrange(range, with: "")
            ret.append(result)
        }
    }
    return ret
}

func getLocalInfo() -> [String: Any] {
    let InfoDict = Bundle.main.infoDictionary
    return InfoDict!
}
