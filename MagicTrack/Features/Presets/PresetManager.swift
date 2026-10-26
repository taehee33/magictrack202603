import Foundation
import Combine

// MARK: - PresetModel

struct TrackpadPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var emoji: String

    // 내장 트랙패드 설정
    var internalTrackingSpeed: Double
    var internalScrollSpeed: Double
    var internalClickPressure: Int

    // 매직 트랙패드 설정
    var magicTrackingSpeed: Double
    var magicScrollSpeed: Double
    var magicClickPressure: Int
    var magicRotation: TrackpadRotation

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "⚡",
        internalTrackingSpeed: Double = 7,
        internalScrollSpeed: Double = 5,
        internalClickPressure: Int = 1,
        magicTrackingSpeed: Double = 7,
        magicScrollSpeed: Double = 5,
        magicClickPressure: Int = 1,
        magicRotation: TrackpadRotation = .standard
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.internalTrackingSpeed = internalTrackingSpeed
        self.internalScrollSpeed = internalScrollSpeed
        self.internalClickPressure = internalClickPressure
        self.magicTrackingSpeed = magicTrackingSpeed
        self.magicScrollSpeed = magicScrollSpeed
        self.magicClickPressure = magicClickPressure
        self.magicRotation = magicRotation
    }

    // 빌트인 기본 프리셋. 속도는 시스템 설정 칸 번호 (이동 1~10, 스크롤 1~8). "일반" = 이동 7칸·스크롤 5칸·보통
    static let defaultPresets: [TrackpadPreset] = [
        TrackpadPreset(
            name: "일반",
            emoji: "☀️",
            internalTrackingSpeed: 7,
            internalScrollSpeed: 5,
            internalClickPressure: 1,
            magicTrackingSpeed: 7,
            magicScrollSpeed: 5,
            magicClickPressure: 1,
            magicRotation: .standard
        ),
        TrackpadPreset(
            name: "코딩",
            emoji: "💻",
            internalTrackingSpeed: 8,
            internalScrollSpeed: 6,
            internalClickPressure: 1,
            magicTrackingSpeed: 9,
            magicScrollSpeed: 7,
            magicClickPressure: 0,
            magicRotation: .standard
        ),
        TrackpadPreset(
            name: "디자인",
            emoji: "🎨",
            internalTrackingSpeed: 7,
            internalScrollSpeed: 5,
            internalClickPressure: 0,
            magicTrackingSpeed: 6,
            magicScrollSpeed: 5,
            magicClickPressure: 0,
            magicRotation: .standard
        ),
        TrackpadPreset(
            name: "게임",
            emoji: "🎮",
            internalTrackingSpeed: 10,
            internalScrollSpeed: 7,
            internalClickPressure: 2,
            magicTrackingSpeed: 10,
            magicScrollSpeed: 7,
            magicClickPressure: 2,
            magicRotation: .standard
        )
    ]
}

// MARK: - PresetManager

final class PresetManager: ObservableObject {
    static let shared = PresetManager()

    @Published var presets: [TrackpadPreset] = []
    @Published var activePresetID: UUID?

    private let presetsKey = "saved_presets"
    private let activePresetKey = "active_preset_id"

    private init() {
        SpeedScale.migrateStoredValuesIfNeeded(migratePresets: Self.migrateSavedPresetSpeeds)
        loadPresets()
    }

    /// 저장된 프리셋의 속도 값을 한 번 변환 (SpeedScale 마이그레이션에서 호출). convert(값, 스크롤 여부)
    static func migrateSavedPresetSpeeds(_ convert: (Double, Bool) -> Double) {
        let key = "saved_presets"
        guard let data = UserDefaults.standard.data(forKey: key),
              var list = try? JSONDecoder().decode([TrackpadPreset].self, from: data) else { return }
        for i in list.indices {
            list[i].internalTrackingSpeed = convert(list[i].internalTrackingSpeed, false)
            list[i].internalScrollSpeed = convert(list[i].internalScrollSpeed, true)
            list[i].magicTrackingSpeed = convert(list[i].magicTrackingSpeed, false)
            list[i].magicScrollSpeed = convert(list[i].magicScrollSpeed, true)
        }
        if let encoded = try? JSONEncoder().encode(list) { UserDefaults.standard.set(encoded, forKey: key) }
    }

    var activePreset: TrackpadPreset? {
        presets.first { $0.id == activePresetID }
    }

    // MARK: - CRUD

    func addPreset(_ preset: TrackpadPreset) {
        presets.append(preset)
        savePresets()
    }

    func updatePreset(_ preset: TrackpadPreset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
            savePresets()
        }
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        if activePresetID == id { activePresetID = nil }
        savePresets()
    }

    /// 기본 프리셋으로 초기화하고 저장 (설정 화면용)
    func resetToDefaultPresetsAndSave() {
        presets = TrackpadPreset.defaultPresets
        activePresetID = presets.first?.id
        UserDefaults.standard.set(activePresetID?.uuidString, forKey: activePresetKey)
        savePresets()
    }

    // MARK: - 활성 프리셋 적용

    func activatePreset(_ preset: TrackpadPreset) {
        activePresetID = preset.id
        UserDefaults.standard.set(preset.id.uuidString, forKey: activePresetKey)

        let manager = TrackpadManager.shared

        if let internal_ = manager.internalTrackpad {
            internal_.trackingSpeed = preset.internalTrackingSpeed
            internal_.scrollSpeed = preset.internalScrollSpeed
            internal_.clickPressure = preset.internalClickPressure
            manager.applySettings(for: internal_)
        }

        if let magic = manager.magicTrackpad {
            magic.trackingSpeed = preset.magicTrackingSpeed
            magic.scrollSpeed = preset.magicScrollSpeed
            magic.clickPressure = preset.magicClickPressure
            magic.rotation = preset.magicRotation
            manager.applySettings(for: magic)
        }

        manager.reapplyActiveProfile()
        print("✅ 프리셋 적용: \(preset.emoji) \(preset.name)")
    }

    /// 현재 감도 설정을 새 프리셋으로 저장
    func saveCurrentAsPreset(name: String, emoji: String) {
        let manager = TrackpadManager.shared
        let preset = TrackpadPreset(
            name: name,
            emoji: emoji,
            internalTrackingSpeed: manager.internalTrackpad?.trackingSpeed ?? TrackpadDevice.defaultTrackingSpeed(for: .internal),
            internalScrollSpeed: manager.internalTrackpad?.scrollSpeed ?? TrackpadDevice.defaultScrollSpeed(for: .internal),
            internalClickPressure: manager.internalTrackpad?.clickPressure ?? 1,
            magicTrackingSpeed: manager.magicTrackpad?.trackingSpeed ?? TrackpadDevice.defaultTrackingSpeed(for: .magicTrackpad),
            magicScrollSpeed: manager.magicTrackpad?.scrollSpeed ?? TrackpadDevice.defaultScrollSpeed(for: .magicTrackpad),
            magicClickPressure: manager.magicTrackpad?.clickPressure ?? 1,
            magicRotation: manager.magicTrackpad?.rotation ?? .standard
        )
        addPreset(preset)
        activePresetID = preset.id
    }

    // MARK: - 영속화

    private func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    /// 빌트인 프리셋 표시 순서 (일반 = 기본이 먼저). 저장된 목록을 이 순서로 재정렬
    private static let defaultPresetOrder: [String] = ["일반", "코딩", "디자인", "게임"]

    private static func reorderPresets(_ list: [TrackpadPreset]) -> [TrackpadPreset] {
        var ordered: [TrackpadPreset] = []
        for name in defaultPresetOrder {
            if let p = list.first(where: { $0.name == name }) {
                ordered.append(p)
            }
        }
        let appended = list.filter { !defaultPresetOrder.contains($0.name) }
        return ordered + appended
    }

    private func loadPresets() {
        // v1.1.0까지 있던 스케일 변환·'일반' 강제 복원은 사용자 값을 덮어써서 제거. 표시 순서만 정리한다.
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode([TrackpadPreset].self, from: data) {
            presets = Self.reorderPresets(saved)
            if presets != saved { savePresets() }
        } else {
            // 최초 실행: 기본 프리셋 목록만 만든다. 사용자의 현재 macOS 설정은 바꾸지 않는다.
            presets = TrackpadPreset.defaultPresets
            savePresets()
        }

        if let idStr = UserDefaults.standard.string(forKey: activePresetKey),
           let id = UUID(uuidString: idStr),
           presets.contains(where: { $0.id == id }) {
            activePresetID = id
        } else {
            activePresetID = presets.first?.id
            UserDefaults.standard.set(activePresetID?.uuidString, forKey: activePresetKey)
        }
    }
}
