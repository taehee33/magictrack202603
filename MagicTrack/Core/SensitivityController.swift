import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem
import ObjectiveC

// MARK: - SensitivityController
// 트랙패드 이동 속도·스크롤 속도·클릭 압력을 시스템에 즉시 적용하는 컨트롤러.
// 셸(defaults) 실행 없이 IOKit / CFPreferences / 시스템 설정 백엔드를 직접 호출한다.
//
// 실측(macOS 27.0.1) 근거:
// - 이동 속도: IOHIDSetAccelerationWithKey(HIDTrackpadAcceleration) 즉시 반영
// - 스크롤: IOHIDSetAccelerationWithKey(HIDTrackpadScrollAcceleration) 트랙패드에만 즉시 반영 (마우스 영향 없음)
// - 클릭 압력: defaults 기록은 반영 안 됨 → 시스템 설정 앱과 같은 MTTGestureBackEnd 사용 시 즉시 반영

final class SensitivityController {

    static let shared = SensitivityController()
    private init() {}

    private var ioHIDSystemConnect: io_connect_t = 0

    func openIOHIDSystem() -> Bool {
        guard ioHIDSystemConnect == 0 else { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else {
            print("❌ IOHIDSystem 서비스를 찾을 수 없습니다.")
            return false
        }
        let result = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &ioHIDSystemConnect)
        IOObjectRelease(service)
        if result != kIOReturnSuccess {
            print("❌ IOHIDSystem 연결 실패: \(result)")
            return false
        }
        return true
    }

    func closeIOHIDSystem() {
        if ioHIDSystemConnect != 0 {
            IOServiceClose(ioHIDSystemConnect)
            ioHIDSystemConnect = 0
        }
    }

    // MARK: - 단위 변환 (UI 0~10)

    /// UI 이동 속도 0~10 → 시스템 trackpad.scaling 0~3
    private func toSystemTracking(_ value: Double) -> Double {
        value.clamped(to: 0.0...10.0) / 10.0 * 3.0
    }

    /// UI 스크롤 속도 0~10 → 시스템 스크롤 가속 0~1
    private func toSystemScroll(_ value: Double) -> Double {
        value.clamped(to: 0.0...10.0) / 10.0
    }

    // MARK: - 현재 시스템 값 읽기

    func getCurrentTrackingSpeed() -> Double {
        (CFPreferencesCopyValue(Self.trackingPrefKey, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber)?.doubleValue ?? 1.0
    }

    /// 트랙패드 스크롤 가속 (0~1). 읽지 못하면 보통(0.5)
    func getCurrentScrollSpeed() -> Double {
        guard ioHIDSystemConnect != 0 || openIOHIDSystem() else { return 0.5 }
        var value = 0.0
        let result = IOHIDGetAccelerationWithKey(ioHIDSystemConnect, kIOHIDTrackpadScrollAccelerationKey as CFString, &value)
        return result == kIOReturnSuccess ? value : 0.5
    }

    func getCurrentClickPressure() -> Int {
        if let level = ClickPressureBackend.currentLevel() { return level.clamped(to: 0...2) }
        let value = CFPreferencesCopyAppValue("FirstClickThreshold" as CFString, "com.apple.AppleMultitouchTrackpad" as CFString) as? NSNumber
        return (value?.intValue ?? 1).clamped(to: 0...2)
    }

    // MARK: - 적용

    /// 이동 속도 (UI 0~10). 즉시 반영 + 재부팅 후에도 유지되도록 전역 설정에도 기록
    func setTrackingSpeed(_ value: Double) {
        let systemValue = toSystemTracking(value)
        if ioHIDSystemConnect != 0 || openIOHIDSystem() {
            IOHIDSetAccelerationWithKey(ioHIDSystemConnect, kIOHIDTrackpadAccelerationType as CFString, systemValue)
        }
        CFPreferencesSetValue(Self.trackingPrefKey, NSNumber(value: systemValue), kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// 트랙패드 스크롤 속도 (UI 0~10). 마우스 휠 설정(scrollwheel.scaling)은 건드리지 않는다
    func setScrollSpeed(_ value: Double) {
        guard ioHIDSystemConnect != 0 || openIOHIDSystem() else { return }
        IOHIDSetAccelerationWithKey(ioHIDSystemConnect, kIOHIDTrackpadScrollAccelerationKey as CFString, toSystemScroll(value))
    }

    /// 클릭 압력 0(가볍게) ~ 2(단단하게). 연결된 모든 트랙패드에 함께 적용된다
    func setClickPressure(_ level: Int) {
        let level = level.clamped(to: 0...2)
        if ClickPressureBackend.setLevel(level) { return }
        // 백엔드를 쓸 수 없는 macOS에서는 설정 파일에만 기록 (재로그인 후 반영)
        for domain in ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"] {
            for key in ["FirstClickThreshold", "SecondClickThreshold"] {
                CFPreferencesSetAppValue(key as CFString, NSNumber(value: level), domain as CFString)
            }
            CFPreferencesAppSynchronize(domain as CFString)
        }
        print("⚠️ 클릭 압력 즉시 적용 불가 — 설정 파일에만 기록")
    }

    private static let trackingPrefKey = "com.apple.trackpad.scaling" as CFString
}

// MARK: - ClickPressureBackend
// 시스템 설정 › 트랙패드의 '클릭' 슬라이더가 쓰는 PreferencePanesSupport.framework의 MTTGestureBackEnd를
// Objective-C 런타임으로 호출한다 (비공개 API — 없으면 nil/false로 대체 경로 사용).

private enum ClickPressureBackend {
    private static let backend: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport", RTLD_NOW)
        guard let cls = NSClassFromString("MTTGestureBackEnd") as? NSObject.Type else { return nil }
        let sharedSel = NSSelectorFromString("sharedInstance")
        guard cls.responds(to: sharedSel) else { return nil }
        return cls.perform(sharedSel)?.takeUnretainedValue() as? NSObject
    }()

    static func currentLevel() -> Int? {
        let sel = NSSelectorFromString("clickPressureLevel")
        guard let backend, backend.responds(to: sel), let imp = backend.method(for: sel) else { return nil }
        typealias Getter = @convention(c) (NSObject, Selector) -> Int
        return unsafeBitCast(imp, to: Getter.self)(backend, sel)
    }

    static func setLevel(_ level: Int) -> Bool {
        let sel = NSSelectorFromString("setClickPressureLevel:")
        guard let backend, backend.responds(to: sel), let imp = backend.method(for: sel) else { return false }
        typealias Setter = @convention(c) (NSObject, Selector, Int) -> Void
        unsafeBitCast(imp, to: Setter.self)(backend, sel, level)
        return true
    }
}
