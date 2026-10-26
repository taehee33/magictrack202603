import Foundation
import IOKit
import IOKit.hid

// MARK: - TrackpadType

enum TrackpadType: String, Codable {
    case `internal` = "internal"
    case magicTrackpad = "magic_trackpad"

    var displayName: String {
        switch self {
        case .internal: return "내장 트랙패드"
        case .magicTrackpad: return "매직 트랙패드"
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
        case .standard: return "기본"
        case .left90: return "왼쪽 90°"
        case .right90: return "오른쪽 90°"
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
    @Published var trackingSpeed: Double      // 0.0 ~ 10.0 (UI/저장), 기본 5
    @Published var scrollSpeed: Double        // 0.0 ~ 10.0 (UI/저장), 기본 5
    @Published var clickPressure: Int         // 0 ~ 2 (Light / Medium / Firm)
    @Published var rotation: TrackpadRotation

    /// 이동/스크롤 속도 UI 범위 (시스템은 0~3 사용)
    static let speedRange: ClosedRange<Double> = 0.0...10.0
    static let defaultSpeed: Double = 5.0
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
            self.trackingSpeed = defaults.double(forKey: key + "trackingSpeed").clamped(to: TrackpadDevice.speedRange)
        } else {
            self.trackingSpeed = TrackpadDevice.defaultTrackingSpeed(for: type)
        }
        if defaults.object(forKey: key + "scrollSpeed") != nil {
            self.scrollSpeed = defaults.double(forKey: key + "scrollSpeed").clamped(to: TrackpadDevice.speedRange)
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
    }

    func saveSettings() {
        let key = "\(type.rawValue)_"
        UserDefaults.standard.set(trackingSpeed, forKey: key + "trackingSpeed")
        UserDefaults.standard.set(scrollSpeed, forKey: key + "scrollSpeed")
        UserDefaults.standard.set(clickPressure, forKey: key + "clickPressure")
        UserDefaults.standard.set(rotation.rawValue, forKey: key + "rotation")
    }

    // MARK: - 기본값 (초기화 버튼용)

    static func defaultTrackingSpeed(for type: TrackpadType) -> Double {
        UserDefaults.standard.object(forKey: macDefaultKey(for: type, suffix: "trackingSpeed")) != nil
            ? UserDefaults.standard.double(forKey: macDefaultKey(for: type, suffix: "trackingSpeed"))
            : TrackpadDevice.defaultSpeed
    }

    static func defaultScrollSpeed(for type: TrackpadType) -> Double {
        UserDefaults.standard.object(forKey: macDefaultKey(for: type, suffix: "scrollSpeed")) != nil
            ? UserDefaults.standard.double(forKey: macDefaultKey(for: type, suffix: "scrollSpeed"))
            : TrackpadDevice.defaultSpeed
    }

    static func defaultClickPressure(for type: TrackpadType) -> Int {
        UserDefaults.standard.object(forKey: macDefaultKey(for: type, suffix: "clickPressure")) != nil
            ? UserDefaults.standard.integer(forKey: macDefaultKey(for: type, suffix: "clickPressure"))
            : 1
    }

    static func ensureMacDefaultsCaptured() {
        let controller = SensitivityController.shared

        captureIfNeeded(
            key: macDefaultKey(for: .internal, suffix: "trackingSpeed"),
            value: uiTrackingValue(fromSystemTracking: controller.getCurrentTrackingSpeed())
        )
        captureIfNeeded(
            key: macDefaultKey(for: .magicTrackpad, suffix: "trackingSpeed"),
            value: uiTrackingValue(fromSystemTracking: controller.getCurrentTrackingSpeed())
        )
        captureIfNeeded(
            key: macDefaultKey(for: .internal, suffix: "scrollSpeed"),
            value: uiScrollValue(fromSystemScroll: controller.getCurrentScrollSpeed())
        )
        captureIfNeeded(
            key: macDefaultKey(for: .magicTrackpad, suffix: "scrollSpeed"),
            value: uiScrollValue(fromSystemScroll: controller.getCurrentScrollSpeed())
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

    private static func macDefaultKey(for type: TrackpadType, suffix: String) -> String {
        "\(macDefaultPrefix)\(type.rawValue)_\(suffix)"
    }

    private static func uiTrackingValue(fromSystemTracking value: Double) -> Double {
        (value / 3.0 * 10.0).clamped(to: speedRange)
    }

    private static func uiScrollValue(fromSystemScroll value: Double) -> Double {
        (value * 10.0).clamped(to: speedRange)
    }
}

// MARK: - Comparable Clamp

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
