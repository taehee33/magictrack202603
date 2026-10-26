// 장치 판별·전환 규칙 단위 테스트 (Xcode 테스트 타깃 없이 실행)
// 실행: Tests/run_tests.sh
import Foundation

var failures = 0
func check(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
    if condition { print("✓ \(name)") } else { print("✗ \(name) (\(line))"); failures += 1 }
}

// MARK: - DeviceClassifier (실측값 기준)

let touchPadPairs: [(page: Int, usage: Int)] = [(1, 2), (1, 1), (13, 5), (65280, 12)]
let builtIn = HIDDeviceSnapshot(productName: "Apple Internal Keyboard / Trackpad", transport: "FIFO", vendorID: 0, productID: 0, isBuiltIn: true, usagePairs: touchPadPairs)
let magicBT = HIDDeviceSnapshot(productName: "태희의 Magic Trackpad", transport: "Bluetooth", vendorID: 0x4C, productID: 0x324, isBuiltIn: false, usagePairs: touchPadPairs)
let magicRenamed = HIDDeviceSnapshot(productName: "태희 패드", transport: "Bluetooth", vendorID: 0x4C, productID: 0x324, isBuiltIn: false, usagePairs: touchPadPairs)
let magicUSB = HIDDeviceSnapshot(productName: "Magic Trackpad", transport: "USB", vendorID: 0x5AC, productID: 0x324, isBuiltIn: false, usagePairs: touchPadPairs)
let thirdPartyPad = HIDDeviceSnapshot(productName: "Some Trackpad", transport: "Bluetooth", vendorID: 0x1234, productID: 1, isBuiltIn: false, usagePairs: touchPadPairs)
let mxMaster = HIDDeviceSnapshot(productName: "MX Master 3S", transport: "Bluetooth Low Energy", vendorID: 0x46D, productID: 0xB034, isBuiltIn: false, usagePairs: [(1, 2), (1, 1), (65347, 514)])
let keyboard = HIDDeviceSnapshot(productName: "G715 Keyboard", transport: "Bluetooth Low Energy", vendorID: 0x46D, productID: 0xB368, isBuiltIn: false, usagePairs: [(1, 6), (1, 2), (1, 1)])
let backlight = HIDDeviceSnapshot(productName: "Keyboard Backlight", transport: "USB", vendorID: 0x5AC, productID: 0, isBuiltIn: true, usagePairs: [(65280, 15)])

check(DeviceClassifier.classify(builtIn) == .internalTrackpad, "내장 트랙패드(FIFO, Built-In)")
check(DeviceClassifier.classify(magicBT) == .magicTrackpad, "블루투스 매직 트랙패드(VID 0x4C)")
check(DeviceClassifier.classify(magicRenamed) == .magicTrackpad, "이름을 바꾼 매직 트랙패드")
check(DeviceClassifier.classify(magicUSB) == .magicTrackpad, "USB 매직 트랙패드는 내장이 아님")
check(DeviceClassifier.classify(thirdPartyPad) == .otherTrackpad, "서드파티 트랙패드는 매직이 아님")
check(DeviceClassifier.classify(mxMaster) == .mouse, "MX Master는 마우스")
check(DeviceClassifier.classify(keyboard) == .ignored, "포인터 겸용 키보드는 제외")
check(DeviceClassifier.classify(backlight) == .ignored, "키보드 백라이트는 제외")

// MARK: - SwitchCoordinator

typealias S = SwitchCoordinator.State
let both = S(mode: .auto, active: .internal, hasInternal: true, hasMagic: true, lastTouched: .internal)

check(SwitchCoordinator.onTouch(.magicTrackpad, state: both, otherPadTouching: false) == .magicTrackpad, "자동: 매직 터치 → 매직")
check(SwitchCoordinator.onTouch(.internal, state: both, otherPadTouching: false) == nil, "자동: 이미 적용 중인 패드는 다시 적용 안 함")
check(SwitchCoordinator.onTouch(.magicTrackpad, state: both, otherPadTouching: true) == nil, "자동: 다른 패드에 손이 있으면 먼저 닿은 쪽 유지")
var locked = both; locked.mode = .lockInternal
check(SwitchCoordinator.onTouch(.magicTrackpad, state: locked, otherPadTouching: false) == nil, "고정: 터치 무시")
var unavailable = both; unavailable.autoAvailable = false
check(SwitchCoordinator.onTouch(.magicTrackpad, state: unavailable, otherPadTouching: false) == nil, "감지 불가: 자동 전환 안 함")
var noMagic = both; noMagic.hasMagic = false
check(SwitchCoordinator.onTouch(.magicTrackpad, state: noMagic, otherPadTouching: false) == nil, "등록 안 된 패드 터치는 무시")

var lockMagic = both; lockMagic.mode = .lockMagic
check(SwitchCoordinator.target(for: lockMagic) == .magicTrackpad, "매직 고정 → 매직")
lockMagic.hasMagic = false
check(SwitchCoordinator.target(for: lockMagic) == .internal, "매직 고정인데 매직 끊김 → 내장으로 임시 전환")
var autoMagicLast = both; autoMagicLast.lastTouched = .magicTrackpad
check(SwitchCoordinator.target(for: autoMagicLast) == .magicTrackpad, "자동: 재실행 시 마지막 터치 패드")
check(SwitchCoordinator.target(for: S(mode: .auto, active: nil, hasInternal: false, hasMagic: false, lastTouched: nil)) == nil, "연결된 패드 없음 → nil")
check(SwitchMode.auto.next == .lockInternal && SwitchMode.lockInternal.next == .lockMagic && SwitchMode.lockMagic.next == .auto, "⌥M 순환 순서")

print(failures == 0 ? "\n모든 테스트 통과" : "\n실패 \(failures)건")
exit(failures == 0 ? 0 : 1)
