import Foundation

public enum SleepPreventionStatusText: Sendable {
    public static func text(for policy: SleepPreventionPolicy) -> String {
        switch policy.reason {
        case .off:
            return "オフ。蓋を閉じるとスリープします"
        case .keepingAwake:
            if let remaining = remainingText(policy.remainingDuration) {
                return "オン。蓋を閉じても起きています。\(remaining)"
            }
            return "オン。蓋を閉じても起きています"
        case .batteryLow:
            if let percent = policy.power.batteryPercent {
                return "電池 \(percent)%。スリープします"
            }
            return "電池が少ないのでスリープします"
        case .durationExpired:
            return "制限時間を過ぎたのでスリープします"
        }
    }

    public static func symbolName(for policy: SleepPreventionPolicy) -> String {
        policy.shouldKeepAwake ? "cup.and.saucer.fill" : "moon.zzz"
    }

    private static func remainingText(_ remaining: TimeInterval?) -> String? {
        guard let remaining, remaining > 0 else {
            return nil
        }
        let minutes = Int(remaining.rounded(.up)) / 60
        if minutes >= 120 {
            return "あと \(minutes / 60) 時間で寝る"
        }
        if minutes >= 1 {
            return "あと \(minutes) 分で寝る"
        }
        return "まもなく寝る"
    }
}
