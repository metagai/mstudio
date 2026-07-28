import AppKit
import Foundation

/// Opens the user's mail client at contact@metag.ai.
///
/// Deliberately not an in-app form: the gateway has no feedback endpoint, and a form that
/// posts nowhere would fail silently. Handing off to Mail means the user can see whether
/// their message was actually sent.
///
/// The subject carries the app and OS version so we don't have to ask. The body is left
/// empty on purpose — we don't put words in the user's mouth.
@MainActor
enum FeedbackMail {
    static let address = "contact@metag.ai"

    static func open() {
        let subject = "METAG feedback — \(appVersion) · macOS \(osVersion)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
