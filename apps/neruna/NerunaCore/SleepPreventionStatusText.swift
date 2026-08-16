public enum SleepPreventionStatusText: Sendable {
    public static func text(for policy: SleepPreventionPolicy) -> String {
        if policy.isEnabled {
            return "オン。蓋を閉じても起きています"
        }
        return "オフ。蓋を閉じるとスリープします"
    }

    public static func symbolName(for policy: SleepPreventionPolicy) -> String {
        policy.isEnabled ? "cup.and.saucer.fill" : "moon.zzz"
    }
}
