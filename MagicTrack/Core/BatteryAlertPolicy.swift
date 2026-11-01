import Foundation

// MARK: - BatteryAlertPolicy
// 매직 트랙패드 배터리 부족 알림 규칙 (IOKit 없이 테스트할 수 있게 BatteryMonitor에서 분리)

/// 알림 단계: 기준 아래(부족) → 5% 이하(거의 없음). 기준보다 충분히 올라가면(충전) 처음으로 돌아간다
enum BatteryAlertStage: Int {
    case none = 0
    case low = 1
    case critical = 2
}

enum BatteryAlertPolicy {
    static let criticalPercent = 5
    /// 기준 바로 위에서 오르내릴 때 알림이 반복되지 않도록, 이만큼 더 올라가야 다시 알린다
    static let rearmMargin = 5

    /// 지금 잔량에 맞는 단계와, 새로 알려야 할 단계(없으면 nil)
    static func evaluate(percent: Int, threshold: Int, alerted: BatteryAlertStage) -> (stage: BatteryAlertStage, notify: BatteryAlertStage?) {
        if percent > threshold + rearmMargin { return (.none, nil) }
        let current: BatteryAlertStage = percent <= criticalPercent ? .critical : (percent <= threshold ? .low : .none)
        guard current.rawValue > alerted.rawValue else { return (alerted, nil) }
        return (current, current)
    }
}

// MARK: - BatteryLevel 표시

enum BatteryLevel {
    /// SF Symbol (battery.0percent ~ battery.100percent)
    static func symbolName(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
