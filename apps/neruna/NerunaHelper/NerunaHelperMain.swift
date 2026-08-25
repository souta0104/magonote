import Foundation
import NerunaCore

@main
struct NerunaHelperMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try HelperRuntime().run(arguments: arguments)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
