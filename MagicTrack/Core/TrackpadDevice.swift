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

        // 저장된 값 로드 (없으면 기본값). 이전 0~3 스케일은 0~10으로 마이그레이션
        let key = "\(type.rawValue)_"
        var rawTracking = UserDefaults.standard.double(forKey: key + "trackingSpeed")
        var rawScroll = UserDefaults.standard.double(forKey: key + "scrollSpeed")
        if rawTracking > 0 && rawTracking <= 3.0 { rawTracking = rawTracking / 3.0 * 10.0 }
        if rawScroll > 0 && rawScroll <= 3.0 { rawScroll = rawScroll / 3.0 * 10.0 }
        self.trackingSpeed = rawTracking.clamped(to: TrackpadDevice.speedRange)
        self.scrollSpeed = rawScroll.clamped(to: TrackpadDevice.speedRange)
        // 클릭 압력: 키가 없으면 기본값 보통(1). integer(forKey:)는 키 없을 때 0을 반환하므로 구분 필요
        let clickKey = key + "clickPressure"
        if UserDefaults.standard.object(forKey: clickKey) != nil {
            self.clickPressure = min(max(UserDefaults.standard.integer(forKey: clickKey), 0), 2)
        } else {
            self.clickPressure = 1  // 보통 = 기본값
        }
        if let storedRotation = UserDefaults.standard.string(forKey: key + "rotation"),
           let rotation = TrackpadRotation(rawValue: storedRotation) {
            self.rotation = rotation
        } else {
            self.rotation = .standard
        }

        // 저장된 값이 없었으면 기본값 5
        if UserDefaults.standard.object(forKey: key + "trackingSpeed") == nil || self.trackingSpeed == 0.0 {
            self.trackingSpeed = TrackpadDevice.defaultTrackingSpeed(for: type)
        }
        if UserDefaults.standard.object(forKey: key + "scrollSpeed") == nil || self.scrollSpeed == 0.0 {
            self.scrollSpeed = TrackpadDevice.defaultScrollSpeed(for: type)
        }
        if UserDefaults.standard.object(forKey: clickKey) == nil {
            self.clickPressure = TrackpadDevice.defaultClickPressure(for: type)
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
            value: controller.getCurrentClickPressure(for: .internal)
        )
        captureIfNeeded(
            key: macDefaultKey(for: .magicTrackpad, suffix: "clickPressure"),
            value: controller.getCurrentClickPressure(for: .magicTrackpad)
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
