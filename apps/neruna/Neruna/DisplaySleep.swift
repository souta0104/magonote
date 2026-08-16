import Foundation
import NerunaCore

enum DisplaySleep {
    static func request() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: SleepDisabledCommand.pmsetPath)
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
        } catch {
            return
        }
    }
}
