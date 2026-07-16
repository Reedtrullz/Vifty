import Darwin
import Foundation
import ViftyFanControlSafety

enum LockHelperMode: String {
    case attempt
    case holdUntilReleased
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3,
      let mode = LockHelperMode(rawValue: arguments[0]),
      let ownerID = uid_t(arguments[2]) else {
    fail("Usage: ViftyLockTestHelper attempt|holdUntilReleased <lock-path> <owner-uid> [ready-path release-path]", code: 64)
}

let lockURL = URL(fileURLWithPath: arguments[1], isDirectory: false)
let guardURL = ProcessInfo.processInfo.environment["VIFTY_LOCK_TEST_GUARD_PATH"]
    .map { URL(fileURLWithPath: $0, isDirectory: false) }
do {
    let lock = try FanControlExclusiveLock(
        url: lockURL,
        guardURL: guardURL,
        requiredOwnerID: ownerID
    )
    switch mode {
    case .attempt:
        lock.release()
        exit(0)
    case .holdUntilReleased:
        guard arguments.count == 5 else { fail("holdUntilReleased requires ready and release paths", code: 64) }
        let readyURL = URL(fileURLWithPath: arguments[3], isDirectory: false)
        let releaseURL = URL(fileURLWithPath: arguments[4], isDirectory: false)
        try Data("ready".utf8).write(to: readyURL, options: .atomic)
        while !FileManager.default.fileExists(atPath: releaseURL.path) {
            usleep(10_000)
        }
        _ = lock.url
        _exit(0)
    }
} catch FanControlExclusiveLockError.alreadyOwned {
    exit(75)
} catch {
    fail(error.localizedDescription)
}
