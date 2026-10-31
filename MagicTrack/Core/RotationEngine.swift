import Foundation
import AppKit
import ApplicationServices
import IOKit.hid
import QuartzCore

// MARK: - RotationEngine
// 매직 트랙패드의 포인터 이동·드래그·스크롤을 회전시킨다 (시제품: 실측/rotate, 기록: 03·04 문서).
// - 180°: 멀티터치 드라이버의 표면 방향 설정(MTDeviceSetSurfaceOrientation)으로 처리 → 포인터·스크롤·제스처 모두, 권한 불필요
// - 90°: 드라이버가 지원하지 않아 이벤트 탭으로 처리 (손쉬운 사용 권한 필요). 두 손가락 페이지 넘기기, 세·네 손가락 쓸어넘기기도 회전
// - 대상 판별: 이벤트 비공개 필드 87 = 보낸 HID 서비스 ID (0단계 실측). 스크롤 관성 이벤트는 0으로 오므로 직전 출처를 이어 씀
// - 포인터: 원본 이벤트에 담긴 HID 데이터로 시스템이 커서를 다시 움직여 떨리므로, 원본을 버리고 회전된 새 이벤트를 보냄
// - 스크롤: 원본 이벤트의 필드와 붙어 있는 IOHID 원본을 함께 회전해 원본 그대로 보냄 (새로 만들면 앱이 페이지 넘기기로 알아보지 못함)
// - 이벤트 탭을 쓰므로 손쉬운 사용 권한 필요. 회전이 '기본'이 아닐 때만 켠다

final class RotationEngine: ObservableObject {
    static let shared = RotationEngine()

    /// 회전이 설정돼 있지만 손쉬운 사용 권한이 없어 동작하지 못하는 상태
    @Published private(set) var needsAccessibility = false
    @Published private(set) var isRunning = false
    /// 180°를 드라이버로 뒤집고 있는지 (포인터·스크롤·제스처 모두, 권한 불필요)
    @Published private(set) var driverFlipActive = false
    private(set) var rotatedEventCount = 0

    private var rotation: TrackpadRotation = .standard
    private var magicConnected = false
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    /// 네 손가락 쓸어넘기기(Dock 제어 이벤트)는 HID 단계 뒤에 만들어져 세션 단계에서 따로 받는다
    private var swipeTap: CFMachPort?
    private var swipeTapSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    // 이벤트 탭 콜백(메인 런루프)에서만 접근
    private var magicServiceIDs = Set<UInt64>()
    /// 회전된 커서 위치
    private var cursor = CGPoint.zero
    private var lastScrollFromMagic = false
    /// 마지막으로 매직 트랙패드 스크롤로 처리한 시각. 출처 없는 스크롤은 이 직후(관성)일 때만 매직으로 본다
    private var lastMagicScrollTime: CFAbsoluteTime = 0
    private static let senderField = CGEventField(rawValue: 87)!
    private static let moveTypes: Set<CGEventType> = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private static let clickTypes: Set<CGEventType> = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]

    private init() {}

    // MARK: - 설정

    func update(magicRotation: TrackpadRotation, magicConnected: Bool, trackingSpeed: Double? = nil) {
        rotation = magicRotation
        if let trackingSpeed { self.trackingSpeed = trackingSpeed }
        self.magicConnected = magicConnected
        refreshMagicServiceIDs()
        reconcile()
    }

    func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        PermissionManager.shared.openPrivacySettings(section: "Privacy_Accessibility")
    }

    func stop() {
        stopTap()
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    /// 권한을 다시 등록한 뒤 호출. 켜져 있던 이벤트 탭은 권한이 풀리면 조용히 멈추므로 끄고 다시 판단한다
    func recheckPermission() {
        stopTap()
        reconcile()
    }

    private func reconcile() {
        // 180°는 드라이버로 처리. 지원하지 않으면 이벤트 탭으로 대신 처리
        let flipByDriver = rotation == .upsideDown && TouchSourceMonitor.shared.supportsSurfaceFlip
        driverFlipActive = TouchSourceMonitor.shared.setMagicSurfaceFlipped(flipByDriver && magicConnected) && flipByDriver && magicConnected
        let wanted = (rotation != .standard && !flipByDriver && magicConnected)
        guard wanted else {
            stop()
            needsAccessibility = false
            return
        }
        guard AXIsProcessTrusted() else {
            stopTap()
            needsAccessibility = true
            // 사용자가 시스템 설정에서 허용하면 자동으로 켠다
            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    if AXIsProcessTrusted() { self?.reconcile() }
                }
            }
            return
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
        needsAccessibility = false
        startTapIfNeeded()
    }

    /// 매직 트랙패드의 HID 이벤트 서비스 ID (필드 87과 비교)
    private func refreshMagicServiceIDs() {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        var ids = Set<UInt64>()
        for service in (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? [] {
            func prop(_ key: String) -> Any? { IOHIDServiceClientCopyProperty(service, key as CFString) }
            let pairs = prop(kIOHIDDeviceUsagePairsKey) as? [[String: Any]] ?? []
            let isTouchPad = pairs.contains {
                ($0[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue == kHIDPage_Digitizer
                    && ($0[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue == kHIDUsage_Dig_TouchPad
            }
            let builtIn = (prop("Built-In") as? NSNumber)?.intValue == 1
            guard isTouchPad, !builtIn, let id = IOHIDServiceClientGetRegistryID(service) as? NSNumber else { continue }
            ids.insert(id.uint64Value)
        }
        magicServiceIDs = ids
    }

    // MARK: - 이벤트 탭

    private func startTapIfNeeded() {
        guard tap == nil else { return }
        scrollProbe = UserDefaults.standard.bool(forKey: Self.scrollProbeKey)
        var mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
        for t in Self.moveTypes.union(Self.clickTypes) { mask |= 1 << t.rawValue }
        if scrollProbe { for t in Self.probeGestureTypes { mask |= CGEventMask(1) << t } }
        mask |= CGEventMask(1) << Self.gestureType
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return Unmanaged<RotationEngine>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            print("❌ 회전용 이벤트 탭 생성 실패")
            needsAccessibility = true
            return
        }
        // 커서를 직접 옮긴 직후 하드웨어 입력이 잠시 무시되는 기본 동작을 끈다 (끄지 않으면 커서가 멈춤)
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        CGEventSource(stateID: .hidSystemState)?.localEventsSuppressionInterval = 0
        cursor = CGEvent(source: nil)?.location ?? .zero
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.tapSource = source
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.idleCheck() }
        isRunning = true
        TouchSourceMonitor.shared.onMagicFrame = { [weak self] dx, dy, fingers, time in
            let arrival = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async { self?.magicFrame(dx: dx, dy: dy, fingers: fingers, time: time, arrival: arrival) }
        }
        startSwipeTap()
        print("🔄 회전 시작: \(rotation.displayName)")
    }

    private func startSwipeTap() {
        guard swipeTap == nil else { return }
        var mask: CGEventMask = CGEventMask(1) << Self.dockControlType
        if scrollProbe { for t in Self.probeGestureTypes { mask |= CGEventMask(1) << t } }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return Unmanaged<RotationEngine>.fromOpaque(userInfo).takeUnretainedValue().handleSwipe(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            print("❌ 쓸어넘기기 회전 탭 생성 실패")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        swipeTap = tap
        swipeTapSource = source
    }

    private func stopSwipeTap() {
        if let swipeTap { CGEvent.tapEnable(tap: swipeTap, enable: false) }
        if let swipeTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), swipeTapSource, .commonModes) }
        swipeTap = nil
        swipeTapSource = nil
    }

    private func stopTap() {
        idleTimer?.invalidate()
        idleTimer = nil
        if detached { setDetached(false) }
        TouchSourceMonitor.shared.onMagicFrame = nil
        pointerActive = false
        renderLink?.invalidate()
        renderLink = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        stopSwipeTap()
        if isRunning { print("🔄 회전 중지") }
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let sender = UInt64(bitPattern: event.getIntegerValueField(Self.senderField))
        let fromMagic = magicServiceIDs.contains(sender)

        if Self.probeGestureTypes.contains(type.rawValue) {
            if scrollProbe { logProbe("hid\(type.rawValue)", event, sender: sender, fromMagic: fromMagic) }
            if fromMagic, type.rawValue == Self.gestureType {
                if event.getIntegerValueField(Self.field(Self.gestureSubtypeField)) == Self.gestureSubtypeScroll {
                    rotateGestureScroll(event)
                } else {
                    rotateTouchesInPlace(event)
                }
                if scrollProbe { logProbe("hid\(type.rawValue)→", event, sender: sender, fromMagic: fromMagic) }
            }
            return Unmanaged.passUnretained(event)
        }

        if Self.moveTypes.contains(type) {
            let dx = event.getDoubleValueField(.mouseEventDeltaX), dy = event.getDoubleValueField(.mouseEventDeltaY)
            guard fromMagic else {
                handBack(event, dx: dx, dy: dy)
                return Unmanaged.passUnretained(event)
            }
            guard dx != 0 || dy != 0 else { return Unmanaged.passUnretained(event) }
            // 커서는 손가락 센서 프레임마다 직접 옮긴다(magicFrame). macOS는 천천히 움직일 때 이동 이벤트를
            // 띄엄띄엄(실측 0.7초 공백) 보내서, 이벤트에 맞춰 옮기면 멈췄다 한꺼번에 가며 떨린다.
            // 이벤트는 '한 손가락 포인터 이동이 시작됐다'는 신호로 쓰고, 위치와 이동량만 회전된 커서에 맞춰 고친다
            if !pointerActive {
                // 손가락이 닿을 때 이미 분리해 뒀으면 커서는 그대로 있다. 아니면 macOS가 회전 안 된 방향으로 옮긴 만큼 되돌린다
                activatePointer(at: detached ? cursor : CGPoint(x: event.location.x - dx, y: event.location.y - dy))
                CGWarpMouseCursorPosition(cursor)
            } else {
                renderPointer()
            }
            setDetached(true) // macOS가 수시로 분리를 풀기 때문에 매직 이벤트마다 다시 분리한다 (참고: lazycatlabs/trackpad_rotator)
            event.location = cursor
            event.setDoubleValueField(.mouseEventDeltaX, value: pendingDelta.x)
            event.setDoubleValueField(.mouseEventDeltaY, value: pendingDelta.y)
            pendingDelta = (0, 0)
            rotatedEventCount += 1
            return Unmanaged.passUnretained(event)
        }

        if Self.clickTypes.contains(type), fromMagic {
            // 누르고 뗄 때 손가락 중심이 살짝 밀리는데, macOS처럼 그동안은 커서를 멈춰 둔다
            clickFreezeUntil = CFAbsoluteTimeGetCurrent() + 0.12
            if pointerActive { event.location = cursor }
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel {
            // 출처가 0인 스크롤(관성, 느린 스크롤의 일부)은 직전 스크롤의 출처를 따른다
            // 출처가 0인 스크롤에는 매직의 관성 스크롤뿐 아니라 Logi Options+ 같은 앱이 다시 보내는 마우스 휠도 있다.
            // 매직 스크롤 바로 뒤(0.2초 안)에 이어지는 것만 매직으로 보고, 그 밖의 출처 없는 스크롤은 그대로 둔다
            let now = CFAbsoluteTimeGetCurrent()
            if sender != 0 { lastScrollFromMagic = fromMagic }
            let continuesMagic = sender == 0 && lastScrollFromMagic && now - lastMagicScrollTime < 0.2
            guard fromMagic || continuesMagic else {
                if scrollProbe { logProbe("scroll-other", event, sender: sender, fromMagic: fromMagic) }
                return Unmanaged.passUnretained(event)
            }
            lastMagicScrollTime = now
            deactivatePointer()
            if scrollProbe { logProbe("scroll", event, sender: sender, fromMagic: fromMagic) }
            rotateScrollInPlace(event)
            if scrollProbe { logProbe("scroll→", event, sender: sender, fromMagic: fromMagic) }
            rotatedEventCount += 1
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - 커서 분리 (매직을 쓰는 동안만)

    private var detached = false
    /// 한 손가락 포인터 이동 중인지. macOS의 이동 이벤트로 켜고, 손가락 수가 바뀌거나 떼거나 스크롤하면 끈다
    private var pointerActive = false
    private var pointerFingers = 0
    private var clickFreezeUntil: CFAbsoluteTime = 0
    /// 직전 이동 이벤트 이후 프레임으로 옮긴 양 (이벤트의 이동량으로 넘긴다)
    private var pendingDelta = (x: 0.0, y: 0.0)
    private var idleTimer: Timer?

    /// 매직 트랙패드 이동 속도 (시스템 설정 칸 1~10)
    private var trackingSpeed = 7.0
    // 센서 프레임은 약 66Hz라 화면(최대 120Hz)보다 느리고, 가끔 두 개씩 붙어서 도착한다.
    // 그래서 ① 센서가 찍은 시각으로 계산하고 ② 아주 느릴 때의 센서 떨림만 거른 뒤(One Euro 필터)
    // ③ 회전·가속한 위치를 프레임 사이에서 이어 120Hz로 커서를 그린다 (한 프레임쯤 늦게 따라가는 대신 고르게 움직임)
    private struct PointerFrame { var time: Double; var x: Double; var y: Double }
    private var pointerFrames: [PointerFrame] = []
    /// 회전·가속을 거친 누적 이동 (pt)
    private var pointerOutput = (x: 0.0, y: 0.0)
    /// 커서에 이미 반영한 누적 이동 (pt)
    private var pointerRendered = (x: 0.0, y: 0.0)
    /// 손가락 위치 필터 상태 (mm, 패드 기준)
    private var fingerRaw = (x: 0.0, y: 0.0)
    private var fingerFiltered = (x: 0.0, y: 0.0)
    private var fingerVelocity = (x: 0.0, y: 0.0)
    private var lastSensorTime: Double?
    /// 도착 시각 − 센서 시각 중 가장 작은 값 (센서 시각을 지금 시각으로 바꾸는 데 씀)
    private var sensorClockOffset: Double?
    /// 화면 갱신마다 커서를 그린다. ProMotion 화면은 주사율이 24~120Hz로 바뀌므로 고정 타이머 대신 화면에 맞추고, 움직이는 동안 120Hz를 요청한다
    private var renderLink: CADisplayLink?
    private lazy var renderProxy = DisplayLinkProxy { [weak self] in self?.renderPointer() }
    /// 프레임 사이를 잇기 위해 이만큼 늦게 그린다 (센서 프레임 간격 약 15ms)
    private static let renderDelay = 0.012
    /// 멈춰 있을 때 거르는 정도(Hz, 낮을수록 강하게)와 빨라질수록 덜 거르는 정도(mm/s당 Hz)
    private static let filterMinCutoff = 3.0, filterBeta = 0.3, filterVelocityCutoff = 15.0

    private func activatePointer(at point: CGPoint) {
        pointerActive = true
        pointerFingers = TouchSourceMonitor.shared.magicFingerCount
        cursor = point
        pendingDelta = (0, 0)
        pointerFrames.removeAll()
        pointerOutput = (0, 0)
        pointerRendered = (0, 0)
        fingerRaw = (0, 0)
        fingerFiltered = (0, 0)
        fingerVelocity = (0, 0)
        lastSensorTime = nil
        if renderLink == nil {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let link = screen?.displayLink(target: renderProxy, selector: #selector(DisplayLinkProxy.tick)) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                link.add(to: .main, forMode: .common)
                renderLink = link
            }
        }
    }

    /// 손가락을 떼거나 다른 동작으로 넘어가면 남은 이동을 마저 반영하고 멈춘다
    private func deactivatePointer() {
        guard pointerActive else { return }
        moveCursor(by: (pointerOutput.x - pointerRendered.x, pointerOutput.y - pointerRendered.y))
        pointerRendered = pointerOutput
        pointerActive = false
        renderLink?.invalidate()
        renderLink = nil
    }

    private func magicFrame(dx: Double, dy: Double, fingers: Int, time: Double, arrival: CFAbsoluteTime) {
        guard isRunning else { return }
        if !pointerActive {
            // 손가락이 닿자마자 분리해 둔다. macOS의 첫 이동 이벤트 때 분리하면 그 전에 커서가 회전 안 된 방향으로 한 번 튄다
            if fingers > 0, !detached, let location = CGEvent(source: nil)?.location {
                cursor = location
                setDetached(true)
            }
            return
        }
        guard fingers > 0, fingers == pointerFingers else { deactivatePointer(); return }
        let offset = arrival - time
        // 시계가 조금씩 어긋나는 것도 따라가도록 최솟값을 아주 천천히 늘린다
        sensorClockOffset = min(offset, (sensorClockOffset ?? offset) + 0.0005)

        // 한 프레임의 이동은 8mm로 제한 (순간이동 방지)
        let travel = hypot(dx, dy)
        let scale = travel > 8 ? 8 / travel : 1
        fingerRaw.x += dx * scale
        fingerRaw.y += dy * scale
        guard let last = lastSensorTime else {
            lastSensorTime = time
            fingerFiltered = fingerRaw
            pointerFrames.append(PointerFrame(time: time, x: 0, y: 0))
            return
        }
        let dt = min(max(time - last, 1.0 / 240), 0.05)
        lastSensorTime = max(time, last)

        // One Euro 필터: 속도가 느릴수록 강하게, 빠를수록 약하게 거른다
        func alpha(_ cutoff: Double) -> Double { 1 / (1 + 1 / (2 * .pi * cutoff * dt)) }
        let previous = fingerFiltered
        let av = alpha(Self.filterVelocityCutoff)
        fingerVelocity.x += av * ((fingerRaw.x - previous.x) / dt - fingerVelocity.x)
        fingerVelocity.y += av * ((fingerRaw.y - previous.y) / dt - fingerVelocity.y)
        let speed = hypot(fingerVelocity.x, fingerVelocity.y) // mm/s
        let ap = alpha(Self.filterMinCutoff + Self.filterBeta * speed)
        fingerFiltered.x += ap * (fingerRaw.x - previous.x)
        fingerFiltered.y += ap * (fingerRaw.y - previous.y)

        // 누르고 뗄 때 손가락 중심이 살짝 밀리는데, macOS처럼 그동안은 커서를 멈춰 둔다
        if CFAbsoluteTimeGetCurrent() >= clickFreezeUntil {
            let gain = pointerGain(mmPerSecond: speed)
            let (rx, ry) = rotate(fingerFiltered.x - previous.x, fingerFiltered.y - previous.y)
            pointerOutput.x += rx * gain
            pointerOutput.y += ry * gain
        }
        pointerFrames.append(PointerFrame(time: lastSensorTime!, x: pointerOutput.x, y: pointerOutput.y))
        if pointerFrames.count > 12 { pointerFrames.removeFirst(pointerFrames.count - 12) }
    }

    /// 지금 그릴 위치(한 프레임쯤 전)를 앞뒤 프레임 사이에서 이어 구해 커서를 옮긴다
    private func renderPointer() {
        guard pointerActive, let offset = sensorClockOffset, let lastFrame = pointerFrames.last else { return }
        let t = CFAbsoluteTimeGetCurrent() - offset - Self.renderDelay
        var position = (x: lastFrame.x, y: lastFrame.y)
        if let next = pointerFrames.firstIndex(where: { $0.time > t }) {
            if next == 0 {
                position = (pointerFrames[0].x, pointerFrames[0].y)
            } else {
                let a = pointerFrames[next - 1], b = pointerFrames[next]
                let f = b.time > a.time ? (t - a.time) / (b.time - a.time) : 1
                position = (a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f)
            }
        }
        let delta = (position.x - pointerRendered.x, position.y - pointerRendered.y)
        guard delta.0 != 0 || delta.1 != 0 else { return }
        pointerRendered = position
        moveCursor(by: delta)
    }

    private func moveCursor(by delta: (Double, Double)) {
        guard delta.0 != 0 || delta.1 != 0 else { return }
        let target = clampToScreens(CGPoint(x: cursor.x + delta.0, y: cursor.y + delta.1))
        pendingDelta.x += target.x - cursor.x
        pendingDelta.y += target.y - cursor.y
        cursor = target
        setDetached(true)
        CGWarpMouseCursorPosition(target)
    }

    /// 손가락 1mm가 몇 포인트가 될지. macOS 실측 곡선(실측/rotate/calibration.txt, 속도 설정 5 기준):
    /// 10mm/s ≈ 4.5pt, 100mm/s ≈ 20pt, 250mm/s 이상 ≈ 50pt → 대략 4 + 0.17·v, 50에서 멈춤.
    /// 다른 속도 설정은 macOS 이동 속도 값(0~3)의 비율로 늘리거나 줄인다 (측정 시 값 1.5147)
    private func pointerGain(mmPerSecond v: Double) -> Double {
        let measured = min(4 + 0.17 * v, 50)
        let scale = (0.15 + SpeedScale.trackingValue(stop: trackingSpeed)) / (0.15 + 1.5147)
        return measured * scale
    }

    private func setDetached(_ value: Bool) {
        CGAssociateMouseAndMouseCursorPosition(value ? 0 : 1)
        detached = value
    }

    /// 다른 장치가 움직이면 커서를 하드웨어에 돌려준다. 분리된 동안엔 시스템이 안 움직였으므로 이 이동은 직접 반영
    private func handBack(_ event: CGEvent, dx: Double, dy: Double) {
        deactivatePointer()
        cursor = event.location
        guard detached else { return }
        let target = clampToScreens(CGPoint(x: event.location.x + dx, y: event.location.y + dy))
        CGWarpMouseCursorPosition(target)
        event.location = target
        cursor = target
        setDetached(false)
    }

    /// 매직에서 손을 떼면 다시 연결
    private func idleCheck() {
        guard detached, !TouchSourceMonitor.shared.isTouching(builtIn: false) else { return }
        deactivatePointer()
        setDetached(false)
    }

    // MARK: - 두 손가락 스크롤·페이지 넘기기
    // 원본 스크롤을 버리고 새로 만들어 보내면 앱이 두 손가락 페이지 넘기기(뒤로·앞으로)로 알아보지 못한다.
    // 그래서 원본 이벤트의 필드와 붙어 있는 IOHID 원본을 함께 회전해 원본 그대로 보낸다.
    // 문제를 살펴볼 때: defaults write com.magictrack.app rotation_scroll_probe -bool true 로 /tmp에 기록을 남긴다

    private static let scrollProbeKey = "rotation_scroll_probe"
    /// 기록용: 제스처 계열 이벤트 종류 (18 회전, 19·20 제스처 시작·끝, 29 제스처, 31 쓸기, 32 스마트 확대)
    private static let probeGestureTypes: Set<UInt32> = [18, 19, 20, 29, 31, 32]
    private static let probeLogPath = "/tmp/mmt_scroll_probe.log"
    private var scrollProbe = false
    // IOHID Scroll(6): 0 X, 1 Y. 두 축 모두 CGEvent 필드와 부호가 반대라(실측 2026-10-31: 내장 x -14 ↔ 좌우 +1.3, 매직 y -36 ↔ 위아래 +2.6)
    // 회전(선형)에 부호가 그대로 상쇄되므로 원본 값을 바로 회전하면 된다
    private static let hidScroll: UInt32 = 6

    // 비공개 필드 175·176(정규화된 이동), 177·178(장치 이동): IOHID 원본의 x·y와 같은 부호로 들어 있다 (실측 2026-10-31).
    // 앱의 페이지 넘기기(쓸기 추적)는 이 장치 이동 값을 보는 것으로 보여서 함께 회전한다
    private static let deviceDeltaFields: [(x: UInt32, y: UInt32)] = [(175, 176), (177, 178)]

    private func rotateScrollInPlace(_ event: CGEvent) {
        // CGEvent 필드: Axis1 = 위아래, Axis2 = 좌우
        let line = rotate(Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                          Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)))
        let point = rotate(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                           event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        let cgH = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let cgV = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixed = rotate(cgH, cgV)

        // IOHID 원본을 먼저 붙인다 (붙이면 일부 필드가 원본 기준으로 다시 채워지므로 필드는 그 뒤에 쓴다)
        if let fn = Self.hid, let hidEvent = fn.copy(event)?.takeRetainedValue(), fn.type(hidEvent) == Self.hidScroll {
            let xField = Self.hidField(Self.hidScroll, 0), yField = Self.hidField(Self.hidScroll, 1)
            func rotateHID(_ e: CFTypeRef) {
                let (rh, rv) = rotate(fn.getFloat(e, xField), fn.getFloat(e, yField))
                fn.setFloat(e, xField, rh)
                fn.setFloat(e, yField, rv)
            }
            rotateHID(hidEvent)
            // 자식 스크롤(가속 전 값으로 보임)도 같은 방향으로. 쓸기 추적이 이 값을 볼 수 있다
            if let children = fn.children(hidEvent)?.takeUnretainedValue() as? [CFTypeRef] {
                for child in children where fn.type(child) == Self.hidScroll { rotateHID(child) }
            }
            fn.set(event, hidEvent)
        }

        // 줄 단위 값을 쓰면 다른 값이 다시 계산되므로 줄 단위 → 점 → 고정소수점 순서로 쓴다
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(line.0.rounded()))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(line.1.rounded()))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(point.0.rounded()))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(point.1.rounded()))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed.0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed.1)

        // 장치 이동 값은 IOHID 원본과 같은 부호 (두 축 모두 반대라 그대로 회전)
        for pair in Self.deviceDeltaFields {
            let fx = Self.field(pair.x), fy = Self.field(pair.y)
            let dx = event.getDoubleValueField(fx), dy = event.getDoubleValueField(fy)
            guard dx != 0 || dy != 0 else { continue }
            let (rx, ry) = rotate(dx, dy)
            event.setDoubleValueField(fx, value: rx)
            event.setDoubleValueField(fy, value: ry)
        }
    }

    // 제스처 이벤트(종류 29)에는 손가락 위치가 담긴 IOHID Digitizer(11) 원본이 붙어 온다.
    // Chrome은 두 손가락 페이지 넘기기를 이 손가락 위치로 따라가므로, 위치(0~1, x 오른쪽·y 아래쪽, 실측 2026-10-31)도 패드 가운데를 중심으로 회전한다
    private static let gestureType: UInt32 = 29
    private static let hidDigitizer: UInt32 = 11

    private func rotateTouchesInPlace(_ event: CGEvent) {
        guard let fn = Self.hid, let hidEvent = fn.copy(event)?.takeRetainedValue(),
              fn.type(hidEvent) == Self.hidDigitizer else { return }
        let xField = Self.hidField(Self.hidDigitizer, 0), yField = Self.hidField(Self.hidDigitizer, 1)
        func rotatePosition(_ e: CFTypeRef) {
            let (rx, ry) = rotate(fn.getFloat(e, xField) - 0.5, fn.getFloat(e, yField) - 0.5)
            fn.setFloat(e, xField, rx + 0.5)
            fn.setFloat(e, yField, ry + 0.5)
        }
        rotatePosition(hidEvent)
        if let children = fn.children(hidEvent)?.takeUnretainedValue() as? [CFTypeRef] {
            for child in children where fn.type(child) == Self.hidDigitizer { rotatePosition(child) }
        }
        fn.set(event, hidEvent)
    }

    // 제스처 이벤트 중 하위 종류(110) 6은 스크롤을 한 번 더 담아 온다 (실측 2026-10-31).
    // Safari의 두 손가락 페이지 넘기기(AppKit 쓸기 추적)는 이 값을 보므로 스크롤 이벤트와 똑같이 회전한다.
    // 필드: 113·114·118 = 좌우(Double), 116 = 좌우(정수), 115·117·164 = 좌우의 Float32 비트,
    // 119·139 = 위아래(Double), 123·165 = 위아래의 Float32 비트. 두 값 모두 IOHID 원본과 부호가 반대(회전엔 상관없음)
    private static let gestureSubtypeField: UInt32 = 110
    private static let gestureSubtypeScroll: Int64 = 6

    private func rotateGestureScroll(_ event: CGEvent) {
        if let fn = Self.hid, let hidEvent = fn.copy(event)?.takeRetainedValue(), fn.type(hidEvent) == Self.hidScroll {
            let xField = Self.hidField(Self.hidScroll, 0), yField = Self.hidField(Self.hidScroll, 1)
            func rotateHID(_ e: CFTypeRef) {
                let (rh, rv) = rotate(fn.getFloat(e, xField), fn.getFloat(e, yField))
                fn.setFloat(e, xField, rh)
                fn.setFloat(e, yField, rv)
            }
            rotateHID(hidEvent)
            if let children = fn.children(hidEvent)?.takeUnretainedValue() as? [CFTypeRef] {
                for child in children where fn.type(child) == Self.hidScroll { rotateHID(child) }
            }
            fn.set(event, hidEvent)
        }
        let (x, y) = rotate(event.getDoubleValueField(Self.field(113)), event.getDoubleValueField(Self.field(119)))
        for i: UInt32 in [113, 114, 118] { event.setDoubleValueField(Self.field(i), value: x) }
        event.setIntegerValueField(Self.field(116), value: Int64(x.rounded()))
        for i: UInt32 in [115, 117, 164] { event.setIntegerValueField(Self.field(i), value: Int64(Float(x).bitPattern)) }
        for i: UInt32 in [119, 139] { event.setDoubleValueField(Self.field(i), value: y) }
        for i: UInt32 in [123, 165] { event.setIntegerValueField(Self.field(i), value: Int64(Float(y).bitPattern)) }
    }

    private func logProbe(_ label: String, _ event: CGEvent, sender: UInt64, fromMagic: Bool) {
        var hidText = "없음"
        if let fn = Self.hid, let hidEvent = fn.copy(event)?.takeRetainedValue() {
            let t = fn.type(hidEvent)
            hidText = "type=\(t) f0=\(fn.getFloat(hidEvent, Self.hidField(t, 0))) f1=\(fn.getFloat(hidEvent, Self.hidField(t, 1)))"
            if let children = fn.children(hidEvent)?.takeUnretainedValue() as? [CFTypeRef], !children.isEmpty {
                hidText += " children=\(children.map { fn.type($0) })"
                for child in children where fn.type(child) == Self.hidScroll {
                    hidText += " c6=(\(fn.getFloat(child, Self.hidField(6, 0))),\(fn.getFloat(child, Self.hidField(6, 1))))"
                }
            }
        }
        let cg = "h=\(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)) v=\(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))"
            + " phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)) momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase))"
        // 비공개 필드 중 0이 아닌 것 (내장/매직의 두 손가락 페이지 넘기기 비교용)
        var fields: [String] = []
        for i in UInt32(88)...UInt32(200) where i != 87 {
            guard let f = CGEventField(rawValue: i) else { continue }
            let v = event.getIntegerValueField(f)
            let d = event.getDoubleValueField(f)
            if v != 0 || d != 0 { fields.append(d != Double(v) ? "\(i)=\(v)/\(d)" : "\(i)=\(v)") }
        }
        let line = String(format: "%.3f %@ magic=%d sender=%llu cg[%@] hid[%@] f[%@]\n",
                          CFAbsoluteTimeGetCurrent(), label, fromMagic ? 1 : 0, sender, cg, hidText, fields.joined(separator: " "))
        // NSLog는 통합 로그에서 내용이 가려져서 파일로 남긴다
        if let handle = FileHandle(forWritingAtPath: Self.probeLogPath) ?? {
            FileManager.default.createFile(atPath: Self.probeLogPath, contents: nil)
            return FileHandle(forWritingAtPath: Self.probeLogPath)
        }() {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        }
    }

    /// 트랙패드가 시계 방향으로 놓인 각도만큼 입력을 되돌린다 (오른쪽 90°: 손가락 → 오른쪽이 패드 기준 위쪽으로 들어옴)
    // MARK: - 네 손가락 쓸어넘기기 (시험)
    // 실측(2026-10-30, 개발자 모드 기록): 매직 트랙패드의 세·네 손가락 쓸어넘기기는 Dock 제어 이벤트(종류 30)로 오고
    // 비공개 필드 110 = 23(DockSwipe), 123 = 축(1 좌우: 데스크톱 전환, 2 위아래: Mission Control),
    // 124 = 누적 진행(부호가 방향), 135 = 124의 Float32 비트, 125·126 = 이번 이동(좌우 진행, -위아래 진행), 129·130 = 끝날 때 속도.
    // 좌우 진행은 손가락 오른쪽이 음수, 위아래 진행은 위가 양수.
    // 90°에서는 축을 바꾸고 방향을 맞춰 원본 이벤트를 그대로 고쳐 보낸다 (macOS가 고친 값을 따르는지 시험)

    private static let dockControlType: UInt32 = 30
    private static func field(_ index: UInt32) -> CGEventField { CGEventField(rawValue: index)! }

    private func handleSwipe(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let swipeTap { CGEvent.tapEnable(tap: swipeTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let sender = UInt64(bitPattern: event.getIntegerValueField(Self.senderField))
        if scrollProbe, type.rawValue != Self.dockControlType {
            logProbe("session\(type.rawValue)", event, sender: sender, fromMagic: magicServiceIDs.contains(sender))
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == Self.dockControlType, magicServiceIDs.contains(sender),
              event.getIntegerValueField(Self.field(110)) == 23 else {
            return Unmanaged.passUnretained(event)
        }
        let axis = event.getIntegerValueField(Self.field(123))
        guard axis == 1 || axis == 2 else { return Unmanaged.passUnretained(event) }

        // 진행 값(좌우 h, 위아래 v) ↔ 화면 좌표(x 오른쪽+, y 아래+)
        func toScreen(_ h: Double, _ v: Double) -> (Double, Double) { (-h, -v) }
        func fromScreen(_ x: Double, _ y: Double) -> (h: Double, v: Double) { (-x, -y) }

        let progress = event.getDoubleValueField(Self.field(124))
        let (px, py) = rotate(toScreen(axis == 1 ? progress : 0, axis == 2 ? progress : 0).0,
                              toScreen(axis == 1 ? progress : 0, axis == 2 ? progress : 0).1)
        // 축은 회전으로만 정해진다 (90°면 바뀌고 180°면 그대로)
        let newAxis: Int64 = rotationSwapsAxes ? (axis == 1 ? 2 : 1) : axis
        let rotated = fromScreen(px, py)
        let newProgress = newAxis == 1 ? rotated.h : rotated.v

        // 이번 이동과 끝 속도도 같은 방향으로 (125: 좌우 진행, 126: -위아래 진행)
        func rotatePair(_ hIndex: UInt32, _ vIndex: UInt32) {
            let h = event.getDoubleValueField(Self.field(hIndex))
            let v = -event.getDoubleValueField(Self.field(vIndex))
            let (x, y) = toScreen(h, v)
            let (rx, ry) = rotate(x, y)
            let r = fromScreen(rx, ry)
            event.setDoubleValueField(Self.field(hIndex), value: r.h)
            event.setDoubleValueField(Self.field(vIndex), value: -r.v)
        }

        // macOS 27의 Dock은 이벤트에 붙은 IOHID 원본을 읽으므로 원본도 같이 회전한다
        rotateAttachedHIDEvent(of: event) { h, v in
            let (x, y) = rotate(toScreen(h, v).0, toScreen(h, v).1)
            return fromScreen(x, y)
        }
        event.setIntegerValueField(Self.field(123), value: newAxis)
        event.setDoubleValueField(Self.field(124), value: newProgress)
        event.setIntegerValueField(Self.field(135), value: Int64(Float(newProgress).bitPattern))
        rotatePair(125, 126)
        rotatePair(129, 130)
        rotatedEventCount += 1
        return Unmanaged.passUnretained(event)
    }

    private var rotationSwapsAxes: Bool { rotation == .left90 || rotation == .right90 }

    // MARK: IOHID 원본 (비공개 함수, dlsym으로 찾음. 없으면 아무것도 하지 않음)

    private typealias CopyHIDFn = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    private typealias SetHIDFn = @convention(c) (CGEvent, CFTypeRef?) -> Void
    private typealias GetTypeFn = @convention(c) (CFTypeRef) -> UInt32
    private typealias GetIntFn = @convention(c) (CFTypeRef, UInt32) -> Int
    private typealias SetIntFn = @convention(c) (CFTypeRef, UInt32, Int) -> Void
    private typealias GetFloatFn = @convention(c) (CFTypeRef, UInt32) -> Double
    private typealias SetFloatFn = @convention(c) (CFTypeRef, UInt32, Double) -> Void
    private typealias GetChildrenFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?

    private struct HIDFunctions {
        let copy: CopyHIDFn, set: SetHIDFn, type: GetTypeFn, getInt: GetIntFn, setInt: SetIntFn
        let getFloat: GetFloatFn, setFloat: SetFloatFn, children: GetChildrenFn
    }

    private static let hid: HIDFunctions? = {
        func symbol<T>(_ name: String, _ path: String) -> T? {
            guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL), let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        let skyLight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        let ioKit = "/System/Library/Frameworks/IOKit.framework/IOKit"
        guard let copy: CopyHIDFn = symbol("SLEventCopyIOHIDEvent", skyLight),
              let set: SetHIDFn = symbol("SLEventSetIOHIDEvent", skyLight),
              let type: GetTypeFn = symbol("IOHIDEventGetType", ioKit),
              let getInt: GetIntFn = symbol("IOHIDEventGetIntegerValue", ioKit),
              let setInt: SetIntFn = symbol("IOHIDEventSetIntegerValue", ioKit),
              let getFloat: GetFloatFn = symbol("IOHIDEventGetFloatValue", ioKit),
              let setFloat: SetFloatFn = symbol("IOHIDEventSetFloatValue", ioKit),
              let children: GetChildrenFn = symbol("IOHIDEventGetChildren", ioKit) else { return nil }
        return HIDFunctions(copy: copy, set: set, type: type, getInt: getInt, setInt: setInt,
                            getFloat: getFloat, setFloat: setFloat, children: children)
    }()

    // IOHID 필드 번호 = (종류 << 16) | 순번. DockSwipe(23): 1 축, 2 진행. Velocity(9): 0 X, 1 Y
    private static let hidDockSwipe: UInt32 = 23
    private static let hidVelocity: UInt32 = 9
    private static func hidField(_ type: UInt32, _ index: UInt32) -> UInt32 { type << 16 | index }

    /// 이벤트에 붙은 IOHID 원본의 축·진행(과 끝 속도)을 회전시켜 다시 붙인다.
    /// IOHID 원본은 좌우 부호가 CGEvent 필드와 반대(위아래는 같음)라서, CGEvent 기준으로 바꿔 회전한 뒤 되돌린다 (실측 2026-10-30)
    private func rotateAttachedHIDEvent(of event: CGEvent, transform cgTransform: (Double, Double) -> (h: Double, v: Double)) {
        func transform(_ hidH: Double, _ hidV: Double) -> (h: Double, v: Double) {
            let r = cgTransform(-hidH, hidV)
            return (-r.h, r.v)
        }
        guard let fn = Self.hid, let hidEvent = fn.copy(event)?.takeRetainedValue(),
              fn.type(hidEvent) == Self.hidDockSwipe else { return }

        let motionField = Self.hidField(Self.hidDockSwipe, 1)
        let progressField = Self.hidField(Self.hidDockSwipe, 2)
        let motion = fn.getInt(hidEvent, motionField)
        let progress = fn.getFloat(hidEvent, progressField)
        guard motion == 1 || motion == 2 else { return }

        let r = transform(motion == 1 ? progress : 0, motion == 2 ? progress : 0)
        let newMotion = rotationSwapsAxes ? (motion == 1 ? 2 : 1) : motion
        fn.setInt(hidEvent, motionField, newMotion)
        fn.setFloat(hidEvent, progressField, newMotion == 1 ? r.h : r.v)

        // 끝날 때 붙는 속도(자식 이벤트)도 같은 방향으로
        if let children = fn.children(hidEvent)?.takeUnretainedValue() as? [CFTypeRef] {
            for child in children where fn.type(child) == Self.hidVelocity {
                let xField = Self.hidField(Self.hidVelocity, 0), yField = Self.hidField(Self.hidVelocity, 1)
                let vx = fn.getFloat(child, xField), vy = fn.getFloat(child, yField)
                let rv = transform(vx, vy)
                fn.setFloat(child, xField, rv.h)
                fn.setFloat(child, yField, rv.v)
            }
        }
        fn.set(event, hidEvent)
    }

    private func rotate(_ x: Double, _ y: Double) -> (Double, Double) {
        switch rotation {
        case .standard: return (x, y)
        case .right90: return (-y, x)
        case .upsideDown: return (-x, -y)
        case .left90: return (y, -x)
        }
    }

    private func clampToScreens(_ p: CGPoint) -> CGPoint {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return p }
        let frames = screens.map { s -> CGRect in
            CGRect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        if frames.contains(where: { $0.contains(p) }) { return p }
        guard let nearest = frames.min(by: { hypot($0.midX - p.x, $0.midY - p.y) < hypot($1.midX - p.x, $1.midY - p.y) }) else { return p }
        return CGPoint(x: min(max(p.x, nearest.minX), nearest.maxX - 1), y: min(max(p.y, nearest.minY), nearest.maxY - 1))
    }
}

/// CADisplayLink가 Objective-C 대상을 요구해서 두는 작은 중계 객체
private final class DisplayLinkProxy: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func tick() { action() }
}
