import Darwin
import Foundation
import ViftyCore

public enum FanControlExclusiveLockError: Error, Equatable, LocalizedError {
    case unsafePath(String)
    case alreadyOwned
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .unsafePath(let reason): "Unsafe fan-control lock path: \(reason)"
        case .alreadyOwned: "Another process owns the Vifty fan-control safety lock."
        case .ioFailure(let reason): "Fan-control lock I/O failed: \(reason)"
        }
    }
}

/// Process-scoped `fcntl` exclusion shared by the daemon and offline Auto-only
/// maintenance. Both the lock file descriptor and its root-to-leaf directory
/// anchor are retained for the lifetime of the lock. Path replacement makes
/// `isHeld` fail closed instead of silently switching this owner to a new inode.
public final class FanControlExclusiveLock: @unchecked Sendable {
    public static let defaultURL = FanControlJournalStore.defaultDirectoryURL
        .appendingPathComponent("writer.lock", isDirectory: false)
    public static let defaultGuardURL = FanControlJournalStore.defaultDirectoryURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".vifty-fan-control-writer.guard", isDirectory: false)

    public let url: URL
    private let descriptor: Int32
    private let registryKey: String
    private let secureDirectory: SecureStorageDirectory
    private let fileName: String
    private let guardDescriptor: Int32
    private let guardDirectory: SecureStorageDirectory
    private let guardFileName: String
    private let stateLock = NSLock()
    private var ownsLock = true

    public var isHeld: Bool {
        stateLock.withLock {
            guard ownsLock else { return false }
            do {
                try secureDirectory.validateOpenRegularFileDescriptor(
                    descriptor,
                    named: fileName
                )
                try guardDirectory.validateOpenRegularFileDescriptor(
                    guardDescriptor,
                    named: guardFileName
                )
                return true
            } catch {
                return false
            }
        }
    }

    public init(
        url: URL = FanControlExclusiveLock.defaultURL,
        guardURL: URL? = nil,
        requiredOwnerID: uid_t = 0
    ) throws {
        self.url = url
        let fileName = url.lastPathComponent
        guard !fileName.isEmpty else {
            throw FanControlExclusiveLockError.unsafePath("lock filename is empty")
        }
        // POSIX record locks are process-scoped, so the same process must never
        // open the lock inode through a differently cased/path-aliased spelling.
        // A conservative normalized key prevents that before any descriptor is
        // opened; false collisions on a case-sensitive volume are fail-closed.
        let registryKey = url.resolvingSymlinksInPath().standardizedFileURL.path
            .precomposedStringWithCanonicalMapping
            .lowercased()
        guard FanControlExclusiveLockRegistry.shared.reserve(registryKey) else {
            throw FanControlExclusiveLockError.alreadyOwned
        }
        var shouldReleaseRegistry = true
        defer {
            if shouldReleaseRegistry {
                FanControlExclusiveLockRegistry.shared.release(registryKey)
            }
        }

        let directory: SecureStorageDirectory
        do {
            guard let opened = try SecureStorageDirectory.open(
                directoryURL: url.deletingLastPathComponent(),
                requiredOwnerID: requiredOwnerID,
                createIfMissing: true
            ) else {
                throw FanControlExclusiveLockError.ioFailure("could not create lock directory")
            }
            directory = opened
        } catch {
            throw Self.map(error)
        }

        let lockDirectoryURL = url.deletingLastPathComponent()
        let resolvedGuardURL: URL
        if let guardURL {
            resolvedGuardURL = guardURL
        } else if url.standardizedFileURL == Self.defaultURL.standardizedFileURL {
            // Keep the production guard outside `/Library/Application Support/Vifty`.
            // Replacing the app-managed state tree must not create a second
            // writer-lock universe while an old daemon still owns its inode.
            resolvedGuardURL = Self.defaultGuardURL
        } else {
            resolvedGuardURL = lockDirectoryURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(lockDirectoryURL.lastPathComponent).\(fileName).guard",
                    isDirectory: false
                )
        }
        let guardFileName = resolvedGuardURL.lastPathComponent
        guard !guardFileName.isEmpty else {
            throw FanControlExclusiveLockError.unsafePath("guard filename is empty")
        }
        let guardDirectory: SecureStorageDirectory
        do {
            guard let opened = try SecureStorageDirectory.open(
                directoryURL: resolvedGuardURL.deletingLastPathComponent(),
                requiredOwnerID: requiredOwnerID,
                requiresExactMode: false,
                createIfMissing: true
            ) else {
                throw FanControlExclusiveLockError.ioFailure("could not open lock guard directory")
            }
            guardDirectory = opened
        } catch {
            throw Self.map(error)
        }

        let guardDescriptor: Int32
        do {
            let candidate = try guardDirectory.openRegularFileDescriptor(
                named: guardFileName,
                createIfMissing: true
            )
            do {
                try Self.acquireKernelLock(candidate, context: "acquire directory guard lock")
                try guardDirectory.validateOpenRegularFileDescriptor(
                    candidate,
                    named: guardFileName
                )
                guardDescriptor = candidate
            } catch {
                Self.releaseKernelLock(candidate)
                close(candidate)
                throw error
            }
        } catch {
            throw Self.map(error)
        }

        let descriptor: Int32
        do {
            let candidate = try directory.openRegularFileDescriptor(
                named: fileName,
                createIfMissing: true
            )
            do {
                try Self.acquireKernelLock(candidate, context: "acquire writer lock")
                try directory.validateOpenRegularFileDescriptor(candidate, named: fileName)
                descriptor = candidate
            } catch {
                Self.releaseKernelLock(candidate)
                close(candidate)
                throw error
            }
        } catch {
            Self.releaseKernelLock(guardDescriptor)
            close(guardDescriptor)
            throw Self.map(error)
        }

        self.descriptor = descriptor
        self.registryKey = registryKey
        self.secureDirectory = directory
        self.fileName = fileName
        self.guardDescriptor = guardDescriptor
        self.guardDirectory = guardDirectory
        self.guardFileName = guardFileName
        shouldReleaseRegistry = false
    }

    deinit {
        release()
    }

    public func release() {
        stateLock.withLock {
            guard ownsLock else { return }
            Self.releaseKernelLock(descriptor)
            close(descriptor)
            Self.releaseKernelLock(guardDescriptor)
            close(guardDescriptor)
            FanControlExclusiveLockRegistry.shared.release(registryKey)
            ownsLock = false
        }
    }

    private static func acquireKernelLock(_ descriptor: Int32, context: String) throws {
        var kernelLock = flock()
        kernelLock.l_start = 0
        kernelLock.l_len = 0
        kernelLock.l_pid = 0
        kernelLock.l_type = Int16(F_WRLCK)
        kernelLock.l_whence = Int16(SEEK_SET)
        guard fcntl(descriptor, F_SETLK, &kernelLock) == 0 else {
            if errno == EACCES || errno == EAGAIN {
                throw FanControlExclusiveLockError.alreadyOwned
            }
            throw posixFailure(context)
        }
    }

    private static func releaseKernelLock(_ descriptor: Int32) {
        var kernelLock = flock()
        kernelLock.l_start = 0
        kernelLock.l_len = 0
        kernelLock.l_pid = 0
        kernelLock.l_type = Int16(F_UNLCK)
        kernelLock.l_whence = Int16(SEEK_SET)
        _ = fcntl(descriptor, F_SETLK, &kernelLock)
    }

    private static func map(_ error: any Error) -> FanControlExclusiveLockError {
        if let error = error as? FanControlExclusiveLockError { return error }
        if let error = error as? SecureStorageError {
            switch error {
            case .invalidPath(let reason), .unsafePath(let reason):
                return .unsafePath(reason)
            case .fileTooLarge(let name, let maximumBytes):
                return .unsafePath("lock file \(name) exceeds \(maximumBytes) bytes")
            case .ioFailure(let reason):
                return .ioFailure(reason)
            }
        }
        return .ioFailure(error.localizedDescription)
    }

    private static func posixFailure(_ operation: String) -> FanControlExclusiveLockError {
        .ioFailure("\(operation): \(String(cString: strerror(errno)))")
    }
}

private final class FanControlExclusiveLockRegistry: @unchecked Sendable {
    static let shared = FanControlExclusiveLockRegistry()

    private let lock = NSLock()
    private var ownedPaths: Set<String> = []

    func reserve(_ path: String) -> Bool {
        lock.withLock {
            ownedPaths.insert(path).inserted
        }
    }

    func release(_ path: String) {
        _ = lock.withLock {
            ownedPaths.remove(path)
        }
    }
}
