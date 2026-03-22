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
    private var keyToRefs: [String: Set<UInt>] = [:]
    private var monitoredInputRefs: [UInt: TrackpadType] = [:]
    private var inputReportBuffers: [UInt: UnsafeMutablePointer<UInt8>] = [:]
    private var inputReportLengths: [UInt: CFIndex] = [:]
    private let activeSwitchCooldown: TimeInterval = 0.15
    private let automaticActivationEnabled = false
    private let preferredBluetoothKey = "preferred_bluetooth_trackpad_key"

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
            return
        }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        for device in devices {
            let transport = property(device, key: kIOHIDTransportKey) ?? ""
            guard transport.lowercased().contains("bluetooth") else { continue }
            let productName = property(device, key: kIOHIDProductKey) ?? ""
            let vendorID = intProperty(device, key: kIOHIDVendorIDKey)
            let productID = intProperty(device, key: kIOHIDProductIDKey)
            let serialNumber = property(device, key: kIOHIDSerialNumberKey) ?? ""
            let key = BluetoothHIDDevice.deviceKey(name: productName, vendorID: vendorID, productID: productID, serialNumber: serialNumber)
            guard key == preferredKey, isMagicTrackpad(productID: productID, productName: productName) else { continue }
            let td = TrackpadDevice(hidDevice: device, type: .magicTrackpad, productName: productName, vendorID: vendorID, productID: productID, serialNumber: serialNumber)
            magicTrackpad = td
            return
        }
        magicTrackpad = nil
    }

    // MARK: - 모니터링 시작

    func startMonitoring() {
        TrackpadDevice.ensureMacDefaultsCaptured()

        // IOHIDSystem 연결
        _ = sensitivityController.openIOHIDSystem()

        // HID Manager 생성
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }

        // 트랙패드·마우스 매칭: Digitizer/TouchPad, GenericDesktop/Mouse, GenericDesktop/Pointer(일부 마우스), Apple 벤더
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
                kIOHIDDeviceUsageKey:     0x01  // Pointer — MX Master 등 일부 마우스
            ],
            [
                kIOHIDVendorIDKey: 0x05AC  // Apple Inc.
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

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // 현재 연결된 디바이스 스캔 (시작 시 기존 연결 감지)
        scanExistingDevices()
        updateFallbackActiveTrackpad()
        print("🟢 TrackpadManager 모니터링 시작")
    }

    func stopMonitoring() {
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        sensitivityController.closeIOHIDSystem()
        print("🔴 TrackpadManager 모니터링 종료")
    }

    // MARK: - 기존 연결 스캔

    private func scanExistingDevices() {
        guard let manager = hidManager else { return }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        for device in devices {
            deviceConnected(device)
        }
    }

    // MARK: - 디바이스 연결/해제 핸들링

    private func deviceConnected(_ device: IOHIDDevice) {
        let transport = property(device, key: kIOHIDTransportKey) ?? ""
        let productName = property(device, key: kIOHIDProductKey) ?? "Unknown"
        let vendorID = intProperty(device, key: kIOHIDVendorIDKey)
        let productID = intProperty(device, key: kIOHIDProductIDKey)
        let serialNumber = property(device, key: kIOHIDSerialNumberKey) ?? ""
        let usagePage = intProperty(device, key: kIOHIDDeviceUsagePageKey)
        let usage = intProperty(device, key: kIOHIDDeviceUsageKey)

        // 디버그: 매칭된 모든 HID 디바이스 로그 (블루투스 매직 트랙패드 확인용)
        print("🔌 HID 디바이스: \(productName) | transport=\(transport) | VID=\(String(vendorID, radix: 16)) PID=\(String(productID, radix: 16)) | usage=\(usagePage)/\(usage)")

        let normalizedTransport = transport.lowercased()
        let isInternal = ["spi", "usb", "built-in", "fifo"].contains(normalizedTransport)
        let isBluetooth = transport.lowercased().contains("bluetooth")
        let deviceIsMagicFamily = isMagicTrackpad(productID: productID, productName: productName)

        if isInternal {
            guard isTrackpad(device) else { print("   ⏭️ 내장은 트랙패드만 등록"); return }
            registerInputMonitoring(for: device, type: .internal)
            appendInputLog(source: "connect", type: .internal, deviceName: productName, detail: "transport=\(transport) usage=\(usagePage)/\(usage)")
            if internalTrackpad == nil {
                print("   ✅ 내장 트랙패드로 등록")
                let td = TrackpadDevice(
                    hidDevice: device,
                    type: .internal,
                    productName: productName,
                    vendorID: vendorID,
                    productID: productID,
                    serialNumber: serialNumber
                )
                internalTrackpad = td
            }
            updateFallbackActiveTrackpad()
            return
        }

        guard isBluetooth else { return }

        // 블루투스: 트랙패드 또는 마우스면 목록에 추가 (트랙패드/마우스 구분 표시용)
        let isTrackpadDevice = isTrackpad(device)
        let isMouseDevice = isMouse(device)
        guard isTrackpadDevice || isMouseDevice || deviceIsMagicFamily else {
            print("   ⏭️ 블루투스 포인팅 디바이스 아님")
            return
        }
        if deviceIsMagicFamily {
            appendInputLog(source: "connect", type: .magicTrackpad, deviceName: productName, detail: "transport=\(transport) usage=\(usagePage)/\(usage)")
        }

        let deviceRef = deviceRefValue(device)
        let key = BluetoothHIDDevice.deviceKey(name: productName, vendorID: vendorID, productID: productID, serialNumber: serialNumber)
        let kind: BluetoothDeviceKind = (isTrackpadDevice || deviceIsMagicFamily) ? .trackpad : .mouse
        let info = BluetoothHIDDevice(id: key, name: productName, vendorID: vendorID, productID: productID, serialNumber: serialNumber, deviceRef: deviceRef, kind: kind)
        refToKey[deviceRef] = key
        if keyToRefs[key] == nil { keyToRefs[key] = [] }
        keyToRefs[key]?.insert(deviceRef)
        bluetoothDevicesByKey[key] = info
        availableBluetoothDevices = Array(bluetoothDevicesByKey.values)

        if deviceIsMagicFamily {
            let preferred = preferredBluetoothDeviceKey
            let useThis = preferred == nil || preferred == key
            registerInputMonitoring(for: device, type: .magicTrackpad)
            if useThis {
                print("   ✅ 매직 트랙패드로 등록: \(productName)")
                let td = TrackpadDevice(
                    hidDevice: device,
                    type: .magicTrackpad,
                    productName: productName,
                    vendorID: vendorID,
                    productID: productID,
                    serialNumber: serialNumber
                )
                magicTrackpad = td
                updateFallbackActiveTrackpad()
            } else {
                print("   ⏭️ 블루투스 트랙패드 목록에만 추가 (선택된 기기 아님): \(productName)")
            }
        } else if isMouseDevice {
            print("   📋 블루투스 마우스 목록에 추가: \(productName)")
        }
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        let ref = deviceRefValue(device)
        monitoredInputRefs.removeValue(forKey: ref)
        if let reportBuffer = inputReportBuffers.removeValue(forKey: ref) {
            reportBuffer.deallocate()
        }
        inputReportLengths.removeValue(forKey: ref)
        if let key = refToKey.removeValue(forKey: ref) {
            keyToRefs[key]?.remove(ref)
            if keyToRefs[key]?.isEmpty == true {
                keyToRefs.removeValue(forKey: key)
                bluetoothDevicesByKey.removeValue(forKey: key)
            }
            availableBluetoothDevices = Array(bluetoothDevicesByKey.values)
        }

        if internalTrackpad?.hidDevice == device {
            internalTrackpad = nil
            appendInputLog(source: "disconnect", type: .internal, deviceName: property(device, key: kIOHIDProductKey) ?? "Unknown", detail: "")
            print("❌ 내장 트랙패드 연결 해제")
        }
        if magicTrackpad?.hidDevice == device {
            magicTrackpad = nil
            appendInputLog(source: "disconnect", type: .magicTrackpad, deviceName: property(device, key: kIOHIDProductKey) ?? "Unknown", detail: "")
            print("❌ 매직 트랙패드 연결 해제")
        }
        updateFallbackActiveTrackpad()
    }

    private func deviceRefValue(_ device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device as AnyObject).toOpaque())
    }

    // MARK: - 감도 적용

    /// 트랙패드 설정을 IOKit에 실제로 적용
    func applySettings(for device: TrackpadDevice) {
        sensitivityController.setClickPressure(device.clickPressure, for: device.type)
        device.saveSettings()
        applyActiveProfileIfNeeded(for: device.type)
    }

    func activateProfileManually(for type: TrackpadType) {
        activateTrackpad(type, source: "manual", force: true)
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

    // MARK: - 활성 장치 기반 스위칭

    private func registerInputMonitoring(for device: IOHIDDevice, type: TrackpadType) {
        let ref = deviceRefValue(device)
        guard monitoredInputRefs[ref] == nil else { return }
        monitoredInputRefs[ref] = type
        let productName = property(device, key: kIOHIDProductKey) ?? "Unknown"
        IOHIDDeviceRegisterInputValueCallback(device, { context, _, sender, value in
            guard let context, let sender else { return }
            let manager = Unmanaged<TrackpadManager>.fromOpaque(context).takeUnretainedValue()
            let hidDevice = unsafeBitCast(sender, to: IOHIDDevice.self)
            manager.handleInputValue(from: hidDevice, value: value)
        }, Unmanaged.passUnretained(self).toOpaque())

        let maxReportSize = max(
            64,
            (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
        )
        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxReportSize)
        inputReportBuffers[ref] = reportBuffer
        inputReportLengths[ref] = CFIndex(maxReportSize)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer,
            CFIndex(maxReportSize),
            { context, _, sender, _, _, _, reportLength in
                guard let context, let sender else { return }
                let manager = Unmanaged<TrackpadManager>.fromOpaque(context).takeUnretainedValue()
                let hidDevice = unsafeBitCast(sender, to: IOHIDDevice.self)
                manager.handleInputReport(from: hidDevice, reportLength: reportLength)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        appendInputLog(source: "monitor", type: type, deviceName: productName, detail: "ref=\(ref)")
        print("🎧 입력 감시 등록: \(productName) [\(type.displayName)]")
    }

    private func handleInputValue(from device: IOHIDDevice, value: IOHIDValue) {
        let ref = deviceRefValue(device)
        guard let type = monitoredInputRefs[ref] else { return }
        guard isMeaningfulInput(value) else { return }
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        appendInputLog(
            source: "value",
            type: type,
            deviceName: property(device, key: kIOHIDProductKey) ?? "Unknown",
            detail: "ref=\(ref) usage=\(usagePage)/\(usage) value=\(intValue)"
        )
        guard automaticActivationEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.activateTrackpad(type, source: "input")
        }
    }

    private func handleInputReport(from device: IOHIDDevice, reportLength: CFIndex) {
        let ref = deviceRefValue(device)
        guard let type = monitoredInputRefs[ref] else { return }
        guard reportLength > 0 else { return }
        appendInputLog(
            source: "report",
            type: type,
            deviceName: property(device, key: kIOHIDProductKey) ?? "Unknown",
            detail: "ref=\(ref) len=\(reportLength)"
        )
        guard automaticActivationEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.activateTrackpad(type, source: "report")
        }
    }

    private func isMeaningfulInput(_ value: IOHIDValue) -> Bool {
        let element = IOHIDValueGetElement(value)
        let integerValue = IOHIDValueGetIntegerValue(value)
        guard integerValue != 0 else { return false }

        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        if usagePage == kHIDPage_GenericDesktop {
            return usage == kHIDUsage_GD_X
                || usage == kHIDUsage_GD_Y
                || usage == kHIDUsage_GD_Wheel
        }

        if usagePage == kHIDPage_Digitizer {
            return true
        }

        return false
    }

    private func activateTrackpad(_ type: TrackpadType, source: String, force: Bool = false) {
        let now = Date()
        if activeTrackpadType == type && !force {
            return
        }
        if !force, let lastSwitch = lastActiveSwitchAt, now.timeIntervalSince(lastSwitch) < activeSwitchCooldown {
            return
        }
        activeTrackpadType = type
        lastActiveSwitchAt = now
        appendInputLog(source: "activate", type: type, deviceName: device(for: type)?.productName ?? type.displayName, detail: "source=\(source)")
        applyProfile(for: type)
        print("🎯 활성 트랙패드 전환: \(type.displayName) source=\(source)")
    }

    private func updateFallbackActiveTrackpad() {
        guard automaticActivationEnabled else { return }
        if activeTrackpadType == .internal, internalTrackpad == nil {
            activeTrackpadType = nil
        }
        if activeTrackpadType == .magicTrackpad, magicTrackpad == nil {
            activeTrackpadType = nil
        }

        if activeTrackpadType == nil {
            if internalTrackpad != nil && magicTrackpad == nil {
                activateTrackpad(.internal, source: "fallback")
            } else if magicTrackpad != nil && internalTrackpad == nil {
                activateTrackpad(.magicTrackpad, source: "fallback")
            }
        }
    }

    private func applyActiveProfileIfNeeded(for type: TrackpadType) {
        if activeTrackpadType == nil {
            guard automaticActivationEnabled else { return }
            activateTrackpad(type, source: "settings")
            return
        }
        guard activeTrackpadType == type else { return }
        applyProfile(for: type)
    }

    private func applyProfile(for type: TrackpadType) {
        guard let device = device(for: type) else { return }
        sensitivityController.setGlobalTrackpadTrackingSpeed(device.trackingSpeed)
        sensitivityController.setGlobalTrackpadScrollSpeed(device.scrollSpeed)
        sensitivityController.setClickPressure(device.clickPressure, for: type)
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

    private func isTrackpad(_ device: IOHIDDevice) -> Bool {
        let usagePage = intProperty(device, key: kIOHIDDeviceUsagePageKey)
        let usage = intProperty(device, key: kIOHIDDeviceUsageKey)
        let productName = (property(device, key: kIOHIDProductKey) ?? "").lowercased()

        // 1) HID Usage: Digitizer + TouchPad (일반 트랙패드)
        let isDigitizer = usagePage == kHIDPage_Digitizer && usage == kHIDUsage_Dig_TouchPad
        // 2) 블루투스/내장 일부 기기는 usage=0/0으로 올라오므로 이름으로 보완
        let nameIsTrackpad = productName.contains("trackpad")
            || productName.contains("track pad")
            || productName.contains("internal keyboard / trackpad")

        return isDigitizer || nameIsTrackpad
    }

    private func isMouse(_ device: IOHIDDevice) -> Bool {
        let usagePage = intProperty(device, key: kIOHIDDeviceUsagePageKey)
        let usage = intProperty(device, key: kIOHIDDeviceUsageKey)
        let name = (property(device, key: kIOHIDProductKey) ?? "").lowercased()
        // HID: Generic Desktop + Mouse(0x02) 또는 Pointer(0x01, 일부 마우스)
        let usageMouse = usagePage == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_Mouse || usage == 0x01)
        let nameMouse = name.contains("mouse") || name.contains("마우스") || name.contains("master") || name.contains("mx ")
        return usageMouse || nameMouse
    }

    private func isMagicTrackpad(productID: Int, productName: String) -> Bool {
        // 매직 트랙패드 1: 0x030E, 2: 0x0265, 3: 0x0274, 기타 Apple 트랙패드
        let magicTrackpadProductIDs = [0x030E, 0x0265, 0x0274, 0x0255]
        let name = productName.lowercased()
        return magicTrackpadProductIDs.contains(productID)
            || name.contains("magic trackpad")
            || name.contains("magic track pad")
            || name.contains("trackpad")
    }

    private func property(_ device: IOHIDDevice, key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private func intProperty(_ device: IOHIDDevice, key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? Int) ?? 0
    }
}
