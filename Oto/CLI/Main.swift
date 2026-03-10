import Darwin
import Foundation

@main
struct OtoCLIExecutable {
    static func main() async {
        let exitCode = await OtoCLIRunner.run(arguments: Array(CommandLine.arguments.dropFirst()))
        Darwin.exit(exitCode)
    }
}
