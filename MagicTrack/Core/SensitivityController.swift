import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

// 스크롤 가속 키 (일부 SDK에 kIOHIDScrollAccelerationType 없음 → 문자열 사용)
private let kScrollAccelKey = "HIDScrollAcceleration" as CFString

// MARK: - SensitivityController
// IOKit을 통해 실제 트랙패드 감도를 읽고 쓰는 핵심 컨트롤러

final class SensitivityController {

    static let shared = SensitivityController()
    private init() {}

    // MARK: - IOHIDSystem Connection

    private var ioHIDSystemConnect: io_connect_t = 0
    private var eventSystemClient: IOHIDEventSystemClient?
    private var didLogServiceCandidates = false

    func openIOHIDSystem() -> Bool {
        if eventSystemClient == nil {
            eventSystemClient = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem")
        )
        guard service != 0 else {
            print("❌ IOHIDSystem 서비스를 찾을 수 없습니다.")
            return false
        }
        let result = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &ioHIDSystemConnect)
        IOObjectRelease(service)

        if result == kIOReturnSuccess {
            print("✅ IOHIDSystem 연결 성공")
            return true
        } else {
            print("❌ IOHIDSystem 연결 실패: \(result)")
            return false
        }
    }

    func closeIOHIDSystem() {
        if ioHIDSystemConnect != 0 {
            IOServiceClose(ioHIDSystemConnect)
            ioHIDSystemConnect = 0
        }
        eventSystemClient = nil
    }

    // MARK: - 감도 값 읽기 (현재 시스템 설정)

    func getCurrentTrackingSpeed() -> Double {
        // defaults read로 현재 값 확인 (더 안정적)
        let result = shell("defaults read -g com.apple.trackpad.scaling")
        return Double(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
    }

    func getCurrentScrollSpeed() -> Double {
        let result = shell("defaults read -g com.apple.scrollwheel.scaling")
        return Double(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.3125
    }

    func getCurrentClickPressure(for type: TrackpadType) -> Int {
        let domainKey: String
        switch type {
        case .internal:
            domainKey = "com.apple.AppleMultitouchTrackpad"
        case .magicTrackpad:
            domainKey = "com.apple.driver.AppleBluetoothMultitouch.trackpad"
        }

        let result = shell("defaults read \(domainKey) FirstClickThreshold")
        guard let value = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 1
        }
        return min(max(value, 0), 2)
    }

    // MARK: - 내장 트랙패드 감도 설정

    /// UI 값 0~10을 시스템 0~3으로 변환
    private func toSystemTracking(_ value: Double) -> Double {
        value.clamped(to: 0.0...10.0) / 10.0 * 3.0
    }

    /// 내장 트랙패드 추적 속도 설정 (UI 0.0 ~ 10.0)
    func setInternalTrackingSpeed(_ value: Double) {
        setGlobalTrackpadTrackingSpeed(value)
        print("✅ 내장 트랙패드 속도 설정(UI): \(value)")
    }

    /// 내장 트랙패드 스크롤 속도 설정 (UI 0.0 ~ 10.0)
    func setInternalScrollSpeed(_ value: Double) {
        setGlobalTrackpadScrollSpeed(value)
        print("✅ 내장 스크롤 속도 설정(UI): \(value)")
    }

    /// 현재 활성 트랙패드 프로필에 반영할 전역 추적 속도 설정.
    func setGlobalTrackpadTrackingSpeed(_ value: Double) {
        let systemValue = toSystemTracking(value)

        if ioHIDSystemConnect != 0 {
            let valueRef = NSNumber(value: systemValue) as CFTypeRef
            IOHIDSetAccelerationWithKey(
                ioHIDSystemConnect,
                kIOHIDTrackpadAccelerationType as CFString,
                valueRef as! Double
            )
        }

        shell_void("defaults write -g com.apple.trackpad.scaling \(systemValue)")
        print("✅ 전역 트랙패드 속도 설정: \(systemValue) (UI: \(value))")
    }

    /// 현재 활성 트랙패드 프로필에 반영할 전역 스크롤 속도 설정.
    func setGlobalTrackpadScrollSpeed(_ value: Double) {
        let systemValue = toSystemTracking(value)
        let normalized = systemValue / 3.0
        shell_void("defaults write -g com.apple.scrollwheel.scaling \(normalized)")

        if ioHIDSystemConnect != 0 {
            let valueRef = NSNumber(value: normalized) as CFTypeRef
            IOHIDSetAccelerationWithKey(
                ioHIDSystemConnect,
                kScrollAccelKey,
                valueRef as! Double
            )
        }
        print("✅ 전역 스크롤 속도 설정: \(normalized) (UI: \(value))")
    }

    // MARK: - 매직 트랙패드 감도 설정
    // 전역(mouse.scaling / trackpad.scaling)을 쓰면 블루투스 마우스나 내장 트랙패드에 영향이 가므로,
    // 매직 트랙패드에는 해당 HID 디바이스에만 IOHIDDeviceSetProperty로 설정. 전역은 건드리지 않음.

    /// 매직 트랙패드 이동 속도: 해당 HID 디바이스에만 설정. mouse.scaling 미사용(블루투스 마우스 영향 방지).
    func setMagicTrackpadSpeed(_ value: Double, device: IOHIDDevice?) {
        let systemValue = toSystemTracking(value)
        guard let device = device else {
            print("⚠️ 매직 트랙패드 HID 없음 — 이동 속도 미적용")
            return
        }
        let valueRef = NSNumber(value: systemValue) as CFTypeRef
        let service = matchingService(for: device)
        let servicePointerApplied = service.map {
            IOHIDServiceClientSetProperty($0, kIOHIDPointerAccelerationKey as CFString, valueRef)
        } ?? false
        let serviceTrackpadApplied = service.map {
            IOHIDServiceClientSetProperty($0, kIOHIDTrackpadAccelerationType as CFString, valueRef)
        } ?? false
        let devicePointerApplied = IOHIDDeviceSetProperty(device, kIOHIDPointerAccelerationKey as CFString, valueRef)
        let deviceTrackpadApplied = IOHIDDeviceSetProperty(device, kIOHIDTrackpadAccelerationType as CFString, valueRef)
        let serviceApplied = servicePointerApplied || serviceTrackpadApplied
        let deviceApplied = devicePointerApplied || deviceTrackpadApplied
        let ok = serviceApplied || deviceApplied
        print("🔎 매직 이동속도 적용 결과: service=\(service != nil) servicePointer=\(servicePointerApplied) serviceTrackpad=\(serviceTrackpadApplied) devicePointer=\(devicePointerApplied) deviceTrackpad=\(deviceTrackpadApplied)")
        if ok {
            print("✅ 매직 트랙패드 per-device 이동 속도: \(systemValue) (UI: \(value))")
        } else {
            print("⚠️ 매직 트랙패드 per-device 이동 속도 미지원(드라이버 한계). 블루투스 마우스는 영향 없음.")
        }
    }

    /// 매직 트랙패드 스크롤: 해당 HID 디바이스에만 설정. 전역 scrollwheel 미사용.
    func setMagicTrackpadScrollSpeed(_ value: Double, device: IOHIDDevice?) {
        let systemValue = toSystemTracking(value)
        let normalized = systemValue / 3.0
        guard let device = device else {
            print("⚠️ 매직 트랙패드 HID 없음 — 스크롤 속도 미적용")
            return
        }
        let valueRef = NSNumber(value: normalized) as CFTypeRef
        let service = matchingService(for: device)
        let serviceScrollApplied = service.map {
            IOHIDServiceClientSetProperty($0, kIOHIDScrollAccelerationKey as CFString, valueRef)
        } ?? false
        let serviceTrackpadScrollApplied = service.map {
            IOHIDServiceClientSetProperty($0, kIOHIDTrackpadScrollAccelerationKey as CFString, valueRef)
        } ?? false
        let deviceScrollApplied = IOHIDDeviceSetProperty(device, kIOHIDScrollAccelerationKey as CFString, valueRef)
        let deviceTrackpadScrollApplied = IOHIDDeviceSetProperty(device, kIOHIDTrackpadScrollAccelerationKey as CFString, valueRef)
        let serviceApplied = serviceScrollApplied || serviceTrackpadScrollApplied
        let deviceApplied = deviceScrollApplied || deviceTrackpadScrollApplied
        let ok = serviceApplied || deviceApplied
        print("🔎 매직 스크롤 적용 결과: service=\(service != nil) serviceScroll=\(serviceScrollApplied) serviceTrackpadScroll=\(serviceTrackpadScrollApplied) deviceScroll=\(deviceScrollApplied) deviceTrackpadScroll=\(deviceTrackpadScrollApplied)")
        if ok {
            print("✅ 매직 트랙패드 per-device 스크롤: \(normalized) (UI: \(value))")
        } else {
            print("⚠️ 매직 트랙패드 per-device 스크롤 미지원. 전역/마우스는 영향 없음.")
        }
    }

    // MARK: - 클릭 압력 (Threshold)

    func setClickPressure(_ level: Int, for type: TrackpadType) {
        // 0: Light, 1: Medium, 2: Firm
        let domainKey: String
        switch type {
        case .internal:
            domainKey = "com.apple.AppleMultitouchTrackpad"
        case .magicTrackpad:
            domainKey = "com.apple.driver.AppleBluetoothMultitouch.trackpad"
        }
        // firstClickThreshold / secondClickThreshold: 0(가벼움) ~ 2(강함)
        shell_void("defaults write \(domainKey) FirstClickThreshold \(level)")
        shell_void("defaults write \(domainKey) SecondClickThreshold \(level)")
        print("✅ 클릭 압력 설정 [\(type.displayName)]: \(level)")
    }

    // MARK: - Shell Helper

    /// Shell 명령 실행, 표준출력 반환. 실패 시 빈 문자열 또는 기본값 사용.
    @discardableResult
    func shell(_ command: String) -> String {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if task.terminationStatus != Int32(0) {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                print("⚠️ shell 실패 [\(command)]: exit=\(task.terminationStatus), stderr=\(errStr)")
            }
            return output
        } catch {
            print("❌ shell 실행 오류 [\(command)]: \(error)")
            return ""
        }
    }

    /// Shell 명령 실행 (출력 무시). 실패 시 로그만 남김.
    func shell_void(_ command: String) {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
            task.waitUntilExit()
            _ = outPipe.fileHandleForReading.readDataToEndOfFile()
            if task.terminationStatus != Int32(0) {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                print("⚠️ defaults write 실패 [\(command)]: \(errStr)")
            }
        } catch {
            print("❌ shell_void 실행 오류 [\(command)]: \(error)")
        }
    }

    private func matchingService(for device: IOHIDDevice) -> IOHIDServiceClient? {
        let client: IOHIDEventSystemClient
        if let existingClient = eventSystemClient {
            client = existingClient
        } else {
            client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
            eventSystemClient = client
        }
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return nil
        }

        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        let serialNumber = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
        let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String)?.lowercased()
        let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue

        print("🔎 HID 서비스 탐색: name=\(productName ?? "nil") serial=\(serialNumber ?? "nil") transport=\(transport ?? "nil") vid=\(vendorID.map(String.init) ?? "nil") pid=\(productID.map(String.init) ?? "nil") services=\(services.count)")
        logCandidateServicesIfNeeded(
            services: services,
            productName: productName,
            transport: transport,
            vendorID: vendorID,
            productID: productID
        )

        let matched = services.first { service in
            let serviceName = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String
            let serviceSerial = IOHIDServiceClientCopyProperty(service, kIOHIDSerialNumberKey as CFString) as? String
            let serviceTransport = (IOHIDServiceClientCopyProperty(service, kIOHIDTransportKey as CFString) as? String)?.lowercased()
            let serviceVendor = (IOHIDServiceClientCopyProperty(service, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue
            let serviceProduct = (IOHIDServiceClientCopyProperty(service, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue

            let nameMatches = (productName == nil || serviceName == productName)
            let serialMatches = (serialNumber?.isEmpty != false) || serviceSerial == nil || serviceSerial == serialNumber
            let transportMatches = (transport == nil || serviceTransport == transport)
            let vendorMatches = (vendorID == nil || serviceVendor == vendorID)
            let productMatches = (productID == nil || serviceProduct == productID)
            return nameMatches && serialMatches && transportMatches && vendorMatches && productMatches
        }
        print("🔎 HID 서비스 매칭 결과: matched=\(matched != nil)")
        return matched
    }

    private func logCandidateServicesIfNeeded(
        services: [IOHIDServiceClient],
        productName: String?,
        transport: String?,
        vendorID: Int?,
        productID: Int?
    ) {
        guard !didLogServiceCandidates else { return }
        didLogServiceCandidates = true

        let interesting = services.compactMap { service -> String? in
            let serviceName = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String
            let serviceTransport = (IOHIDServiceClientCopyProperty(service, kIOHIDTransportKey as CFString) as? String)?.lowercased()
            let serviceVendor = (IOHIDServiceClientCopyProperty(service, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue
            let serviceProduct = (IOHIDServiceClientCopyProperty(service, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
            let serviceSerial = IOHIDServiceClientCopyProperty(service, kIOHIDSerialNumberKey as CFString) as? String

            let sameVendorProduct = vendorID == serviceVendor && productID == serviceProduct
            let nameContainsTrackpad = (serviceName?.lowercased().contains("trackpad") ?? false)
            let bluetoothService = (serviceTransport?.contains("bluetooth") ?? false)
            let sameName = productName != nil && serviceName == productName
            let sameTransport = transport != nil && serviceTransport == transport

            guard sameVendorProduct || nameContainsTrackpad || bluetoothService || sameName || sameTransport else {
                return nil
            }

            return "name=\(serviceName ?? "nil") transport=\(serviceTransport ?? "nil") vid=\(serviceVendor.map(String.init) ?? "nil") pid=\(serviceProduct.map(String.init) ?? "nil") serial=\(serviceSerial ?? "nil")"
        }

        print("🔎 HID 서비스 후보 \(interesting.count)개")
        for candidate in interesting.prefix(40) {
            print("   ↳ \(candidate)")
        }
    }
}
