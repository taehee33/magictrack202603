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

// MARK: - SpeedScale (시스템 설정 칸과 동일)

check(SpeedScale.trackingStops.count == 10 && SpeedScale.scrollStops.count == 8, "칸 수: 이동 10, 스크롤 8 (시스템과 동일)")
check(SpeedScale.trackingValue(stop: SpeedScale.defaultTrackingStop) == 0.6875 && SpeedScale.scrollValue(stop: SpeedScale.defaultScrollStop) == 0.3125, "macOS 기본값 = 4칸 (0xB000, 0x5000)")
check(SpeedScale.scrollStops == [0, 0.125, 0.215, 0.3125, 0.5, 0.75, 1.0, 1.7], "스크롤 칸 값 = 시스템 sScrollSpeedFactors")
check(SpeedScale.trackingValue(stop: 1) == 0 && SpeedScale.trackingValue(stop: 7) == 1.5 && SpeedScale.trackingValue(stop: 10) == 3, "이동 칸 → 시스템 값")
check(SpeedScale.trackingStop(forSystemValue: 1.5147) == 7, "현재 매직 값 1.5147 → 7칸")
check(SpeedScale.trackingStop(forSystemValue: 5.0 * 0.3) == 7, "기존 앱 5 → 7칸 (시스템 가운데 아님)")
check(SpeedScale.scrollValue(stop: 5) == 0.5 && SpeedScale.scrollStop(forSystemValue: 0.5) == 5, "스크롤 0.5 ↔ 5칸")
check(SpeedScale.trackingValue(stop: 0) == 0 && SpeedScale.trackingValue(stop: 99) == 3, "범위 밖 칸은 양 끝으로")

// MARK: - 내 기본값 / Mac 기본값

check(TrackpadDefaults.mac == TrackpadDefaults(trackingSpeed: 4, scrollSpeed: 4, clickPressure: 1), "Mac 기본값 = 이동 4 · 스크롤 4 · 클릭 보통")
check(TrackpadDefaults(trackingSpeed: 7, scrollSpeed: 5, clickPressure: 2).summary == "이동 7칸 · 스크롤 5칸 · 클릭 단단하게", "기본값 요약 문구")

let myDefaultKeys = ["trackingSpeed", "scrollSpeed", "clickPressure"].map { TrackpadDevice.macDefaultKey(for: .magicTrackpad, suffix: $0) }
let savedDefaults = myDefaultKeys.map { UserDefaults.standard.object(forKey: $0) }
let internalBefore = TrackpadDefaults.mine(for: .internal)
let pad = TrackpadDevice(hidDevice: nil, type: .magicTrackpad, productName: "테스트")
pad.trackingSpeed = 8; pad.scrollSpeed = 6; pad.clickPressure = 0
pad.saveAsMyDefaults()
check(TrackpadDefaults.mine(for: .magicTrackpad) == TrackpadDefaults(trackingSpeed: 8, scrollSpeed: 6, clickPressure: 0), "현재 값을 내 기본값으로 저장 → 다시 읽어도 같음")
check(TrackpadDefaults.mine(for: .internal) == internalBefore, "매직 기본값 저장은 내장 기본값을 바꾸지 않음")
let rotated = TrackpadDevice(hidDevice: nil, type: .magicTrackpad, productName: "테스트")
rotated.rotation = .left90
rotated.apply(.mac)
check(rotated.trackingSpeed == 4 && rotated.scrollSpeed == 4 && rotated.clickPressure == 1 && rotated.rotation == .left90, "Mac 기본값 적용은 회전을 건드리지 않음")
check(rotated.myDefaults == pad.myDefaults, "새로 만든 장치도 저장된 내 기본값을 읽음")
for (key, value) in zip(myDefaultKeys, savedDefaults) { UserDefaults.standard.set(value, forKey: key) }

let valuesPad = TrackpadDevice(hidDevice: nil, type: .internal, productName: "테스트")
valuesPad.trackingSpeed = 6; valuesPad.scrollSpeed = 3; valuesPad.clickPressure = 2
check(valuesPad.currentValues == TrackpadDefaults(trackingSpeed: 6, scrollSpeed: 3, clickPressure: 2), "현재 값 = 이동·스크롤·클릭 (프리셋 '수정됨' 비교용)")

print(failures == 0 ? "\n모든 테스트 통과" : "\n실패 \(failures)건")
exit(failures == 0 ? 0 : 1)
