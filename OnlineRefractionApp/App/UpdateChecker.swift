import Foundation
import UIKit

struct UpdateInfo {
    let version: String
    let notes: String?
    let appStoreURL: URL
}

enum UpdateChecker {
    /// 检查 App Store 是否有更新。无更新返回 nil。
    static func checkAppStore(
        bundleId: String = Bundle.main.bundleIdentifier ?? "",
        country: String = Locale.current.regionCode ?? "CN"
    ) async throws -> UpdateInfo? {
        guard !bundleId.isEmpty else { return nil }

        // Apple 查版本接口（不需要你的服务器）
        let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)&country=\(country)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        struct LookupResponse: Decodable {
            struct App: Decodable {
                let version: String
                let trackViewUrl: String
                let releaseNotes: String?
            }
            let results: [App]
        }

        let resp = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard let app = resp.results.first,
              let link = URL(string: app.trackViewUrl) else { return nil }

        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        return isNewer(app.version, than: current) ? UpdateInfo(version: app.version, notes: app.releaseNotes, appStoreURL: link) : nil
    }

    /// 1.2.10 这种点号版本的比较
    private static func isNewer(_ online: String, than local: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(online), b = parts(local)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 跳转到 App Store（用 itms-apps 可直接拉起商店 App）
    static func openAppStore(_ url: URL) {
        let s = url.absoluteString.replacingOccurrences(of: "https://", with: "itms-apps://")
        if let u = URL(string: s) { UIApplication.shared.open(u) }
    }
}
