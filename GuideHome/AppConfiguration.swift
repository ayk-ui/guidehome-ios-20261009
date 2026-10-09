import Foundation

enum AppConfiguration {
    static let origin = "https://dyzj-ios-tingt02191010.netlify.app"
    static let entryURL = URL(string: origin + "/ios-v3-0-1/mobile/")!
    static let host = "dyzj-ios-tingt02191010.netlify.app"

    static func owns(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        return url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == host
            && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil
    }
}
