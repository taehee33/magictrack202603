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

    func rules(usingPreset presetID: UUID) -> [AppRule] {
        rules.filter { $0.presetID == presetID }
    }

    func deleteRules(usingPreset presetID: UUID) {
        rules.removeAll { $0.presetID == presetID }
        saveRules()
    }

    /// 규칙이 가리키는 프리셋을 바꾼다 ('프리셋 없음' 규칙 고치기)
    func setPreset(_ presetID: UUID, forRule ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].presetID = presetID
        saveRules()
    }

    /// 프리셋 ID가 바뀐 경우(기본 프리셋 초기화) 규칙을 새 ID로 옮긴다
    func remapPresets(_ remap: [UUID: UUID]) {
        guard !remap.isEmpty else { return }
        for index in rules.indices {
            if let newID = remap[rules[index].presetID] {
                rules[index].presetID = newID
            }
        }
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
