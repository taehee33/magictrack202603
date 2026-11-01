import Foundation
import IOKit
import Combine
import UserNotifications

// MARK: - BatteryMonitor
// 매직 트랙패드 배터리 잔량을 읽어 보여 주고, 기준 아래로 떨어지면 알림을 보낸다.
//
// 실측(macOS 27, 매직 트랙패드 USB-C 0x0324 블루투스) 근거:
// - 잔량은 HID 장치가 아니라 AppleDeviceManagementHIDEventService의 BatteryPercent 속성에 있음
// - 그 서비스의 SerialNumber = 매직 트랙패드 HID 장치의 SerialNumber (블루투스 주소)
// - 잔량은 변할 때 알림이 따로 오지 않으므로 몇 분마다 다시 읽는다

final class BatteryMonitor: NSObject, ObservableObject {
    static let shared = BatteryMonitor()

    static let alertEnabledKey = "low_battery_alert_enabled"
    static let thresholdKey = "low_battery_threshold"
    static let thresholdOptions = [10, 20, 30]
    private static let alertedStageKey = "low_battery_alerted_stage"
    private static let pollInterval: TimeInterval = 120

    /// 매직 트랙패드 잔량 (0~100). 매직이 없거나 읽지 못하면 nil
    @Published private(set) var percent: Int?
    /// 알림 권한을 거부해 알림을 보낼 수 없는 상태
    @Published private(set) var notificationsDenied = false

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    private override init() {
        defaults.register(defaults: [Self.alertEnabledKey: true, Self.thresholdKey: 20])
        super.init()
    }

    var threshold: Int { defaults.integer(forKey: Self.thresholdKey) }
    var isLow: Bool { percent.map { $0 <= threshold } ?? false }

    /// 앱 시작 시 호출. 매직 트랙패드가 바뀔 때와 몇 분마다 다시 읽는다
    func start() {
        UNUserNotificationCenter.current().delegate = self
        refreshNotificationStatus()
        TrackpadManager.shared.$magicTrackpad
            .receive(on: DispatchQueue.main)
            .sink { [weak self] magic in
                // 연결 직후에는 배터리 서비스가 아직 안 올라왔을 수 있어 조금 뒤에 한 번 더 읽는다
                self?.refresh(for: magic)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self?.refresh() }
            }
            .store(in: &cancellables)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    func refresh() {
        refresh(for: TrackpadManager.shared.magicTrackpad)
    }

    private func refresh(for magic: TrackpadDevice?) {
        guard let magic else {
            percent = nil
            return
        }
        percent = Self.readBatteryPercent(serialNumber: magic.serialNumber, vendorID: magic.vendorID, productID: magic.productID)
        evaluateAlert()
    }

    /// 기준을 바꿨을 때 등 바로 다시 판단
    func evaluateAlert() {
        guard let percent else { return }
        let alerted = BatteryAlertStage(rawValue: defaults.integer(forKey: Self.alertedStageKey)) ?? .none
        let result = BatteryAlertPolicy.evaluate(percent: percent, threshold: threshold, alerted: alerted)
        defaults.set(result.stage.rawValue, forKey: Self.alertedStageKey)
        guard let stage = result.notify, defaults.bool(forKey: Self.alertEnabledKey) else { return }
        postLowBatteryNotification(percent: percent, stage: stage)
    }

    // MARK: - IOKit

    /// AppleDeviceManagementHIDEventService 중 이 장치의 BatteryPercent. 시리얼이 없으면 VID/PID로 찾는다
    static func readBatteryPercent(serialNumber: String, vendorID: Int, productID: Int) -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var fallback: Int?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let level = (property("BatteryPercent") as? NSNumber)?.intValue else { continue }
            let serial = property("SerialNumber") as? String ?? ""
            if !serialNumber.isEmpty, serial.caseInsensitiveCompare(serialNumber) == .orderedSame {
                return level.clamped(to: 0...100)
            }
            if fallback == nil,
               (property("VendorID") as? NSNumber)?.intValue == vendorID,
               (property("ProductID") as? NSNumber)?.intValue == productID {
                fallback = level.clamped(to: 0...100)
            }
        }
        return serialNumber.isEmpty ? fallback : nil
    }

    // MARK: - 알림

    private func postLowBatteryNotification(percent: Int, stage: BatteryAlertStage) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.notificationsDenied = !granted }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = stage == .critical
                ? String(localized: "매직 트랙패드 배터리가 거의 없어요")
                : String(localized: "매직 트랙패드 배터리가 부족해요")
            content.body = String(localized: "남은 배터리 \(percent)%. 충전해 주세요.")
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "low_battery", content: content, trigger: nil))
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async { self?.notificationsDenied = settings.authorizationStatus == .denied }
        }
    }
}

extension BatteryMonitor: UNUserNotificationCenterDelegate {
    /// 앱이 앞에 있을 때도 배너를 보여 준다
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
