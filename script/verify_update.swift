import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CryptoKit

final class UpdateFeed: NSObject, XMLParserDelegate {
    var enclosures: [[String: String]] = []
    var elements: [String] = []
    var build = ""
    var version = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        elements.append(name)
        if name == "enclosure" { enclosures.append(attributes) }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        if elements.last == "sparkle:version" { build += text }
        if elements.last == "sparkle:shortVersionString" { version += text }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { elements.removeLast() }
}

struct VerificationError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func verify() throws {
    guard CommandLine.arguments.count == 5 else { throw VerificationError("usage: verify_update.swift Info.plist appcast.xml update.zip tag") }
    let infoURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let feedURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let archiveURL = URL(fileURLWithPath: CommandLine.arguments[3])
    let tag = CommandLine.arguments[4]
    guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any],
          info["CFBundleIdentifier"] as? String == "com.qiuyuzhou.ShadowsocksX-NG",
          let publicText = info["SUPublicEDKey"] as? String,
          let publicKey = Data(base64Encoded: publicText), publicKey.count == 32,
          info["SURequireSignedFeed"] as? Bool == true,
          info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
          info["SUFeedURL"] as? String == "https://github.com/sadlll/SS-NG-R8/releases/latest/download/appcast.xml",
          info["CFBundleShortVersionString"] as? String == String(tag.dropFirst()), tag.hasPrefix("v") else {
        throw VerificationError("Invalid updater configuration or release version")
    }
    let feed = UpdateFeed()
    let parser = XMLParser(data: try Data(contentsOf: feedURL)); parser.delegate = feed
    guard parser.parse(), feed.enclosures.count == 1,
          let enclosure = feed.enclosures.first,
          enclosure["url"] == "https://github.com/sadlll/SS-NG-R8/releases/download/\(tag)/\(archiveURL.lastPathComponent)",
          feed.build.trimmingCharacters(in: .whitespacesAndNewlines) == info["CFBundleVersion"] as? String,
          feed.version.trimmingCharacters(in: .whitespacesAndNewlines) == info["CFBundleShortVersionString"] as? String,
          let signatureText = enclosure["sparkle:edSignature"], let signature = Data(base64Encoded: signatureText),
          let lengthText = enclosure["length"], let length = Int(lengthText) else {
        throw VerificationError("Invalid update feed, version, URL or signature metadata")
    }
    let archive = try Data(contentsOf: archiveURL)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard archive.count == length, key.isValidSignature(signature, for: archive) else {
        throw VerificationError("Update archive signature or length does not match the pinned public key")
    }
    print("Verified update archive against pinned public key: \(tag) build \(feed.build)")
}

do { try verify() } catch { fputs("Update verification failed: \(error)\n", stderr); exit(1) }
