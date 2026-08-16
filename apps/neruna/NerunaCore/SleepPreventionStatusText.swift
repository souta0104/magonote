public enum SleepPreventionStatusText: Sendable {
    public static func text(for policy: SleepPreventionPolicy) -> String {
        if !policy.isEnabled {
            return "オフ。蓋を閉じるとスリープします"
        }
        if policy.isOnACPower {
            return "電源接続中。蓋を閉じても起きています"
        }
        return "電池駆動中。蓋を閉じるとスリープします"
    }

    public static func symbolName(for policy: SleepPreventionPolicy) -> String {
        if !policy.isEnabled {
            return "moon.zzz"
        }
        return policy.isOnACPower ? "cup.and.saucer.fill" : "cup.and.saucer"
    }
}
