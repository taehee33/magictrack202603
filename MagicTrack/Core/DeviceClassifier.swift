import Foundation
import IOKit.hid

// MARK: - DeviceClassifier
// HID 장치 속성만으로 내장 트랙패드 / 매직 트랙패드 / 기타 트랙패드 / 마우스를 구분한다.
//
// 실측(macOS 27.0.1, Apple Silicon) 근거:
// - kIOHIDDeviceUsagePageKey/UsageKey는 매칭용 키라 장치 속성으로 읽으면 항상 0 → DeviceUsagePairs를 읽어야 함
// - 내장 트랙패드: Transport "FIFO", VID/PID 0, Built-In = 1
// - 매직 트랙패드(블루투스): VID 0x004C(Bluetooth SIG의 Apple ID), USB 연결 시 VID 0x05AC
// - 장치 이름은 사용자가 바꿀 수 있으므로 판별의 보조 수단으로만 사용

enum HIDDeviceKind: Equatable {
    case internalTrackpad
    case magicTrackpad
    case otherTrackpad
    case mouse
    case ignored
}

struct HIDDeviceSnapshot {
    let productName: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let serialNumber: String
    let isBuiltIn: Bool
    let usagePairs: [(page: Int, usage: Int)]

    init(device: IOHIDDevice) {
        func string(_ key: String) -> String { (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? "" }
        func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
        productName = string(kIOHIDProductKey)
        transport = string(kIOHIDTransportKey)
        vendorID = int(kIOHIDVendorIDKey)
        productID = int(kIOHIDProductIDKey)
        serialNumber = string(kIOHIDSerialNumberKey)
        isBuiltIn = int("Built-In") == 1
        let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] ?? []
        var parsed = pairs.compactMap { pair -> (page: Int, usage: Int)? in
            guard let page = (pair[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue,
                  let usage = (pair[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue else { return nil }
            return (page, usage)
        }
        if parsed.isEmpty {
            // DeviceUsagePairs가 없는 장치는 기본 usage로 대체
            parsed = [(int(kIOHIDPrimaryUsagePageKey), int(kIOHIDPrimaryUsageKey))]
        }
        usagePairs = parsed
    }

    init(productName: String, transport: String, vendorID: Int, productID: Int, serialNumber: String = "",
         isBuiltIn: Bool, usagePairs: [(page: Int, usage: Int)]) {
        self.productName = productName
        self.transport = transport
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.isBuiltIn = isBuiltIn
        self.usagePairs = usagePairs
    }
}

enum DeviceClassifier {
    /// Apple USB VID와 Bluetooth SIG에 등록된 Apple 회사 ID
    static let appleVendorIDs: Set<Int> = [0x05AC, 0x004C]
    /// 매직 트랙패드 PID — 1세대 0x030E, 2세대 0x0265, USB-C 0x0324 (나머지는 기존 목록 유지)
    static let magicTrackpadProductIDs: Set<Int> = [0x030E, 0x0265, 0x0274, 0x0255, 0x0314, 0x0324]

    static func classify(_ d: HIDDeviceSnapshot) -> HIDDeviceKind {
        let hasTouchPad = d.usagePairs.contains { $0.page == kHIDPage_Digitizer && $0.usage == kHIDUsage_Dig_TouchPad }
        let hasPointer = d.usagePairs.contains {
            $0.page == kHIDPage_GenericDesktop && ($0.usage == kHIDUsage_GD_Mouse || $0.usage == kHIDUsage_GD_Pointer)
        }
        let hasKeyboard = d.usagePairs.contains { $0.page == kHIDPage_GenericDesktop && $0.usage == kHIDUsage_GD_Keyboard }
        let name = d.productName.lowercased()

        if hasTouchPad {
            if d.isBuiltIn { return .internalTrackpad }
            let isApple = appleVendorIDs.contains(d.vendorID)
            if isApple && (magicTrackpadProductIDs.contains(d.productID) || name.contains("trackpad")) {
                return .magicTrackpad
            }
            return .otherTrackpad
        }
        if hasPointer && !hasKeyboard && !d.isBuiltIn {
            return .mouse
        }
        return .ignored
    }
}
