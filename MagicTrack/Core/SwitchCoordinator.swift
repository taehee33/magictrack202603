import Foundation

// MARK: - SwitchMode

enum SwitchMode: String, CaseIterable, Codable {
    case auto = "auto"
    case lockInternal = "lock_internal"
    case lockMagic = "lock_magic"

    var displayName: String {
        switch self {
        case .auto: return "자동"
        case .lockInternal: return "내장 고정"
        case .lockMagic: return "매직 고정"
        }
    }

    var shortName: String {
        switch self {
        case .auto: return "자동"
        case .lockInternal: return "내장"
        case .lockMagic: return "매직"
        }
    }

    var lockedType: TrackpadType? {
        switch self {
        case .auto: return nil
        case .lockInternal: return .internal
        case .lockMagic: return .magicTrackpad
        }
    }

    /// ⌥M 순환 순서: 자동 → 내장 고정 → 매직 고정 → 자동
    var next: SwitchMode {
        switch self {
        case .auto: return .lockInternal
        case .lockInternal: return .lockMagic
        case .lockMagic: return .auto
        }
    }

    static func lock(_ type: TrackpadType) -> SwitchMode {
        type == .internal ? .lockInternal : .lockMagic
    }
}

// MARK: - SwitchCoordinator
// 어떤 트랙패드 프로필을 적용할지 정하는 순수 로직 (IOKit 없이 테스트 가능)

enum SwitchCoordinator {
    struct State {
        var mode: SwitchMode
        var active: TrackpadType?
        var hasInternal: Bool
        var hasMagic: Bool
        /// 자동 모드에서 마지막으로 터치된 트랙패드
        var lastTouched: TrackpadType?
        /// 자동 감지를 쓸 수 없으면 자동 모드도 마지막 프로필로 고정 동작
        var autoAvailable: Bool = true

        func isConnected(_ type: TrackpadType) -> Bool {
            type == .internal ? hasInternal : hasMagic
        }
    }

    /// 연결 상태·모드에 맞는 프로필. 연결된 트랙패드가 없으면 nil
    static func target(for s: State) -> TrackpadType? {
        let preferred: TrackpadType? = s.mode.lockedType ?? s.lastTouched ?? s.active
        if let preferred, s.isConnected(preferred) { return preferred }
        if s.hasInternal { return .internal }
        if s.hasMagic { return .magicTrackpad }
        return nil
    }

    /// 새 터치가 시작됐을 때 전환할 프로필. 전환하지 않으면 nil
    /// - otherPadTouching: 다른 트랙패드에 아직 손가락이 닿아 있는지 (동시 사용 시 먼저 닿은 쪽 유지)
    static func onTouch(_ touched: TrackpadType, state s: State, otherPadTouching: Bool) -> TrackpadType? {
        guard s.mode == .auto, s.autoAvailable, s.isConnected(touched) else { return nil }
        guard touched != s.active else { return nil }
        guard !otherPadTouching else { return nil }
        return touched
    }
}
