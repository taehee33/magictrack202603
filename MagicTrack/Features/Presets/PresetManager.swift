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
        internalTrackingSpeed: Double = 5.0,
        internalScrollSpeed: Double = 5.0,
        internalClickPressure: Int = 1,
        magicTrackingSpeed: Double = 5.0,
        magicScrollSpeed: Double = 5.0,
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

    // 빌트인 기본 프리셋. "일반" = 기본값(5,5,보통), 첫 구동 시 적용됨
    static let defaultPresets: [TrackpadPreset] = [
        TrackpadPreset(
            name: "일반",
            emoji: "☀️",
            internalTrackingSpeed: 5.0,
            internalScrollSpeed: 5.0,
            internalClickPressure: 1,
            magicTrackingSpeed: 5.0,
            magicScrollSpeed: 5.0,
            magicClickPressure: 1,
            magicRotation: .standard
        ),
        TrackpadPreset(
            name: "코딩",
            emoji: "💻",
            internalTrackingSpeed: 6.5,
            internalScrollSpeed: 6.5,
            internalClickPressure: 1,
            magicTrackingSpeed: 8.5,
            magicScrollSpeed: 10.0,
            magicClickPressure: 0,
            magicRotation: .standard
        ),
        TrackpadPreset(
            name: "디자인",
            emoji: "🎨",
            internalTrackingSpeed: 5.0,
            internalScrollSpeed: 5.0,
            internalClickPressure: 0,
            magicTrackingSpeed: 3.5,
            magicScrollSpeed: 5.0,
            magicClickPressure: 0,
            magicRotation: .standard
        ),
        TrackpadPreset(
            name: "게임",
            emoji: "🎮",
            internalTrackingSpeed: 10.0,
            internalScrollSpeed: 10.0,
            internalClickPressure: 2,
            magicTrackingSpeed: 10.0,
            magicScrollSpeed: 10.0,
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
        loadPresets()
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

    /// 저장된 값이 예전 0~3 스케일이면 0~10으로 변환
    private static func toCurrentSpeedScale(_ value: Double) -> Double {
        if value > 3.0 { return min(max(value, 0), 10) }
        return (value / 3.0 * 10.0).clamped(to: 0...10)
    }

    func activatePreset(_ preset: TrackpadPreset) {
        activePresetID = preset.id
        UserDefaults.standard.set(preset.id.uuidString, forKey: activePresetKey)

        let manager = TrackpadManager.shared

        if let internal_ = manager.internalTrackpad {
            internal_.trackingSpeed = Self.toCurrentSpeedScale(preset.internalTrackingSpeed)
            internal_.scrollSpeed = Self.toCurrentSpeedScale(preset.internalScrollSpeed)
            internal_.clickPressure = preset.internalClickPressure
            manager.applySettings(for: internal_)
        }

        if let magic = manager.magicTrackpad {
            magic.trackingSpeed = Self.toCurrentSpeedScale(preset.magicTrackingSpeed)
            magic.scrollSpeed = Self.toCurrentSpeedScale(preset.magicScrollSpeed)
            magic.clickPressure = preset.magicClickPressure
            magic.rotation = preset.magicRotation
            manager.applySettings(for: magic)
        }

        print("✅ 프리셋 적용: \(preset.emoji) \(preset.name)")
    }

    /// 현재 감도 설정을 새 프리셋으로 저장
    func saveCurrentAsPreset(name: String, emoji: String) {
        let manager = TrackpadManager.shared
        let preset = TrackpadPreset(
            name: name,
            emoji: emoji,
            internalTrackingSpeed: manager.internalTrackpad?.trackingSpeed ?? TrackpadDevice.defaultSpeed,
            internalScrollSpeed: manager.internalTrackpad?.scrollSpeed ?? TrackpadDevice.defaultSpeed,
            internalClickPressure: manager.internalTrackpad?.clickPressure ?? 1,
            magicTrackingSpeed: manager.magicTrackpad?.trackingSpeed ?? TrackpadDevice.defaultSpeed,
            magicScrollSpeed: manager.magicTrackpad?.scrollSpeed ?? TrackpadDevice.defaultSpeed,
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

    /// 저장된 프리셋이 예전 0~3 스케일이면 0~10으로 변환
    private static func migratePresetSpeedsToNewScale(_ list: [TrackpadPreset]) -> [TrackpadPreset] {
        list.map { p in
            let needsMigrate = p.internalTrackingSpeed <= 3.0 || p.internalScrollSpeed <= 3.0
                || p.magicTrackingSpeed <= 3.0 || p.magicScrollSpeed <= 3.0
            guard needsMigrate else { return p }
            return TrackpadPreset(
                id: p.id,
                name: p.name,
                emoji: p.emoji,
                internalTrackingSpeed: (p.internalTrackingSpeed / 3.0 * 10.0).clamped(to: 0...10),
                internalScrollSpeed: (p.internalScrollSpeed / 3.0 * 10.0).clamped(to: 0...10),
                internalClickPressure: p.internalClickPressure,
                magicTrackingSpeed: (p.magicTrackingSpeed / 3.0 * 10.0).clamped(to: 0...10),
                magicScrollSpeed: (p.magicScrollSpeed / 3.0 * 10.0).clamped(to: 0...10),
                magicClickPressure: p.magicClickPressure,
                magicRotation: p.magicRotation
            )
        }
    }

    /// "일반" 프리셋은 항상 기본값(5, 5, 보통)으로 고정. 8.3 등 잘못 저장된 값 수정
    private static func normalizeGeneralPreset(_ list: [TrackpadPreset]) -> [TrackpadPreset] {
        list.map { p in
            guard p.name == "일반" else { return p }
            let def = TrackpadDevice.defaultSpeed
            let defPressure = 1
            if p.internalTrackingSpeed == def && p.internalScrollSpeed == def
                && p.magicTrackingSpeed == def && p.magicScrollSpeed == def
                && p.internalClickPressure == defPressure && p.magicClickPressure == defPressure {
                return p
            }
            return TrackpadPreset(
                id: p.id,
                name: p.name,
                emoji: p.emoji,
                internalTrackingSpeed: def,
                internalScrollSpeed: def,
                internalClickPressure: defPressure,
                magicTrackingSpeed: def,
                magicScrollSpeed: def,
                magicClickPressure: defPressure,
                magicRotation: .standard
            )
        }
    }

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
        var didMigrateOrReorder = false
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode([TrackpadPreset].self, from: data) {
            var list = Self.migratePresetSpeedsToNewScale(saved)
            list = Self.normalizeGeneralPreset(list)
            list = Self.reorderPresets(list)
            presets = list
            didMigrateOrReorder = (list != saved)
            if didMigrateOrReorder { savePresets() }
        } else {
            // 최초 실행: 기본 프리셋 로드
            presets = TrackpadPreset.defaultPresets
            savePresets()
        }

        let hadSavedActiveID = UserDefaults.standard.string(forKey: activePresetKey) != nil
        if let idStr = UserDefaults.standard.string(forKey: activePresetKey),
           let id = UUID(uuidString: idStr),
           presets.contains(where: { $0.id == id }) {
            activePresetID = id
        } else {
            activePresetID = presets.first?.id
            UserDefaults.standard.set(activePresetID?.uuidString, forKey: activePresetKey)
            if !hadSavedActiveID, let preset = activePreset {
                DispatchQueue.main.async { [weak self] in
                    self?.applyPresetToDevices(preset)
                }
            }
        }
        // 스케일 마이그레이션 후 활성 프리셋 다시 적용 → 트랙패드 화면에 5로 표시
        if didMigrateOrReorder, let preset = activePreset {
            DispatchQueue.main.async { [weak self] in
                self?.activatePreset(preset)
            }
        }
    }

    /// 디바이스에만 적용 (활성 ID 저장 없이). 최초 구동 시 사용
    private func applyPresetToDevices(_ preset: TrackpadPreset) {
        let manager = TrackpadManager.shared
        if let internal_ = manager.internalTrackpad {
            internal_.trackingSpeed = Self.toCurrentSpeedScale(preset.internalTrackingSpeed)
            internal_.scrollSpeed = Self.toCurrentSpeedScale(preset.internalScrollSpeed)
            internal_.clickPressure = preset.internalClickPressure
            manager.applySettings(for: internal_)
        }
        if let magic = manager.magicTrackpad {
            magic.trackingSpeed = Self.toCurrentSpeedScale(preset.magicTrackingSpeed)
            magic.scrollSpeed = Self.toCurrentSpeedScale(preset.magicScrollSpeed)
            magic.clickPressure = preset.magicClickPressure
            magic.rotation = preset.magicRotation
            manager.applySettings(for: magic)
        }
        print("✅ 최초 구동: 기본 프리셋 적용")
    }
}
