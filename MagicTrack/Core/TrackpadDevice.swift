import Foundation
import IOKit
import IOKit.hid

// MARK: - TrackpadType

enum TrackpadType: String, Codable {
    case `internal` = "internal"
    case magicTrackpad = "magic_trackpad"

    var displayName: String {
        switch self {
        case .internal: return String(localized: "내장 트랙패드")
        case .magicTrackpad: return String(localized: "매직 트랙패드")
        }
    }

    var systemImageName: String {
        switch self {
        case .internal: return "laptopcomputer"
        case .magicTrackpad: return "rectangle.roundedtop.fill"
        }
    }

    var accentColor: String {
        switch self {
        case .internal: return "AccentBlue"
        case .magicTrackpad: return "AccentPurple"
        }
    }
}

enum TrackpadRotation: String, Codable, CaseIterable {
    case standard = "standard"
    case left90 = "left_90"
    case right90 = "right_90"
    case upsideDown = "upside_down"

    var displayName: String {
        switch self {
        case .standard: return String(localized: "기본")
        case .left90: return String(localized: "왼쪽 90°")
        case .right90: return String(localized: "오른쪽 90°")
        case .upsideDown: return "180°"
        }
    }

    var angle: Double {
        switch self {
        case .standard: return 0
        case .left90: return -90
        case .right90: return 90
        case .upsideDown: return 180
        }
    }
}

// MARK: - TrackpadDevice

final class TrackpadDevice: ObservableObject, Identifiable {
    let id: UUID = UUID()
    let type: TrackpadType
    let hidDevice: IOHIDDevice?
    let productName: String
    let vendorID: Int
    let productID: Int
    let serialNumber: String

    @Published var isConnected: Bool
    @Published var trackingSpeed: Double      // 시스템 설정 '이동 속도' 슬라이더 칸 1 ~ 10
    @Published var scrollSpeed: Double        // 시스템 손쉬운 사용 '스크롤 속도' 슬라이더 칸 1 ~ 8
    @Published var clickPressure: Int         // 0 ~ 2 (Light / Medium / Firm)
    @Published var rotation: TrackpadRotation
    @Published private(set) var myDefaults: TrackpadDefaults

    static let trackingRange: ClosedRange<Double> = 1...Double(SpeedScale.trackingStops.count)
    static let scrollRange: ClosedRange<Double> = 1...Double(SpeedScale.scrollStops.count)
    /// 내 기본값 저장 키. v1.2.0까지 '맥 설정 값'으로 쓰던 키를 그대로 이어 쓴다
    private static let macDefaultPrefix = "mac_default_"

    init(
        hidDevice: IOHIDDevice?,
        type: TrackpadType,
        productName: String,
        vendorID: Int = 0,
        productID: Int = 0,
        serialNumber: String = ""
    ) {
        self.hidDevice = hidDevice
        self.type = type
        self.productName = productName
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.isConnected = (hidDevice != nil)

        // 저장된 값 로드. 키가 없을 때만 기본값을 쓰고, 0도 정상 값으로 취급한다.
        // (v1.1.0까지 있던 0~3 → 0~10 변환은 실행할 때마다 다시 돌아 값을 부풀렸으므로 제거)
        let key = "\(type.rawValue)_"
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key + "trackingSpeed") != nil {
            self.trackingSpeed = defaults.double(forKey: key + "trackingSpeed").rounded().clamped(to: TrackpadDevice.trackingRange)
        } else {
            self.trackingSpeed = TrackpadDevice.defaultTrackingSpeed(for: type)
        }
        if defaults.object(forKey: key + "scrollSpeed") != nil {
            self.scrollSpeed = defaults.double(forKey: key + "scrollSpeed").rounded().clamped(to: TrackpadDevice.scrollRange)
        } else {
            self.scrollSpeed = TrackpadDevice.defaultScrollSpeed(for: type)
        }
        // 클릭 압력: integer(forKey:)는 키 없을 때 0을 반환하므로 존재 여부로 구분
        let clickKey = key + "clickPressure"
        if defaults.object(forKey: clickKey) != nil {
            self.clickPressure = defaults.integer(forKey: clickKey).clamped(to: 0...2)
        } else {
            self.clickPressure = TrackpadDevice.defaultClickPressure(for: type)
        }
        if let storedRotation = defaults.string(forKey: key + "rotation"),
           let rotation = TrackpadRotation(rawValue: storedRotation) {
            self.rotation = rotation
        } else {
            self.rotation = .standard
        }
        self.myDefaults = TrackpadDefaults.mine(for: type)
    }

    func saveSettings() {
        let key = "\(type.rawValue)_"
        UserDefaults.standard.set(trackingSpeed, forKey: key + "trackingSpeed")
        UserDefaults.standard.set(scrollSpeed, forKey: key + "scrollSpeed")
        UserDefaults.standard.set(clickPressure, forKey: key + "clickPressure")
        UserDefaults.standard.set(rotation.rawValue, forKey: key + "rotation")
    }

    // MARK: - 기본값 (되돌리기 메뉴용)
    // 내 기본값: 장치별로 사용자가 저장한 기준값. 처음 실행할 때 그때의 시스템 설정 값으로 채운다
    // Mac 기본값: Apple 출고 기본값 (이동 4칸 · 스크롤 4칸 · 클릭 보통). 고정

    /// 지금 이동·스크롤·클릭 압력 값 (프리셋과 비교할 때 사용)
    var currentValues: TrackpadDefaults {
        TrackpadDefaults(trackingSpeed: trackingSpeed, scrollSpeed: scrollSpeed, clickPressure: clickPressure)
    }

    func saveAsMyDefaults() {
        let defaults = TrackpadDefaults(trackingSpeed: trackingSpeed, scrollSpeed: scrollSpeed, clickPressure: clickPressure)
        defaults.save(for: type)
        myDefaults = defaults
    }

    /// 이동·스크롤·클릭 압력만 바꾼다. 회전은 트랙패드를 놓은 방향이라 그대로 둔다
    func apply(_ defaults: TrackpadDefaults) {
        trackingSpeed = defaults.trackingSpeed
        scrollSpeed = defaults.scrollSpeed
        clickPressure = defaults.clickPressure
    }

    static func defaultTrackingSpeed(for type: TrackpadType) -> Double {
        UserDefaults.standard.object(forKey: macDefaultKey(for: type, suffix: "trackingSpeed")) != nil
            ? UserDefaults.standard.double(forKey: macDefaultKey(for: type, suffix: "trackingSpeed"))
            : SpeedScale.trackingStop(forSystemValue: SensitivityController.shared.getCurrentTrackingSpeed())
    }

    static func defaultScrollSpeed(for type: TrackpadType) -> Double {
        UserDefaults.standard.object(forKey: macDefaultKey(for: type, suffix: "scrollSpeed")) != nil
            ? UserDefaults.standard.double(forKey: macDefaultKey(for: type, suffix: "scrollSpeed"))
            : SpeedScale.scrollStop(forSystemValue: SensitivityController.shared.getCurrentScrollSpeed())
    }

    static func defaultClickPressure(for type: TrackpadType) -> Int {
        UserDefaults.standard.object(forKey: macDefaultKey(for: type, suffix: "clickPressure")) != nil
            ? UserDefaults.standard.integer(forKey: macDefaultKey(for: type, suffix: "clickPressure"))
            : TrackpadDefaults.mac.clickPressure
    }

    static func ensureMacDefaultsCaptured() {
        let controller = SensitivityController.shared

        captureIfNeeded(
            key: macDefaultKey(for: .internal, suffix: "trackingSpeed"),
            value: SpeedScale.trackingStop(forSystemValue: controller.getCurrentTrackingSpeed())
        )
        captureIfNeeded(
            key: macDefaultKey(for: .magicTrackpad, suffix: "trackingSpeed"),
            value: SpeedScale.trackingStop(forSystemValue: controller.getCurrentTrackingSpeed())
        )
        captureIfNeeded(
            key: macDefaultKey(for: .internal, suffix: "scrollSpeed"),
            value: SpeedScale.scrollStop(forSystemValue: controller.getCurrentScrollSpeed())
        )
        captureIfNeeded(
            key: macDefaultKey(for: .magicTrackpad, suffix: "scrollSpeed"),
            value: SpeedScale.scrollStop(forSystemValue: controller.getCurrentScrollSpeed())
        )
        captureIfNeeded(
            key: macDefaultKey(for: .internal, suffix: "clickPressure"),
            value: controller.getCurrentClickPressure()
        )
        captureIfNeeded(
            key: macDefaultKey(for: .magicTrackpad, suffix: "clickPressure"),
            value: controller.getCurrentClickPressure()
        )
    }

    private static func captureIfNeeded(key: String, value: Double) {
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func captureIfNeeded(key: String, value: Int) {
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    static func macDefaultKey(for type: TrackpadType, suffix: String) -> String {
        "\(macDefaultPrefix)\(type.rawValue)_\(suffix)"
    }
}

// MARK: - TrackpadDefaults

struct TrackpadDefaults: Equatable {
    var trackingSpeed: Double
    var scrollSpeed: Double
    var clickPressure: Int

    /// Apple 출고 기본값 (IOHIPointing.h, 시스템 설정 클릭 '보통')
    static let mac = TrackpadDefaults(
        trackingSpeed: SpeedScale.defaultTrackingStop,
        scrollSpeed: SpeedScale.defaultScrollStop,
        clickPressure: 1
    )

    static func mine(for type: TrackpadType) -> TrackpadDefaults {
        TrackpadDefaults(
            trackingSpeed: TrackpadDevice.defaultTrackingSpeed(for: type),
            scrollSpeed: TrackpadDevice.defaultScrollSpeed(for: type),
            clickPressure: TrackpadDevice.defaultClickPressure(for: type)
        )
    }

    func save(for type: TrackpadType) {
        let defaults = UserDefaults.standard
        defaults.set(trackingSpeed, forKey: TrackpadDevice.macDefaultKey(for: type, suffix: "trackingSpeed"))
        defaults.set(scrollSpeed, forKey: TrackpadDevice.macDefaultKey(for: type, suffix: "scrollSpeed"))
        defaults.set(clickPressure, forKey: TrackpadDevice.macDefaultKey(for: type, suffix: "clickPressure"))
    }

    static let clickPressureLabels = [String(localized: "가볍게"), String(localized: "보통"), String(localized: "단단하게")]

    var summary: String {
        String(localized: "이동 \(Int(trackingSpeed))칸 · 스크롤 \(Int(scrollSpeed))칸 · 클릭 \(Self.clickPressureLabels[clickPressure.clamped(to: 0...2)])")
    }
}

// MARK: - SpeedScale
// 시스템 설정과 같은 속도 칸. 값 표는 시스템 설정이 쓰는 PreferencePanesSupport의 표를 그대로 옮김
// (MTTGestureBackEnd sTrackSpeedFactors / sScrollSpeedFactors, macOS 27.0.1에서 읽음)
// macOS 기본값(IOHIDFamily IOHIPointing.h): 이동 EV_DEFAULTPOINTERACCELLEVEL 0xB000 = 0.6875, 스크롤 EV_DEFAULTSCROLLACCELLEVEL 0x5000 = 0.3125
// → 둘 다 4칸

enum SpeedScale {
    /// 시스템 설정 › 트랙패드 › 이동 속도 (10칸) → com.apple.trackpad.scaling
    static let trackingStops: [Double] = [0, 0.125, 0.5, 0.6875, 0.875, 1.0, 1.5, 2.0, 2.5, 3.0]
    /// 시스템 설정 › 손쉬운 사용 › 포인터 제어 › 트랙패드 옵션 › 스크롤 속도 (8칸)
    static let scrollStops: [Double] = [0, 0.125, 0.215, 0.3125, 0.5, 0.75, 1.0, 1.7]
    static let defaultTrackingStop: Double = 4   // 0.6875
    static let defaultScrollStop: Double = 4     // 0.3125

    /// 칸 번호(1부터) → 시스템 값
    static func trackingValue(stop: Double) -> Double { value(stop: stop, in: trackingStops) }
    static func scrollValue(stop: Double) -> Double { value(stop: stop, in: scrollStops) }

    /// 시스템 값 → 가장 가까운 칸 번호(1부터)
    static func trackingStop(forSystemValue v: Double) -> Double { nearestStop(v, in: trackingStops) }
    static func scrollStop(forSystemValue v: Double) -> Double { nearestStop(v, in: scrollStops) }

    private static func value(stop: Double, in stops: [Double]) -> Double {
        stops[(Int(stop.rounded()) - 1).clamped(to: 0...(stops.count - 1))]
    }

    private static func nearestStop(_ v: Double, in stops: [Double]) -> Double {
        let index = stops.indices.min { abs(stops[$0] - v) < abs(stops[$1] - v) } ?? 0
        return Double(index + 1)
    }

    // MARK: 한 번만 하는 변환 (v1.2.0까지의 0~10 균등 단위 → 시스템 칸)

    private static let versionKey = "speed_scale_version"

    /// 기존 0~10 값을 그때의 시스템 값(이동 ×0.3, 스크롤 ÷10)으로 바꾼 뒤 가장 가까운 칸으로 옮긴다
    /// - migratePresets: 저장된 프리셋 변환 함수 (PresetManager.migrateSavedPresetSpeeds). 테스트에서 의존을 끊기 위해 주입
    static func migrateStoredValuesIfNeeded(migratePresets: ((Double, Bool) -> Double) -> Void) {
        let defaults = UserDefaults.standard
        let version = defaults.integer(forKey: versionKey)
        guard version < 4 else { return }
        if version == 3 {
            // v3 → v4: 스크롤 10칸(시스템 8칸 + 1.25·1.5) → 시스템과 같은 8칸 (가장 가까운 값의 칸으로)
            let old10: [Double] = [0, 0.125, 0.215, 0.3125, 0.5, 0.75, 1.0, 1.25, 1.5, 1.7]
            let convert = { (stop: Double) in scrollStop(forSystemValue: old10[(Int(stop.rounded()) - 1).clamped(to: 0...9)]) }
            for type in [TrackpadType.internal, .magicTrackpad] {
                for key in ["\(type.rawValue)_", "mac_default_\(type.rawValue)_"] {
                    if let old = defaults.object(forKey: key + "scrollSpeed") as? Double {
                        defaults.set(convert(old), forKey: key + "scrollSpeed")
                    }
                }
            }
            migratePresets { old, isScroll in isScroll ? convert(old) : old }
            defaults.set(4, forKey: versionKey)
            return
        }
        // v2(8칸)는 지금과 같은 표이므로 버전만 올린다
        guard version < 2 else {
            defaults.set(4, forKey: versionKey)
            return
        }
        for type in [TrackpadType.internal, .magicTrackpad] {
            for key in ["\(type.rawValue)_", "mac_default_\(type.rawValue)_"] {
                if let old = defaults.object(forKey: key + "trackingSpeed") as? Double {
                    defaults.set(trackingStop(forSystemValue: old * 0.3), forKey: key + "trackingSpeed")
                }
                if let old = defaults.object(forKey: key + "scrollSpeed") as? Double {
                    defaults.set(scrollStop(forSystemValue: old / 10), forKey: key + "scrollSpeed")
                }
            }
        }
        migratePresets { old, isScroll in
            isScroll ? scrollStop(forSystemValue: old / 10) : trackingStop(forSystemValue: old * 0.3)
        }
        defaults.set(4, forKey: versionKey)
    }
}

// MARK: - Comparable Clamp

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
