import Foundation
import Combine

// MARK: - UpdateChecker
// GitHub 최신 릴리스를 하루 한 번 확인해 새 버전이 있으면 알린다.
// 설치는 하지 않고 릴리스 페이지만 열어 준다 (Sparkle 같은 자동 설치 없음)

/// "1.3.0", "v1.10" 같은 버전 문자열을 숫자 단위로 비교한다
enum AppVersion {
    static func components(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        let body = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        // "1.4.0-beta" 같은 꼬리는 버린다
        let core = body.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? body
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let autoCheckKey = "auto_check_updates"
    private static let lastCheckKey = "last_update_check"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    static let releasesPage = URL(string: "https://github.com/taehee33/magictrack202603/releases/latest")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/taehee33/magictrack202603/releases/latest")!

    struct Release: Equatable {
        let version: String
        let page: URL
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    var availableRelease: Release? {
        if case .available(let release) = status { return release }
        return nil
    }

    private var timer: Timer?
    private let defaults = UserDefaults.standard

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private init() {
        defaults.register(defaults: [Self.autoCheckKey: true])
        lastChecked = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    /// 앱 시작 시 호출. 자동 확인이 켜져 있으면 마지막 확인 후 하루가 지났을 때 확인하고, 켜 둔 동안 몇 시간마다 다시 본다
    func start() {
        checkIfDue()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        guard defaults.bool(forKey: Self.autoCheckKey) else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.checkInterval { return }
        check()
    }

    func check() {
        guard status != .checking else { return }
        status = .checking

        var request = URLRequest(url: Self.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MagicMagicTrack/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let release = Self.parseRelease(data: data, response: response)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let release else {
                    self.status = .failed
                    return
                }
                let now = Date()
                self.lastChecked = now
                self.defaults.set(now, forKey: Self.lastCheckKey)
                self.status = AppVersion.isNewer(release.version, than: self.currentVersion)
                    ? .available(release)
                    : .upToDate
            }
        }.resume()
    }

    private static func parseRelease(data: Data?, response: URLResponse?) -> Release? {
        guard let data,
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, page: page)
    }
}
