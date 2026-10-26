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
// - 시스템 설정에 저장된 값은 바꾸지 않는다. 앱이 켜져 있는 동안만 실행 중인 값을 덮어쓰고 종료 시 되돌린다
// - 비용(0단계 실측): IOHIDSetAccelerationWithKey 1회 약 10ms, 클릭 압력 약 7ms, 이벤트 시스템 속성 0.04ms
//   → 자동 전환 시 이동 속도는 이벤트 시스템으로 즉시, 나머지는 백그라운드 큐에서 적용

final class SensitivityController {

    static let shared = SensitivityController()
    private init() {}

    private var ioHIDSystemConnect: io_connect_t = 0
    private let eventSystemClient = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    /// 느린 적용(스크롤·클릭·설정 저장)을 순서대로 처리. 밀린 요청은 가장 최근 것만 적용
    private let applyQueue = DispatchQueue(label: "magictrack.apply", qos: .userInteractive)
    private let pendingLock = NSLock()
    private var pendingProfile: (tracking: Double, scroll: Double, click: Int)?

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

    // MARK: - 단위 변환 (시스템 설정과 같은 칸 번호 → 시스템 값)

    private func toSystemTracking(_ stop: Double) -> Double { SpeedScale.trackingValue(stop: stop) }
    private func toSystemScroll(_ stop: Double) -> Double { SpeedScale.scrollValue(stop: stop) }

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

    /// 프로필 한 번에 적용. 이동 속도는 즉시(메인 스레드 0.1ms 미만), 나머지는 백그라운드
    func applyProfile(tracking: Double, scroll: Double, clickPressure: Int) {
        IOHIDEventSystemClientSetProperty(eventSystemClient, kIOHIDTrackpadAccelerationType as CFString,
                                          NSNumber(value: Int(toSystemTracking(tracking) * 65536)))
        pendingLock.lock()
        let alreadyQueued = pendingProfile != nil
        pendingProfile = (tracking, scroll, clickPressure)
        pendingLock.unlock()
        guard !alreadyQueued else { return }
        applyQueue.async { [weak self] in
            guard let self else { return }
            self.pendingLock.lock()
            let profile = self.pendingProfile
            self.pendingProfile = nil
            self.pendingLock.unlock()
            guard let profile else { return }
            self.setTrackingSpeed(profile.tracking)
            self.setScrollSpeed(profile.scroll)
            self.setClickPressure(profile.click)
        }
    }

    /// 이동 속도 (시스템 설정 칸 1~10). 실행 중인 값만 바꾸고 시스템 설정 파일(com.apple.trackpad.scaling)에는 쓰지 않는다
    func setTrackingSpeed(_ value: Double) {
        setTrackingSystemValue(toSystemTracking(value))
    }

    func setTrackingSystemValue(_ systemValue: Double) {
        if ioHIDSystemConnect != 0 || openIOHIDSystem() {
            IOHIDSetAccelerationWithKey(ioHIDSystemConnect, kIOHIDTrackpadAccelerationType as CFString, systemValue)
        }
    }

    /// 트랙패드 스크롤 속도 (손쉬운 사용 칸 1~8). 실행 중인 값만 바꾼다. 마우스 휠 설정은 건드리지 않는다
    func setScrollSpeed(_ value: Double) {
        setScrollSystemValue(toSystemScroll(value))
    }

    func setScrollSystemValue(_ systemValue: Double) {
        guard ioHIDSystemConnect != 0 || openIOHIDSystem() else { return }
        IOHIDSetAccelerationWithKey(ioHIDSystemConnect, kIOHIDTrackpadScrollAccelerationKey as CFString, systemValue)
    }

    /// 클릭 압력 0(가볍게) ~ 2(단단하게). 연결된 모든 트랙패드에 함께 적용된다.
    /// 드라이버가 시스템 설정 저장소에서 값을 읽는 구조라 저장소를 거칠 수밖에 없다 → 원래 값은 SystemBaseline이 기억했다가 되돌림
    func setClickPressure(_ level: Int) {
        if !ClickPressureBackend.setLevel(level.clamped(to: 0...2)) {
            print("⚠️ 클릭 압력 적용 불가 (시스템 설정 백엔드 없음)")
        }
    }

    // MARK: - 시스템 원래 값 (앱이 켜져 있는 동안만 덮어쓰고, 끌 때 되돌림)

    private let baselineKey = "system_baseline"
    private let overrideActiveKey = "system_override_active"

    /// 앱이 설정을 적용하기 전에 호출. 직전에 비정상 종료했다면 그때 기억한 원래 값을 그대로 쓴다
    func beginOverride() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: overrideActiveKey), defaults.dictionary(forKey: baselineKey) != nil { return }
        var scroll = 0.5
        if ioHIDSystemConnect != 0 || openIOHIDSystem() {
            IOHIDGetAccelerationWithKey(ioHIDSystemConnect, kIOHIDTrackpadScrollAccelerationKey as CFString, &scroll)
        }
        defaults.set([
            "tracking": getCurrentTrackingSpeed(),   // 시스템 설정 파일에 저장된 값
            "scroll": scroll,
            "click": getCurrentClickPressure()
        ], forKey: baselineKey)
        defaults.set(true, forKey: overrideActiveKey)
    }

    /// 앱 종료 시 호출. 시스템 설정 값으로 되돌린다 (밀린 적용이 끝난 뒤)
    func endOverride() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: overrideActiveKey), let baseline = defaults.dictionary(forKey: baselineKey) else { return }
        applyQueue.sync {}
        if let tracking = baseline["tracking"] as? Double { setTrackingSystemValue(tracking) }
        if let scroll = baseline["scroll"] as? Double { setScrollSystemValue(scroll) }
        if let click = baseline["click"] as? Int { setClickPressure(click) }
        defaults.set(false, forKey: overrideActiveKey)
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
        guard cls.responds(to: sharedSel), let backend = cls.perform(sharedSel)?.takeUnretainedValue() as? NSObject else { return nil }
        // 시스템 설정 앱과 달리 iCloud로 다른 Mac에 클릭 설정을 퍼뜨리지 않도록 동기화를 끈다
        let syncSel = NSSelectorFromString("setShouldSyncChangesToCloud:")
        if backend.responds(to: syncSel), let imp = backend.method(for: syncSel) {
            typealias SetBool = @convention(c) (NSObject, Selector, Bool) -> Void
            unsafeBitCast(imp, to: SetBool.self)(backend, syncSel, false)
        }
        return backend
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
