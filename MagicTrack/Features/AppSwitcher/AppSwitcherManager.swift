import Foundation
import AppKit
import Combine

// MARK: - AppRule

struct AppRule: Codable, Identifiable {
    let id: UUID
    var bundleIdentifier: String
    var appName: String
    var appIcon: Data?          // NSImage로 변환
    var presetID: UUID

    init(id: UUID = UUID(), bundleIdentifier: String, appName: String, appIcon: Data? = nil, presetID: UUID) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.appIcon = appIcon
        self.presetID = presetID
    }
}

// MARK: - AppSwitcherManager

final class AppSwitcherManager: ObservableObject {
    static let shared = AppSwitcherManager()

    @Published var rules: [AppRule] = []
    @Published var isEnabled: Bool = true

    private let rulesKey = "app_switcher_rules"
    private let enabledKey = "app_switcher_enabled"
    private var observer: NSObjectProtocol?

    private init() {
        loadRules()
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            // 최초 실행 기본값은 활성화
            isEnabled = true
            UserDefaults.standard.set(true, forKey: enabledKey)
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        }
    }

    // MARK: - 모니터링

    func startMonitoring() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isEnabled else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            self.handleAppActivation(bundleID: bundleID)
        }
        print("🟢 AppSwitcherManager 모니터링 시작")
    }

    func stopMonitoring() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        print("🔴 AppSwitcherManager 모니터링 종료")
    }

    // MARK: - 앱 활성화 처리

    private func handleAppActivation(bundleID: String) {
        guard let rule = rules.first(where: { $0.bundleIdentifier == bundleID }),
              let preset = PresetManager.shared.presets.first(where: { $0.id == rule.presetID }) else {
            return
        }
        PresetManager.shared.activatePreset(preset)
        print("🔄 자동전환: \(rule.appName) → \(preset.emoji) \(preset.name)")
    }

    // MARK: - CRUD

    func addRule(_ rule: AppRule) {
        rules.append(rule)
        saveRules()
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    func toggleEnabled() {
        isEnabled.toggle()
        UserDefaults.standard.set(isEnabled, forKey: enabledKey)
    }

    // MARK: - 영속화

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let saved = try? JSONDecoder().decode([AppRule].self, from: data) {
            rules = saved
        }
    }
}
