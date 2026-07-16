import Darwin
import Foundation

public enum SecureStorageError: Error, Equatable, LocalizedError, Sendable {
    case invalidPath(String)
    case unsafePath(String)
    case fileTooLarge(name: String, maximumBytes: Int)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let reason):
            "Invalid secure-storage path: \(reason)"
        case .unsafePath(let reason):
            "Unsafe secure-storage path: \(reason)"
        case .fileTooLarge(let name, let maximumBytes):
            "Secure-storage file \(name) exceeds \(maximumBytes) bytes."
        case .ioFailure(let reason):
            "Secure-storage I/O failed: \(reason)"
        }
    }
}

public enum SecureStorageSyncPoint: Equatable, Sendable {
    case temporaryFile
    case directoryAfterReplace
    case directoryAfterDelete
}

public struct SecureStorageDurabilityHooks: Sendable {
    public var synchronize: @Sendable (Int32, SecureStorageSyncPoint) throws -> Void

    public init(
        synchronize: @escaping @Sendable (Int32, SecureStorageSyncPoint) throws -> Void
    ) {
        self.synchronize = synchronize
    }

    public static let live = SecureStorageDurabilityHooks { descriptor, point in
        guard fsync(descriptor) == 0 else {
            throw SecureStorageError.ioFailure(
                "fsync failed at \(String(describing: point)): \(String(cString: strerror(errno)))"
            )
        }
    }
}

/// Stable identity plus the observable file version used to bind a streamed
/// preservation copy to the exact primary that may subsequently be replaced.
public struct SecureStorageFileIdentity: Equatable, Sendable {
    fileprivate let device: UInt64
    fileprivate let inode: UInt64
    fileprivate let size: Int64
    fileprivate let modifiedSeconds: Int64
    fileprivate let modifiedNanoseconds: Int64
    fileprivate let changedSeconds: Int64
    fileprivate let changedNanoseconds: Int64

    fileprivate init(_ metadata: stat) {
        device = UInt64(truncatingIfNeeded: metadata.st_dev)
        inode = UInt64(truncatingIfNeeded: metadata.st_ino)
        size = Int64(metadata.st_size)
        modifiedSeconds = Int64(metadata.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(metadata.st_mtimespec.tv_nsec)
        changedSeconds = Int64(metadata.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(metadata.st_ctimespec.tv_nsec)
    }
}

/// A root-to-leaf, descriptor-anchored directory used for privileged state.
///
/// Every path component is opened independently with `O_NOFOLLOW`, compared
/// with its parent entry, and retained for this object's lifetime. Operations
/// are relative to the retained leaf descriptor, and `validatePathIdentity()`
/// fails closed if any component is renamed or substituted later.
public final class SecureStorageDirectory: @unchecked Sendable {
    public let directoryURL: URL
    public let requiredOwnerID: uid_t
    public let requiredMode: mode_t
    public let requiresExactMode: Bool

    private let componentNames: [String]
    private let descriptors: [Int32]

    private var leafDescriptor: Int32 {
        descriptors[descriptors.count - 1]
    }

    private init(
        directoryURL: URL,
        requiredOwnerID: uid_t,
        requiredMode: mode_t,
        requiresExactMode: Bool,
        componentNames: [String],
        descriptors: [Int32]
    ) {
        self.directoryURL = directoryURL
        self.requiredOwnerID = requiredOwnerID
        self.requiredMode = requiredMode
        self.requiresExactMode = requiresExactMode
        self.componentNames = componentNames
        self.descriptors = descriptors
    }

    deinit {
        for descriptor in descriptors.reversed() {
            close(descriptor)
        }
    }

    public static func open(
        directoryURL: URL,
        requiredOwnerID: uid_t,
        requiredMode: mode_t = 0o700,
        requiresExactMode: Bool = true,
        createIfMissing: Bool
    ) throws -> SecureStorageDirectory? {
        guard requiredMode & ~mode_t(0o777) == 0 else {
            throw SecureStorageError.invalidPath("directory mode is outside the POSIX permission mask")
        }
        let normalizedURL = try normalizedAbsoluteURL(directoryURL)
        let components = Array(normalizedURL.pathComponents.dropFirst())
        guard !components.isEmpty else {
            throw SecureStorageError.invalidPath("the filesystem root cannot be a managed directory")
        }

        let rootDescriptor = Darwin.open("/", O_RDONLY | O_CLOEXEC | O_DIRECTORY)
        guard rootDescriptor >= 0 else { throw posixFailure("open filesystem root") }
        var openedDescriptors = [rootDescriptor]
        var completed = false
        defer {
            if !completed {
                for descriptor in openedDescriptors.reversed() {
                    close(descriptor)
                }
            }
        }

        try validateRootDescriptor(rootDescriptor)
        for (index, component) in components.enumerated() {
            try validateComponentName(component)
            let parentDescriptor = openedDescriptors[openedDescriptors.count - 1]
            let isLeaf = index == components.count - 1
            var entryMetadata = stat()
            var wasCreated = false

            if fstatat(parentDescriptor, component, &entryMetadata, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else {
                    throw posixFailure("inspect directory component \(component)")
                }
                guard createIfMissing else { return nil }
                guard mkdirat(parentDescriptor, component, requiredMode) == 0 else {
                    if errno == EEXIST {
                        throw SecureStorageError.unsafePath(
                            "directory component \(component) appeared while it was being created"
                        )
                    }
                    throw posixFailure("create directory component \(component)")
                }
                wasCreated = true
            } else {
                guard entryMetadata.st_mode & S_IFMT == S_IFDIR else {
                    throw SecureStorageError.unsafePath(
                        "directory component \(component) is not a real directory"
                    )
                }
            }

            let childDescriptor = openat(
                parentDescriptor,
                component,
                O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
            )
            guard childDescriptor >= 0 else {
                throw posixFailure("open directory component \(component)")
            }
            openedDescriptors.append(childDescriptor)

            if wasCreated {
                guard fchmod(childDescriptor, requiredMode) == 0 else {
                    throw posixFailure("chmod directory component \(component)")
                }
                if requiredOwnerID != geteuid() {
                    guard fchown(childDescriptor, requiredOwnerID, gid_t.max) == 0 else {
                        throw posixFailure("chown directory component \(component)")
                    }
                }
                guard fsync(parentDescriptor) == 0 else {
                    throw posixFailure("synchronize parent after creating \(component)")
                }
            }

            try validateDirectoryEntry(
                parentDescriptor: parentDescriptor,
                childDescriptor: childDescriptor,
                component: component,
                requiredOwnerID: requiredOwnerID,
                requiredMode: requiredMode,
                requiresExactMode: requiresExactMode,
                isLeaf: isLeaf
            )
        }

        completed = true
        return SecureStorageDirectory(
            directoryURL: normalizedURL,
            requiredOwnerID: requiredOwnerID,
            requiredMode: requiredMode,
            requiresExactMode: requiresExactMode,
            componentNames: components,
            descriptors: openedDescriptors
        )
    }

    public func validatePathIdentity() throws {
        try Self.validateRootDescriptor(descriptors[0])
        for index in componentNames.indices {
            try Self.validateDirectoryEntry(
                parentDescriptor: descriptors[index],
                childDescriptor: descriptors[index + 1],
                component: componentNames[index],
                requiredOwnerID: requiredOwnerID,
                requiredMode: requiredMode,
                requiresExactMode: requiresExactMode,
                isLeaf: index == componentNames.count - 1
            )
        }
    }

    public func readRegularFile(
        named name: String,
        maximumBytes: Int,
        requiredMode: mode_t = 0o600
    ) throws -> Data? {
        try validateFileArguments(name: name, maximumBytes: maximumBytes, requiredMode: requiredMode)
        try validatePathIdentity()
        guard let pathMetadata = try entryMetadata(named: name) else { return nil }
        try validateRegularFileMetadata(
            pathMetadata,
            name: name,
            requiredMode: requiredMode
        )

        let descriptor = openat(leafDescriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Self.posixFailure("open secure file \(name)") }
        defer { close(descriptor) }
        try validateOpenRegularFile(
            descriptor,
            pathMetadata: pathMetadata,
            name: name,
            requiredMode: requiredMode
        )
        let data = try readAll(descriptor, name: name, maximumBytes: maximumBytes)
        try validatePathIdentity()
        return data
    }

    public func replaceRegularFile(
        named name: String,
        data: Data,
        maximumBytes: Int,
        requiredMode: mode_t = 0o600,
        expectedOriginalIdentity: SecureStorageFileIdentity? = nil,
        hooks: SecureStorageDurabilityHooks = .live
    ) throws {
        try validateFileArguments(name: name, maximumBytes: maximumBytes, requiredMode: requiredMode)
        guard data.count <= maximumBytes else {
            throw SecureStorageError.fileTooLarge(name: name, maximumBytes: maximumBytes)
        }
        try validatePathIdentity()
        let originalMetadata = try entryMetadata(named: name)
        if let originalMetadata {
            try validateRegularFileMetadata(
                originalMetadata,
                name: name,
                requiredMode: requiredMode
            )
        }
        if let expectedOriginalIdentity {
            guard let originalMetadata,
                  SecureStorageFileIdentity(originalMetadata) == expectedOriginalIdentity else {
                throw SecureStorageError.unsafePath(
                    "secure file \(name) no longer matches the preserved original"
                )
            }
        }

        let temporaryName = ".\(name).\(UUID().uuidString).tmp"
        let descriptor = openat(
            leafDescriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            requiredMode
        )
        guard descriptor >= 0 else {
            throw Self.posixFailure("create temporary secure file for \(name)")
        }
        var shouldRemoveTemporary = true
        defer {
            close(descriptor)
            if shouldRemoveTemporary {
                _ = unlinkat(leafDescriptor, temporaryName, 0)
            }
        }

        guard fchmod(descriptor, requiredMode) == 0 else {
            throw Self.posixFailure("chmod temporary secure file for \(name)")
        }
        if requiredOwnerID != geteuid() {
            guard fchown(descriptor, requiredOwnerID, gid_t.max) == 0 else {
                throw Self.posixFailure("chown temporary secure file for \(name)")
            }
        }
        var temporaryMetadata = stat()
        guard fstat(descriptor, &temporaryMetadata) == 0 else {
            throw Self.posixFailure("inspect temporary secure file for \(name)")
        }
        try validateRegularFileMetadata(
            temporaryMetadata,
            name: temporaryName,
            requiredMode: requiredMode
        )
        try writeAll(data, descriptor: descriptor, name: name)
        try hooks.synchronize(descriptor, .temporaryFile)

        let currentMetadata = try entryMetadata(named: name)
        guard Self.sameOptionalVersion(originalMetadata, currentMetadata) else {
            throw SecureStorageError.unsafePath(
                "secure file \(name) changed while its replacement was prepared"
            )
        }
        if let expectedOriginalIdentity {
            guard let currentMetadata,
                  SecureStorageFileIdentity(currentMetadata) == expectedOriginalIdentity else {
                throw SecureStorageError.unsafePath(
                    "secure file \(name) changed after its preservation copy"
                )
            }
        }
        try validatePathIdentity()
        guard renameat(leafDescriptor, temporaryName, leafDescriptor, name) == 0 else {
            throw Self.posixFailure("replace secure file \(name)")
        }
        shouldRemoveTemporary = false

        guard let replacedMetadata = try entryMetadata(named: name),
              Self.sameIdentity(temporaryMetadata, replacedMetadata) else {
            throw SecureStorageError.unsafePath(
                "secure file \(name) does not reference the synchronized replacement"
            )
        }
        try validateRegularFileMetadata(
            replacedMetadata,
            name: name,
            requiredMode: requiredMode
        )
        try hooks.synchronize(leafDescriptor, .directoryAfterReplace)
        try validatePathIdentity()
    }

    /// Streams one exact regular file into an atomically replaced sibling.
    /// The source is never accumulated in memory and is never removed. The
    /// returned version identity can be required by a subsequent replacement
    /// so oversized or corrupt durable state cannot be classified from one
    /// inode and then silently replaced on another.
    public func copyRegularFile(
        named sourceName: String,
        to destinationName: String,
        requiredMode: mode_t = 0o600,
        hooks: SecureStorageDurabilityHooks = .live
    ) throws -> SecureStorageFileIdentity {
        try validateFileArguments(name: sourceName, maximumBytes: 1, requiredMode: requiredMode)
        try validateFileArguments(name: destinationName, maximumBytes: 1, requiredMode: requiredMode)
        guard sourceName != destinationName else {
            throw SecureStorageError.invalidPath("secure copy source and destination must differ")
        }
        try validatePathIdentity()
        guard let sourcePathMetadata = try entryMetadata(named: sourceName) else {
            throw SecureStorageError.ioFailure("secure file \(sourceName) is missing")
        }
        try validateRegularFileMetadata(
            sourcePathMetadata,
            name: sourceName,
            requiredMode: requiredMode
        )
        let sourceIdentity = SecureStorageFileIdentity(sourcePathMetadata)
        let destinationMetadata = try entryMetadata(named: destinationName)
        if let destinationMetadata {
            try validateRegularFileMetadata(
                destinationMetadata,
                name: destinationName,
                requiredMode: requiredMode
            )
        }

        let sourceDescriptor = openat(
            leafDescriptor,
            sourceName,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard sourceDescriptor >= 0 else {
            throw Self.posixFailure("open secure copy source \(sourceName)")
        }
        defer { close(sourceDescriptor) }
        try validateOpenRegularFile(
            sourceDescriptor,
            pathMetadata: sourcePathMetadata,
            name: sourceName,
            requiredMode: requiredMode
        )

        let temporaryName = ".\(destinationName).\(UUID().uuidString).tmp"
        let destinationDescriptor = openat(
            leafDescriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            requiredMode
        )
        guard destinationDescriptor >= 0 else {
            throw Self.posixFailure("create temporary secure copy for \(destinationName)")
        }
        var shouldRemoveTemporary = true
        defer {
            close(destinationDescriptor)
            if shouldRemoveTemporary {
                _ = unlinkat(leafDescriptor, temporaryName, 0)
            }
        }

        guard fchmod(destinationDescriptor, requiredMode) == 0 else {
            throw Self.posixFailure("chmod temporary secure copy for \(destinationName)")
        }
        if requiredOwnerID != geteuid() {
            guard fchown(destinationDescriptor, requiredOwnerID, gid_t.max) == 0 else {
                throw Self.posixFailure("chown temporary secure copy for \(destinationName)")
            }
        }
        var temporaryMetadata = stat()
        guard fstat(destinationDescriptor, &temporaryMetadata) == 0 else {
            throw Self.posixFailure("inspect temporary secure copy for \(destinationName)")
        }
        try validateRegularFileMetadata(
            temporaryMetadata,
            name: temporaryName,
            requiredMode: requiredMode
        )
        try copyAll(
            from: sourceDescriptor,
            to: destinationDescriptor,
            sourceName: sourceName,
            destinationName: destinationName
        )
        try hooks.synchronize(destinationDescriptor, .temporaryFile)

        var sourceDescriptorMetadata = stat()
        guard fstat(sourceDescriptor, &sourceDescriptorMetadata) == 0,
              SecureStorageFileIdentity(sourceDescriptorMetadata) == sourceIdentity,
              let currentSourceMetadata = try entryMetadata(named: sourceName),
              SecureStorageFileIdentity(currentSourceMetadata) == sourceIdentity else {
            throw SecureStorageError.unsafePath(
                "secure file \(sourceName) changed while it was being preserved"
            )
        }
        let currentDestinationMetadata = try entryMetadata(named: destinationName)
        guard Self.sameOptionalVersion(destinationMetadata, currentDestinationMetadata) else {
            throw SecureStorageError.unsafePath(
                "secure file \(destinationName) changed while its preservation copy was prepared"
            )
        }
        try validatePathIdentity()
        guard renameat(
            leafDescriptor,
            temporaryName,
            leafDescriptor,
            destinationName
        ) == 0 else {
            throw Self.posixFailure("replace secure preservation file \(destinationName)")
        }
        shouldRemoveTemporary = false

        guard let copiedMetadata = try entryMetadata(named: destinationName),
              Self.sameIdentity(temporaryMetadata, copiedMetadata) else {
            throw SecureStorageError.unsafePath(
                "secure file \(destinationName) does not reference the synchronized preservation copy"
            )
        }
        try validateRegularFileMetadata(
            copiedMetadata,
            name: destinationName,
            requiredMode: requiredMode
        )
        try hooks.synchronize(leafDescriptor, .directoryAfterReplace)
        try validatePathIdentity()
        return sourceIdentity
    }

    @discardableResult
    public func removeRegularFile(
        named name: String,
        requiredMode: mode_t = 0o600,
        hooks: SecureStorageDurabilityHooks = .live
    ) throws -> Bool {
        try validateFileArguments(name: name, maximumBytes: 1, requiredMode: requiredMode)
        try validatePathIdentity()
        guard let metadata = try entryMetadata(named: name) else { return false }
        try validateRegularFileMetadata(metadata, name: name, requiredMode: requiredMode)
        guard unlinkat(leafDescriptor, name, 0) == 0 else {
            throw Self.posixFailure("remove secure file \(name)")
        }
        try hooks.synchronize(leafDescriptor, .directoryAfterDelete)
        try validatePathIdentity()
        return true
    }

    /// Opens or creates a private regular file relative to the retained leaf.
    /// The caller owns the returned descriptor.
    public func openRegularFileDescriptor(
        named name: String,
        requiredMode: mode_t = 0o600,
        createIfMissing: Bool
    ) throws -> Int32 {
        try validateFileArguments(name: name, maximumBytes: 1, requiredMode: requiredMode)
        try validatePathIdentity()
        let originalMetadata = try entryMetadata(named: name)
        if let originalMetadata {
            try validateRegularFileMetadata(
                originalMetadata,
                name: name,
                requiredMode: requiredMode
            )
        } else if !createIfMissing {
            throw SecureStorageError.ioFailure("secure file \(name) is missing")
        }

        let flags = originalMetadata == nil
            ? O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW
            : O_RDWR | O_CLOEXEC | O_NOFOLLOW
        let descriptor = openat(leafDescriptor, name, flags, requiredMode)
        guard descriptor >= 0 else { throw Self.posixFailure("open secure file \(name)") }
        do {
            if originalMetadata == nil {
                guard fchmod(descriptor, requiredMode) == 0 else {
                    throw Self.posixFailure("chmod secure file \(name)")
                }
                if requiredOwnerID != geteuid() {
                    guard fchown(descriptor, requiredOwnerID, gid_t.max) == 0 else {
                        throw Self.posixFailure("chown secure file \(name)")
                    }
                }
                guard fsync(leafDescriptor) == 0 else {
                    throw Self.posixFailure("synchronize directory after creating \(name)")
                }
            }
            guard let pathMetadata = try entryMetadata(named: name) else {
                throw SecureStorageError.unsafePath("secure file \(name) disappeared while opening")
            }
            try validateOpenRegularFile(
                descriptor,
                pathMetadata: pathMetadata,
                name: name,
                requiredMode: requiredMode
            )
            try validatePathIdentity()
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    public func validateOpenRegularFileDescriptor(
        _ descriptor: Int32,
        named name: String,
        requiredMode: mode_t = 0o600
    ) throws {
        try validateFileArguments(name: name, maximumBytes: 1, requiredMode: requiredMode)
        try validatePathIdentity()
        guard let pathMetadata = try entryMetadata(named: name) else {
            throw SecureStorageError.unsafePath("secure file \(name) is no longer linked")
        }
        try validateOpenRegularFile(
            descriptor,
            pathMetadata: pathMetadata,
            name: name,
            requiredMode: requiredMode
        )
    }

    private func entryMetadata(named name: String) throws -> stat? {
        var metadata = stat()
        if fstatat(leafDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
            return metadata
        }
        if errno == ENOENT { return nil }
        throw Self.posixFailure("inspect secure file \(name)")
    }

    private func validateOpenRegularFile(
        _ descriptor: Int32,
        pathMetadata: stat,
        name: String,
        requiredMode: mode_t
    ) throws {
        var openedMetadata = stat()
        guard fstat(descriptor, &openedMetadata) == 0 else {
            throw Self.posixFailure("inspect open secure file \(name)")
        }
        try validateRegularFileMetadata(
            openedMetadata,
            name: name,
            requiredMode: requiredMode
        )
        guard Self.sameIdentity(pathMetadata, openedMetadata) else {
            throw SecureStorageError.unsafePath(
                "secure file \(name) changed while it was being opened"
            )
        }
    }

    private func validateRegularFileMetadata(
        _ metadata: stat,
        name: String,
        requiredMode: mode_t
    ) throws {
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            throw SecureStorageError.unsafePath("secure file \(name) is not a regular file")
        }
        guard metadata.st_uid == requiredOwnerID else {
            throw SecureStorageError.unsafePath("secure file \(name) has the wrong owner")
        }
        guard metadata.st_mode & 0o777 == requiredMode else {
            throw SecureStorageError.unsafePath("secure file \(name) has unsafe permissions")
        }
        guard metadata.st_nlink == 1 else {
            throw SecureStorageError.unsafePath("secure file \(name) has multiple hard links")
        }
    }

    private func validateFileArguments(name: String, maximumBytes: Int, requiredMode: mode_t) throws {
        try Self.validateComponentName(name)
        guard maximumBytes > 0 else {
            throw SecureStorageError.invalidPath("maximum file size must be positive")
        }
        guard requiredMode & ~mode_t(0o777) == 0 else {
            throw SecureStorageError.invalidPath("file mode is outside the POSIX permission mask")
        }
    }

    private func readAll(_ descriptor: Int32, name: String, maximumBytes: Int) throws -> Data {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw Self.posixFailure("inspect secure file size for \(name)")
        }
        guard metadata.st_size >= 0,
              metadata.st_size <= off_t(maximumBytes) else {
            throw SecureStorageError.fileTooLarge(name: name, maximumBytes: maximumBytes)
        }
        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                throw Self.posixFailure("read secure file \(name)")
            }
            guard data.count <= maximumBytes - count else {
                throw SecureStorageError.fileTooLarge(name: name, maximumBytes: maximumBytes)
            }
            data.append(buffer, count: count)
        }
    }

    private func writeAll(_ data: Data, descriptor: Int32, name: String) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw Self.posixFailure("write secure file \(name)")
                }
                guard count > 0 else {
                    throw SecureStorageError.ioFailure(
                        "write secure file \(name): zero-byte progress"
                    )
                }
                offset += count
            }
        }
    }

    private func copyAll(
        from sourceDescriptor: Int32,
        to destinationDescriptor: Int32,
        sourceName: String,
        destinationName: String
    ) throws {
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let readCount = Darwin.read(sourceDescriptor, &buffer, buffer.count)
            if readCount == 0 { return }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw Self.posixFailure("read secure copy source \(sourceName)")
            }
            var offset = 0
            while offset < readCount {
                let writeCount = buffer.withUnsafeBytes { rawBuffer in
                    Darwin.write(
                        destinationDescriptor,
                        rawBuffer.baseAddress!.advanced(by: offset),
                        readCount - offset
                    )
                }
                if writeCount < 0 {
                    if errno == EINTR { continue }
                    throw Self.posixFailure("write secure copy destination \(destinationName)")
                }
                guard writeCount > 0 else {
                    throw SecureStorageError.ioFailure(
                        "write secure copy destination \(destinationName): zero-byte progress"
                    )
                }
                offset += writeCount
            }
        }
    }

    private static func normalizedAbsoluteURL(_ url: URL) throws -> URL {
        guard url.isFileURL else {
            throw SecureStorageError.invalidPath("URL is not a file URL")
        }
        let rawPath = url.path
        guard rawPath.hasPrefix("/"), !rawPath.utf8.contains(0) else {
            throw SecureStorageError.invalidPath("directory path must be absolute and contain no NUL bytes")
        }
        let rawComponents = rawPath.split(separator: "/", omittingEmptySubsequences: true)
        guard !rawComponents.contains("."), !rawComponents.contains("..") else {
            throw SecureStorageError.invalidPath("directory path contains dot traversal")
        }

        // `/var` and `/tmp` are fixed macOS compatibility aliases. Normalize
        // only these system aliases; arbitrary caller-provided symlinks remain
        // visible to the component-by-component `O_NOFOLLOW` walk.
        let normalizedPath: String
        if rawPath == "/var" || rawPath.hasPrefix("/var/")
            || rawPath == "/tmp" || rawPath.hasPrefix("/tmp/") {
            normalizedPath = "/private" + rawPath
        } else {
            normalizedPath = (rawPath as NSString).standardizingPath
        }
        return URL(fileURLWithPath: normalizedPath, isDirectory: true)
    }

    private static func validateRootDescriptor(_ descriptor: Int32) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixFailure("inspect filesystem root")
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_uid == 0,
              metadata.st_mode & 0o022 == 0 else {
            throw SecureStorageError.unsafePath("filesystem root is not a trusted root-owned directory")
        }
    }

    private static func validateDirectoryEntry(
        parentDescriptor: Int32,
        childDescriptor: Int32,
        component: String,
        requiredOwnerID: uid_t,
        requiredMode: mode_t,
        requiresExactMode: Bool,
        isLeaf: Bool
    ) throws {
        var pathMetadata = stat()
        guard fstatat(parentDescriptor, component, &pathMetadata, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw posixFailure("revalidate directory component \(component)")
        }
        var openedMetadata = stat()
        guard fstat(childDescriptor, &openedMetadata) == 0 else {
            throw posixFailure("inspect open directory component \(component)")
        }
        guard sameIdentity(pathMetadata, openedMetadata) else {
            throw SecureStorageError.unsafePath(
                "directory component \(component) changed while it was being opened"
            )
        }
        guard openedMetadata.st_mode & S_IFMT == S_IFDIR else {
            throw SecureStorageError.unsafePath("directory component \(component) is not a directory")
        }

        if isLeaf {
            guard openedMetadata.st_uid == requiredOwnerID else {
                throw SecureStorageError.unsafePath("managed directory has the wrong owner")
            }
            if requiresExactMode {
                guard openedMetadata.st_mode & 0o777 == requiredMode else {
                    throw SecureStorageError.unsafePath(
                        "managed directory permissions are not \(String(requiredMode, radix: 8))"
                    )
                }
            } else {
                guard openedMetadata.st_mode & 0o022 == 0 else {
                    throw SecureStorageError.unsafePath(
                        "managed directory is group/world writable"
                    )
                }
            }
        } else {
            guard openedMetadata.st_uid == 0 || openedMetadata.st_uid == requiredOwnerID else {
                throw SecureStorageError.unsafePath(
                    "intermediate directory \(component) has an untrusted owner"
                )
            }
            guard openedMetadata.st_mode & 0o022 == 0 else {
                throw SecureStorageError.unsafePath(
                    "intermediate directory \(component) is group/world writable"
                )
            }
        }
    }

    private static func validateComponentName(_ component: String) throws {
        guard !component.isEmpty,
              component != ".",
              component != "..",
              !component.contains("/"),
              !component.utf8.contains(0),
              component.utf8.count <= Int(NAME_MAX) else {
            throw SecureStorageError.invalidPath("invalid path component")
        }
    }

    private static func sameIdentity(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private static func sameOptionalIdentity(_ lhs: stat?, _ rhs: stat?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let lhs), .some(let rhs)): sameIdentity(lhs, rhs)
        default: false
        }
    }

    private static func sameOptionalVersion(_ lhs: stat?, _ rhs: stat?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let lhs), .some(let rhs)):
            SecureStorageFileIdentity(lhs) == SecureStorageFileIdentity(rhs)
        default: false
        }
    }

    private static func posixFailure(_ operation: String) -> SecureStorageError {
        .ioFailure("\(operation): \(String(cString: strerror(errno)))")
    }
}
