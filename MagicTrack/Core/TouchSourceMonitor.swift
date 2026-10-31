import Foundation
import AppKit
import IOKit

// MARK: - TouchSourceMonitor
// MultitouchSupport(비공개 프레임워크)로 어느 트랙패드에 손가락이 닿았는지 감지한다.
// 입력 모니터링·손쉬운 사용 권한 없이 동작한다 (실측: 실측/mt/switch.log).
// 프레임워크나 심볼을 찾지 못하면 isAvailable = false 로 남고 앱은 고정 모드로 동작한다.

final class TouchSourceMonitor {
    static let shared = TouchSourceMonitor()

    /// 새 터치가 시작됐을 때 (손가락 0 → 1개 이상). 메인 큐에서 호출. 인자: 내장 트랙패드 여부
    var onTouchBegan: ((_ isBuiltIn: Bool) -> Void)?
    /// 매직 트랙패드의 센서 프레임마다 (MultitouchSupport 스레드에서 호출).
    /// 인자: 손가락 중심 이동(mm, 패드 기준 x→오른쪽, y→아래), 닿은 손가락 수, 센서 시각(초. 차이만 의미 있음)
    var onMagicFrame: ((_ dx: Double, _ dy: Double, _ fingers: Int, _ time: Double) -> Void)?
    private(set) var isAvailable = false
    private(set) var deviceCount = 0

    private typealias MTDeviceRef = UnsafeMutableRawPointer
    private typealias ContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private struct API {
        let createList: @convention(c) () -> Unmanaged<CFMutableArray>
        let isBuiltIn: @convention(c) (MTDeviceRef) -> Bool
        let register: @convention(c) (MTDeviceRef, ContactCallback) -> Void
        let unregister: @convention(c) (MTDeviceRef, ContactCallback) -> Void
        let start: @convention(c) (MTDeviceRef, Int32) -> Int32
        let stop: @convention(c) (MTDeviceRef) -> Int32
        let sensorDimensions: (@convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32)?
        let setOrientationMode: (@convention(c) (MTDeviceRef, Int32) -> Int32)?
        let setOrientation: (@convention(c) (MTDeviceRef, Int32) -> Int32)?
    }

    private let api: API?
    private var deviceList: CFMutableArray?
    /// 콜백 스레드에서 접근하는 상태 — lock으로 보호
    private let lock = NSLock()
    private var builtInDevices = Set<MTDeviceRef>()
    private var fingerCounts: [MTDeviceRef: Int32] = [:]
    private var lastCentroid: [MTDeviceRef: (x: Double, y: Double, count: Int)] = [:]
    private var sensorSizeMM: [MTDeviceRef: (width: Double, height: Double)] = [:]
    private var notifyPort: IONotificationPortRef?
    /// 매직 트랙패드 표면을 180° 뒤집을지. 드라이버가 포인터·스크롤·제스처를 모두 뒤집는다 (실측: 0°/180°만 지원)
    private var magicFlipped = false
    private var restartWorkItem: DispatchWorkItem?

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createList = dlsym(handle, "MTDeviceCreateList"),
              let isBuiltIn = dlsym(handle, "MTDeviceIsBuiltIn"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop") else {
            api = nil
            print("⚠️ MultitouchSupport 사용 불가 — 자동 전환 비활성")
            return
        }
        api = API(
            createList: unsafeBitCast(createList, to: (@convention(c) () -> Unmanaged<CFMutableArray>).self),
            isBuiltIn: unsafeBitCast(isBuiltIn, to: (@convention(c) (MTDeviceRef) -> Bool).self),
            register: unsafeBitCast(register, to: (@convention(c) (MTDeviceRef, ContactCallback) -> Void).self),
            unregister: unsafeBitCast(unregister, to: (@convention(c) (MTDeviceRef, ContactCallback) -> Void).self),
            start: unsafeBitCast(start, to: (@convention(c) (MTDeviceRef, Int32) -> Int32).self),
            stop: unsafeBitCast(stop, to: (@convention(c) (MTDeviceRef) -> Int32).self),
            sensorDimensions: dlsym(handle, "MTDeviceGetSensorSurfaceDimensions").map {
                unsafeBitCast($0, to: (@convention(c) (MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32).self)
            },
            setOrientationMode: dlsym(handle, "MTDeviceSetSurfaceOrientationMode").map {
                unsafeBitCast($0, to: (@convention(c) (MTDeviceRef, Int32) -> Int32).self)
            },
            setOrientation: dlsym(handle, "MTDeviceSetSurfaceOrientation").map {
                unsafeBitCast($0, to: (@convention(c) (MTDeviceRef, Int32) -> Int32).self)
            }
        )
    }

    // MARK: - 시작 / 종료

    func start() {
        guard api != nil else { return }
        startDevices()
        observeDeviceChanges()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func stop() {
        setMagicSurfaceFlipped(false)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
        stopDevices()
    }

    /// 지금 매직 트랙패드에 닿아 있는 손가락 수
    var magicFingerCount: Int {
        lock.lock(); defer { lock.unlock() }
        return lastCentroid.filter { !builtInDevices.contains($0.key) }.map(\.value.count).max() ?? 0
    }

    /// MultitouchSupport가 넘기는 손가락 배열(항목당 96바이트)에서 표면에 닿은 손가락의 정규화 좌표 중심을 구한다.
    /// 오프셋: state +20, normalized.pos.x +32, y +36 (공개된 역공학 자료의 MTTouch 구조)
    private static func touchingCentroid(_ fingers: UnsafeMutableRawPointer?, count: Int) -> (x: Double, y: Double, count: Int)? {
        guard let fingers, count > 0 else { return nil }
        var sx = 0.0, sy = 0.0, n = 0
        for i in 0..<min(count, 16) {
            let base = fingers + i * 96
            let state = base.loadUnaligned(fromByteOffset: 20, as: Int32.self)
            guard (3...5).contains(state) else { continue } // 3·4·5 = 표면에 닿아 있음
            sx += Double(base.loadUnaligned(fromByteOffset: 32, as: Float.self))
            sy += Double(base.loadUnaligned(fromByteOffset: 36, as: Float.self))
            n += 1
        }
        return n > 0 ? (sx / Double(n), sy / Double(n), n) : nil
    }

    /// 지금 해당 트랙패드에 손가락이 닿아 있는지
    func isTouching(builtIn: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return fingerCounts.contains { builtInDevices.contains($0.key) == builtIn && $0.value > 0 }
    }

    private func startDevices() {
        guard let api else { return }
        let list = api.createList().takeRetainedValue()
        deviceList = list
        let devices = (list as NSArray).map { Unmanaged.passUnretained($0 as AnyObject).toOpaque() }
        var sizes: [MTDeviceRef: (width: Double, height: Double)] = [:]
        for device in devices {
            var w: Int32 = 0, h: Int32 = 0
            if let dims = api.sensorDimensions, dims(device, &w, &h) == 0, w > 0, h > 0 {
                sizes[device] = (Double(w) / 100, Double(h) / 100) // 1/100 mm
            }
        }
        lock.lock()
        builtInDevices = Set(devices.filter { api.isBuiltIn($0) })
        fingerCounts = [:]
        lastCentroid = [:]
        sensorSizeMM = sizes
        lock.unlock()
        for device in devices {
            api.register(device, Self.contactCallback)
            _ = api.start(device, 0)
        }
        deviceCount = devices.count
        isAvailable = true
        applySurfaceFlip()
        print("🖐️ 터치 감지 시작: 장치 \(devices.count)개 (내장 \(builtInDevices.count)개)")
    }

    /// 매직 트랙패드(외장) 표면 방향 설정. 장치를 다시 만들 때마다 다시 적용된다
    @discardableResult
    func setMagicSurfaceFlipped(_ flipped: Bool) -> Bool {
        magicFlipped = flipped
        return applySurfaceFlip()
    }

    var supportsSurfaceFlip: Bool { api?.setOrientation != nil && api?.setOrientationMode != nil }

    @discardableResult
    private func applySurfaceFlip() -> Bool {
        guard let api, let setMode = api.setOrientationMode, let setOrientation = api.setOrientation,
              let list = deviceList else { return false }
        var ok = true
        for case let obj as AnyObject in list as NSArray {
            let device = Unmanaged.passUnretained(obj).toOpaque()
            guard !api.isBuiltIn(device) else { continue }
            let modeResult = setMode(device, magicFlipped ? 1 : 0)
            let orientationResult = setOrientation(device, magicFlipped ? 2 : 0)
            ok = ok && modeResult == 0 && orientationResult == 0
        }
        return ok
    }

    private func stopDevices() {
        guard let api, let list = deviceList else { return }
        for case let obj as AnyObject in list as NSArray {
            let device = Unmanaged.passUnretained(obj).toOpaque()
            api.unregister(device, Self.contactCallback)
            _ = api.stop(device)
        }
        deviceList = nil
        lock.lock(); fingerCounts = [:]; lock.unlock()
    }

    /// 장치 연결·해제·깨어남 뒤에는 장치 목록을 새로 만든다 (짧은 시간에 여러 번 와도 한 번만)
    private func scheduleRestart() {
        restartWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.stopDevices()
            self?.startDevices()
        }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    @objc private func handleWake() { scheduleRestart() }

    private func observeDeviceChanges() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            while case let obj = IOIteratorNext(iterator), obj != 0 { IOObjectRelease(obj) }
            guard let context else { return }
            Unmanaged<TouchSourceMonitor>.fromOpaque(context).takeUnretainedValue().scheduleRestart()
        }
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"), callback, context, &iterator)
            // 이미 있는 항목을 비워야 다음 알림이 온다
            while case let obj = IOIteratorNext(iterator), obj != 0 { IOObjectRelease(obj) }
        }
    }

    // MARK: - 접촉 콜백 (MultitouchSupport 스레드)

    private static let contactCallback: ContactCallback = { device, fingers, count, timestamp, _ in
        guard let device else { return 0 }
        shared.handleFrame(device: device, count: count, fingers: fingers, timestamp: timestamp)
        return 0
    }

    private func handleFrame(device: MTDeviceRef, count: Int32, fingers: UnsafeMutableRawPointer?, timestamp: Double) {
        let centroid = Self.touchingCentroid(fingers, count: Int(count))
        lock.lock()
        let previous = fingerCounts[device] ?? 0
        fingerCounts[device] = count
        let builtIn = builtInDevices.contains(device)
        var frameMotion = (x: 0.0, y: 0.0)
        if !builtIn {
            // 외장(매직) 패드의 손가락 중심 이동량을 mm로 누적. 손가락 수가 바뀐 프레임은 중심이 튀므로 건너뜀
            if let centroid, let last = lastCentroid[device], last.count == centroid.count {
                let size = sensorSizeMM[device] ?? (160, 115)
                frameMotion = ((centroid.x - last.x) * size.width, -(centroid.y - last.y) * size.height) // 패드 y는 아래→위, 화면 y는 위→아래
            }
            lastCentroid[device] = centroid
        }
        let onMagicFrame = builtIn ? nil : self.onMagicFrame
        lock.unlock()
        onMagicFrame?(frameMotion.x, frameMotion.y, centroid?.count ?? 0, timestamp)
        guard previous == 0, count > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onTouchBegan?(builtIn)
        }
    }
}

