import Foundation
import IOKit
import IOKit.hid
import Combine

// MARK: - BluetoothHIDDevice
/// 블루투스로 감지된 HID 디바이스 (트랙패드/마우스 선택 목록용)
enum BluetoothDeviceKind: String {
    case trackpad = "트랙패드"
    case mouse = "마우스"
}

struct BluetoothHIDDevice: Identifiable {
    let id: String  // deviceKey와 동일 (선택 저장용)
    let name: String
    let vendorID: Int
    let productID: Int
    let serialNumber: String
    let deviceRef: UInt  // 연결 해제 시 목록에서 제거용
    /// 트랙패드 / 마우스 구분 (선택 시 어떤 기기로 바꿨는지 명확히 하기 위함)
    let kind: BluetoothDeviceKind

    static func deviceKey(name: String, vendorID: Int, productID: Int, serialNumber: String) -> String {
        let serial = serialNumber.isEmpty ? "noSerial" : serialNumber
        return "\(name)|\(vendorID)|\(productID)|\(serial)"
    }
}

struct TrackpadInputDebugLog: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let source: String
    let trackpadType: TrackpadType?
    let deviceName: String
    let detail: String
}

// MARK: - TrackpadManager
// IOKit HID Manager로 트랙패드 디바이스를 탐지하고 관리하는 메인 매니저

final class TrackpadManager: ObservableObject {
    static let shared = TrackpadManager()

    @Published var internalTrackpad: TrackpadDevice?
    @Published var magicTrackpad: TrackpadDevice?
    @Published private(set) var activeTrackpadType: TrackpadType?
    @Published private(set) var lastActiveSwitchAt: Date?
    @Published private(set) var recentInputLogs: [TrackpadInputDebugLog] = []
    @Published private(set) var hidConnectCount = 0
    @Published private(set) var hidMonitorCount = 0
    @Published private(set) var hidValueCount = 0
    @Published private(set) var hidReportCount = 0
    @Published private(set) var hidActivateCount = 0
    /// 블루투스로 감지된 HID 디바이스 목록 (매직 트랙패드 선택 UI용)
    @Published var availableBluetoothDevices: [BluetoothHIDDevice] = []

    private var hidManager: IOHIDManager?
    private let sensitivityController = SensitivityController.shared
    private var cancellables = Set<AnyCancellable>()
    /// 논리 기기당 하나만 유지 (같은 기기가 여러 HID 인터페이스로 올 수 있음)
    private var bluetoothDevicesByKey: [String: BluetoothHIDDevice] = [:]
    private var refToKey: [UInt: String] = [:]
    private var magicTrackpadKey: String?
    private var keyToRefs: [String: Set<UInt>] = [:]
    private let preferredBluetoothKey = "preferred_bluetooth_trackpad_key"
    /// 사용자가 마지막으로 직접 고른 트랙패드. 앱 재실행·장치 재연결 시 이 프로필을 다시 적용한다
    private let preferredActiveKey = "active_trackpad_type"
    /// 시작 시 기존 장치를 훑는 동안에는 장치마다 프로필을 바꾸지 않고, 다 찾은 뒤 한 번만 적용한다
    private var isScanningExistingDevices = false

    private init() {}

    /// 사용자가 선택한 블루투스 매직 트랙패드 키 (nil이면 첫 번째 감지된 기기 사용)
    var preferredBluetoothDeviceKey: String? {
        get { UserDefaults.standard.string(forKey: preferredBluetoothKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferredBluetoothKey) }
    }

    /// 매직 트랙패드로 사용할 블루투스 기기 선택
    func setPreferredBluetoothDevice(key: String?) {
        preferredBluetoothDeviceKey = key
        objectWillChange.send()
        if key == nil {
            magicTrackpad = nil
            magicTrackpadKey = nil
            restoreActiveTrackpad(source: "select")
            return
        }
        // 선택한 기기가 이미 연결돼 있으면 즉시 매직 트랙패드로 적용
        refreshMagicTrackpadFromPreferred()
    }

    /// preferredBluetoothDeviceKey에 맞는 연결된 기기를 찾아 magicTrackpad로 설정. 트랙패드만 적용, 마우스 선택 시에는 미적용.
    func refreshMagicTrackpadFromPreferred() {
        guard let manager = hidManager, let preferredKey = preferredBluetoothDeviceKey else { return }
        guard let info = bluetoothDevicesByKey[preferredKey], info.kind == .trackpad else {
            magicTrackpad = nil
            magicTrackpadKey = nil
            restoreActiveTrackpad(source: "select")
            return
        }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        for device in devices {
            let d = HIDDeviceSnapshot(device: device)
            let kind = DeviceClassifier.classify(d)
            guard kind == .magicTrackpad || kind == .otherTrackpad else { continue }
            guard Self.deviceKey(for: d) == preferredKey else { continue }
            magicTrackpadKey = preferredKey
            magicTrackpad = TrackpadDevice(hidDevice: device, type: .magicTrackpad, productName: d.productName, vendorID: d.vendorID, productID: d.productID, serialNumber: d.serialNumber)
            restoreActiveTrackpad(source: "select")
            return
        }
        magicTrackpad = nil
        magicTrackpadKey = nil
    }

    // MARK: - 모니터링 시작

    func startMonitoring() {
        TrackpadDevice.ensureMacDefaultsCaptured()

        // IOHIDSystem 연결
        _ = sensitivityController.openIOHIDSystem()

        // HID Manager 생성
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }

        // 트랙패드·마우스 매칭: Digitizer/TouchPad, GenericDesktop/Mouse, GenericDesktop/Pointer(일부 마우스)
        let matchingDicts: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_Digitizer,
                kIOHIDDeviceUsageKey:     kHIDUsage_Dig_TouchPad
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey:     kHIDUsage_GD_Mouse
            ],
            [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey:     kHIDUsage_GD_Pointer  // MX Master 등 일부 마우스
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts as CFArray)

        // ─── 디바이스 연결 콜백 ───
        let matchCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let mgr = Unmanaged<TrackpadManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                mgr.deviceConnected(device)
            }
        }

        // ─── 디바이스 해제 콜백 ───
        let removeCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let mgr = Unmanaged<TrackpadManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                mgr.deviceDisconnected(device)
            }
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matchCallback, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removeCallback, selfPtr)

        // 장치 목록·연결 알림만 쓰고 입력은 읽지 않으므로 IOHIDManagerOpen을 호출하지 않는다 (입력 모니터링 권한 불필요)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // 현재 연결된 디바이스 스캔 후 마지막으로 쓰던 프로필 적용
        scanExistingDevices()
        restoreActiveTrackpad(source: "launch")
        print("🟢 TrackpadManager 모니터링 시작")
    }

    func stopMonitoring() {
        if let manager = hidManager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            hidManager = nil
        }
        sensitivityController.closeIOHIDSystem()
        print("🔴 TrackpadManager 모니터링 종료")
    }

    // MARK: - 기존 연결 스캔

    private func scanExistingDevices() {
        guard let manager = hidManager else { return }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        isScanningExistingDevices = true
        for device in devices {
            deviceConnected(device)
        }
        isScanningExistingDevices = false
    }

    // MARK: - 디바이스 연결/해제 핸들링

    private func deviceConnected(_ device: IOHIDDevice) {
        let d = HIDDeviceSnapshot(device: device)
        let kind = DeviceClassifier.classify(d)
        let pairs = d.usagePairs.map { "\($0.page)/\($0.usage)" }.joined(separator: ",")
        print("🔌 HID 디바이스: \(d.productName) | transport=\(d.transport) | VID=\(String(d.vendorID, radix: 16)) PID=\(String(d.productID, radix: 16)) | builtIn=\(d.isBuiltIn) | usage=\(pairs) → \(kind)")

        switch kind {
        case .ignored:
            return
        case .internalTrackpad:
            appendInputLog(source: "connect", type: .internal, deviceName: d.productName, detail: "transport=\(d.transport) usage=\(pairs)")
            if internalTrackpad == nil {
                internalTrackpad = TrackpadDevice(hidDevice: device, type: .internal, productName: d.productName, vendorID: d.vendorID, productID: d.productID, serialNumber: d.serialNumber)
                restoreActiveTrackpad(source: "connect")
            }
            return
        case .magicTrackpad, .otherTrackpad, .mouse:
            break
        }

        // 외장 장치: 선택 목록에 추가 (같은 기기의 여러 HID 인터페이스는 하나로 묶음)
        let deviceRef = deviceRefValue(device)
        let key = Self.deviceKey(for: d)
        let listKind: BluetoothDeviceKind = kind == .mouse ? .mouse : .trackpad
        let info = BluetoothHIDDevice(id: key, name: d.productName, vendorID: d.vendorID, productID: d.productID, serialNumber: d.serialNumber, deviceRef: deviceRef, kind: listKind)
        refToKey[deviceRef] = key
        keyToRefs[key, default: []].insert(deviceRef)
        bluetoothDevicesByKey[key] = info
        availableBluetoothDevices = Array(bluetoothDevicesByKey.values)

        guard kind != .mouse else { return }
        appendInputLog(source: "connect", type: .magicTrackpad, deviceName: d.productName, detail: "transport=\(d.transport) usage=\(pairs)")

        // 매직 트랙패드 슬롯: 사용자가 고른 기기, 없으면 처음 발견한 매직 트랙패드
        let preferred = preferredBluetoothDeviceKey
        let useThis = preferred == key || (preferred == nil && kind == .magicTrackpad)
        guard useThis, magicTrackpadKey != key || magicTrackpad == nil else { return }
        print("   ✅ 매직 트랙패드로 등록: \(d.productName)")
        magicTrackpadKey = key
        magicTrackpad = TrackpadDevice(hidDevice: device, type: .magicTrackpad, productName: d.productName, vendorID: d.vendorID, productID: d.productID, serialNumber: d.serialNumber)
        restoreActiveTrackpad(source: "connect")
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        let ref = deviceRefValue(device)
        if let key = refToKey.removeValue(forKey: ref) {
            keyToRefs[key]?.remove(ref)
            if keyToRefs[key]?.isEmpty == true {
                keyToRefs.removeValue(forKey: key)
                bluetoothDevicesByKey.removeValue(forKey: key)
                if key == magicTrackpadKey, magicTrackpad != nil {
                    magicTrackpad = nil
                    magicTrackpadKey = nil
                    appendInputLog(source: "disconnect", type: .magicTrackpad, deviceName: property(device, key: kIOHIDProductKey) ?? "Unknown", detail: "")
                    print("❌ 매직 트랙패드 연결 해제")
                }
            }
            availableBluetoothDevices = Array(bluetoothDevicesByKey.values)
        }

        if internalTrackpad?.hidDevice == device {
            internalTrackpad = nil
            appendInputLog(source: "disconnect", type: .internal, deviceName: property(device, key: kIOHIDProductKey) ?? "Unknown", detail: "")
            print("❌ 내장 트랙패드 연결 해제")
        }
        restoreActiveTrackpad(source: "disconnect")
    }

    private static func deviceKey(for d: HIDDeviceSnapshot) -> String {
        BluetoothHIDDevice.deviceKey(name: d.productName, vendorID: d.vendorID, productID: d.productID, serialNumber: d.serialNumber)
    }

    private func deviceRefValue(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device as AnyObject).toOpaque())
    }

    // MARK: - 감도 적용

    /// 트랙패드 설정을 IOKit에 실제로 적용
    /// 장치 설정을 저장하고, 그 장치가 지금 적용 중인 프로필이면 시스템에 바로 반영
    func applySettings(for device: TrackpadDevice) {
        device.saveSettings()
        if activeTrackpadType == device.type {
            applyProfile(for: device.type)
        }
    }

    /// 프리셋 적용 등으로 값이 바뀐 뒤 현재 활성 프로필을 다시 적용
    func reapplyActiveProfile() {
        guard let type = activeTrackpadType else {
            restoreActiveTrackpad(source: "reapply")
            return
        }
        applyProfile(for: type)
    }

    func activateProfileManually(for type: TrackpadType) {
        activateTrackpad(type, source: "manual", force: true, persist: true)
    }

    func toggleSelectedTrackpad() {
        let hasInternal = internalTrackpad != nil
        let hasMagic = magicTrackpad != nil

        switch (hasInternal, hasMagic, activeTrackpadType) {
        case (true, true, .internal):
            activateProfileManually(for: .magicTrackpad)
        case (true, true, .magicTrackpad):
            activateProfileManually(for: .internal)
        case (true, true, nil):
            activateProfileManually(for: .internal)
        case (true, false, _):
            activateProfileManually(for: .internal)
        case (false, true, _):
            activateProfileManually(for: .magicTrackpad)
        default:
            break
        }
    }

    // MARK: - 편의 메서드

    func setTrackingSpeed(_ speed: Double, for type: TrackpadType) {
        switch type {
        case .internal:
            internalTrackpad?.trackingSpeed = speed
            if let device = internalTrackpad {
                applySettings(for: device)
            }
        case .magicTrackpad:
            magicTrackpad?.trackingSpeed = speed
            if let device = magicTrackpad {
                applySettings(for: device)
            }
        }
    }

    func setScrollSpeed(_ speed: Double, for type: TrackpadType) {
        switch type {
        case .internal:
            internalTrackpad?.scrollSpeed = speed
            if let device = internalTrackpad {
                applySettings(for: device)
            }
        case .magicTrackpad:
            magicTrackpad?.scrollSpeed = speed
            if let device = magicTrackpad {
                applySettings(for: device)
            }
        }
    }

    // MARK: - 활성 장치 전환

    /// - persist: 사용자가 직접 고른 경우에만 true. 재실행·재연결 시 이 선택을 다시 적용한다
    private func activateTrackpad(_ type: TrackpadType, source: String, force: Bool = false, persist: Bool = false) {
        if persist {
            UserDefaults.standard.set(type.rawValue, forKey: preferredActiveKey)
        }
        if activeTrackpadType == type && !force {
            return
        }
        activeTrackpadType = type
        lastActiveSwitchAt = Date()
        appendInputLog(source: "activate", type: type, deviceName: device(for: type)?.productName ?? type.displayName, detail: "source=\(source)")
        applyProfile(for: type)
        print("🎯 활성 트랙패드 전환: \(type.displayName) source=\(source)")
    }

    /// 연결 상태에 맞춰 적용할 프로필을 정한다.
    /// 마지막으로 직접 고른 트랙패드가 연결돼 있으면 그것, 없으면 연결된 트랙패드(내장 우선)
    private func restoreActiveTrackpad(source: String) {
        guard !isScanningExistingDevices else { return }
        let preferred = UserDefaults.standard.string(forKey: preferredActiveKey).flatMap(TrackpadType.init(rawValue:))
        let target: TrackpadType?
        if let preferred, device(for: preferred) != nil {
            target = preferred
        } else if internalTrackpad != nil {
            target = .internal
        } else if magicTrackpad != nil {
            target = .magicTrackpad
        } else {
            target = nil
        }
        guard let target else {
            activeTrackpadType = nil
            return
        }
        // 실행 직후에는 같은 장치라도 반드시 한 번 적용
        activateTrackpad(target, source: source, force: source == "launch" || source == "select")
    }

    private func applyProfile(for type: TrackpadType) {
        guard let device = device(for: type) else { return }
        sensitivityController.setTrackingSpeed(device.trackingSpeed)
        sensitivityController.setScrollSpeed(device.scrollSpeed)
        sensitivityController.setClickPressure(device.clickPressure)
    }

    private func device(for type: TrackpadType) -> TrackpadDevice? {
        switch type {
        case .internal:
            return internalTrackpad
        case .magicTrackpad:
            return magicTrackpad
        }
    }

    private func appendInputLog(source: String, type: TrackpadType?, deviceName: String, detail: String) {
        let entry = TrackpadInputDebugLog(
            source: source,
            trackpadType: type,
            deviceName: deviceName,
            detail: detail
        )
        DispatchQueue.main.async {
            switch source {
            case "connect":
                self.hidConnectCount += 1
            case "monitor":
                self.hidMonitorCount += 1
            case "value":
                self.hidValueCount += 1
            case "report":
                self.hidReportCount += 1
            case "activate":
                self.hidActivateCount += 1
            default:
                break
            }
            self.recentInputLogs.insert(entry, at: 0)
            if self.recentInputLogs.count > 10 {
                self.recentInputLogs = Array(self.recentInputLogs.prefix(10))
            }
        }
    }

    // MARK: - 헬퍼

    private func property(_ device: IOHIDDevice, key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

}
