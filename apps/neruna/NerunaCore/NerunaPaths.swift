public enum NerunaPaths: Sendable {
    public static let helperPath = "/usr/local/libexec/neruna-helper"
    public static let desiredStatePath = "/usr/local/var/neruna/desired"
    public static let launchDaemonPath =
        "/Library/LaunchDaemons/app.soprog.magonote.neruna.helper.plist"
    public static let sudoersPath = "/etc/sudoers.d/neruna"
    public static let launchDaemonLabel = "app.soprog.magonote.neruna.helper"
}
