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
        internalTrackingSpeed: Double = 4,
        internalScrollSpeed: Double = 4,
        internalClickPressure: Int = 1,
        magicTrackingSpeed: Double = 4,
        magicScrollSpeed: Double = 4,
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

    /// 화면에 보일 이름. 기본 프리셋 이름은 저장값(한국어)을 그대로 두고 언어에 맞게 보여준다
    /// (이름으로 순서·초기화 연결을 맞추므로 저장값은 바꾸지 않는다)
    var displayName: String {
        switch name {
        case "일반": return String(localized: "일반", comment: "기본 프리셋 이름")
        case "코딩": return String(localized: "코딩", comment: "기본 프리셋 이름")
        case "디자인": return String(localized: "디자인", comment: "기본 프리셋 이름")
        case "게임": return String(localized: "게임", comment: "기본 프리셋 이름")
        default: return name
        }
    }

    /// 장치별 이동·스크롤·클릭 압력 값
    func values(for type: TrackpadType) -> TrackpadDefaults {
        switch type {
        case .internal:
            return TrackpadDefaults(trackingSpeed: internalTrackingSpeed, scrollSpeed: internalScrollSpeed, clickPressure: internalClickPressure)
        case .magicTrackpad:
            return TrackpadDefaults(trackingSpeed: magicTrackingSpeed, scrollSpeed: magicScrollSpeed, clickPressure: magicClickPressure)
        }
    }

    mutating func setValues(_ values: TrackpadDefaults, for type: TrackpadType) {
        switch type {
        case .internal:
            internalTrackingSpeed = values.trackingSpeed
            internalScrollSpeed = values.scrollSpeed
            internalClickPressure = values.clickPressure
        case .magicTrackpad:
            magicTrackingSpeed = values.trackingSpeed
            magicScrollSpeed = values.scrollSpeed
            magicClickPressure = values.clickPressure
        }
    }

    /// 이 장치의 지금 값이 프리셋과 다른지 ('수정됨' 표시용). 매직은 회전도 비교
    func differs(from device: TrackpadDevice) -> Bool {
        if device.currentValues != values(for: device.type) { return true }
        return device.type == .magicTrackpad && device.rotation != magicRotation
    }

    // 빌트인 기본 프리셋. 속도는 시스템 설정 칸 번호 (이동 1~10, 스크롤 1~8). "일반" = macOS 기본값 (이동 4칸·스크롤 4칸·보통)
    static let defaultPresets: [TrackpadPreset] = [
        TrackpadPreset(
            name: "일반",
            emoji: "☀️",
            internalTrackingSpeed: 4,
            internalScrollSpeed: 4,
            internalClickPressure: 1,
            magicTrackingSpeed: 4,
            magicScrollSpeed: 4,
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

    /// 프리셋 삭제. removingRules면 이 프리셋을 쓰는 앱 규칙도 함께 지운다 (남기면 규칙 목록에 '프리셋 없음'으로 표시)
    func deletePreset(id: UUID, removingRules: Bool = false) {
        presets.removeAll { $0.id == id }
        if activePresetID == id { activePresetID = nil }
        savePresets()
        if removingRules {
            AppSwitcherManager.shared.deleteRules(usingPreset: id)
        }
    }

    /// 복제본을 원본 바로 뒤에 넣는다
    @discardableResult
    func duplicatePreset(id: UUID) -> TrackpadPreset? {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return nil }
        let source = presets[index]
        var copy = TrackpadPreset(name: String(localized: "\(source.displayName) 사본"), emoji: source.emoji, magicRotation: source.magicRotation)
        copy.setValues(source.values(for: .internal), for: .internal)
        copy.setValues(source.values(for: .magicTrackpad), for: .magicTrackpad)
        presets.insert(copy, at: index + 1)
        savePresets()
        return copy
    }

    /// 기본 프리셋으로 초기화하고 저장 (설정 화면용).
    /// 기본 프리셋은 실행할 때마다 ID가 새로 생겨서, 같은 이름의 기본 프리셋을 쓰던 앱 규칙은 새 ID로 이어 준다
    func resetToDefaultPresetsAndSave() {
        let old = presets
        presets = TrackpadPreset.defaultPresets
        var remap: [UUID: UUID] = [:]
        for preset in old {
            if let replacement = presets.first(where: { $0.name == preset.name }) {
                remap[preset.id] = replacement.id
            }
        }
        AppSwitcherManager.shared.remapPresets(remap)
        activePresetID = presets.first?.id
        UserDefaults.standard.set(activePresetID?.uuidString, forKey: activePresetKey)
        savePresets()
    }

    /// 초기화하면 연결이 끊기는 앱 규칙 수 (직접 만든 프리셋을 쓰는 규칙)
    func rulesLostOnReset() -> Int {
        let defaultNames = Set(TrackpadPreset.defaultPresets.map(\.name))
        let customIDs = Set(presets.filter { !defaultNames.contains($0.name) }.map(\.id))
        return AppSwitcherManager.shared.rules.filter { customIDs.contains($0.presetID) }.count
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

    /// 지금 감도 설정으로 채운 새 프리셋 (아직 저장하지 않음)
    func presetFromCurrentSettings(name: String = "", emoji: String = "⚡") -> TrackpadPreset {
        let manager = TrackpadManager.shared
        var preset = TrackpadPreset(name: name, emoji: emoji)
        for type in [TrackpadType.internal, .magicTrackpad] {
            let device = type == .internal ? manager.internalTrackpad : manager.magicTrackpad
            preset.setValues(device?.currentValues ?? TrackpadDefaults.mine(for: type), for: type)
        }
        preset.magicRotation = manager.magicTrackpad?.rotation ?? .standard
        return preset
    }

    /// 편집 시트에서 저장. 새 프리셋이 지금 값과 같으면 활성으로 표시하고, 쓰고 있는 프리셋을 고쳤으면 바로 다시 적용한다
    func save(_ preset: TrackpadPreset) {
        if presets.contains(where: { $0.id == preset.id }) {
            updatePreset(preset)
            if activePresetID == preset.id { activatePreset(preset) }
        } else {
            addPreset(preset)
            let manager = TrackpadManager.shared
            let devices = [manager.internalTrackpad, manager.magicTrackpad].compactMap { $0 }
            if !devices.contains(where: { preset.differs(from: $0) }) {
                activePresetID = preset.id
                UserDefaults.standard.set(preset.id.uuidString, forKey: activePresetKey)
            }
        }
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
