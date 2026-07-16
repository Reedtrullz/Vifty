import Darwin
import Foundation
import ViftyHelperSupport

let result = await HelperCommandRunner.live.run(
    arguments: Array(CommandLine.arguments.dropFirst())
)
if !result.standardOutput.isEmpty {
    FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
}
if !result.standardError.isEmpty {
    FileHandle.standardError.write(Data(result.standardError.utf8))
}
exit(result.exitCode)
