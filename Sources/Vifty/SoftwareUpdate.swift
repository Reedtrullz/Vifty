import AppKit
import Darwin
import Foundation
import Security
import SwiftUI
import ViftyCore

struct ViftyReleaseVersion: Codable, Comparable, CustomStringConvertible, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        precondition(major >= 0 && minor >= 0 && patch >= 0)
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(bundleVersion: String) {
        guard let parsed = Self.parse(bundleVersion) else { return nil }
        self = parsed
    }

    init?(tag: String) {
        guard tag.first == "v", let parsed = Self.parse(String(tag.dropFirst())) else {
            return nil
        }
        self = parsed
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    var tagName: String {
        "v\(description)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let version = Self(bundleVersion: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a canonical MAJOR.MINOR.PATCH version."
            )
        }
        self = version
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func parse(_ value: String) -> Self? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var values: [Int] = []
        values.reserveCapacity(3)
        for part in parts {
            guard !part.isEmpty,
                  part.count == 1 || part.first != "0",
                  part.utf8.allSatisfy({ byte in byte >= 48 && byte <= 57 }),
                  let number = Int(part)
            else {
                return nil
            }
            values.append(number)
        }

        return Self(major: values[0], minor: values[1], patch: values[2])
    }
}

struct SoftwareUpdateRelease: Codable, Equatable, Sendable {
    let version: ViftyReleaseVersion

    var tagName: String {
        version.tagName
    }

    var releasePageURL: URL {
        // The version parser permits ASCII digits only, so this fixed origin and
        // path cannot be redirected by release API content.
        URL(string: "https://github.com/Reedtrullz/Vifty/releases/tag/\(tagName)")!
    }

    var requiredAssetNames: Set<String> {
        [
            "Vifty-\(tagName).zip",
            "Vifty-\(tagName).zip.sha256",
            "Vifty-\(tagName)-artifact-summary.json",
            "Vifty-\(tagName)-release-checklist.md"
        ]
    }
}

struct SoftwareUpdateConfiguration: Equatable, Sendable {
    static let bundleIdentifier = "tech.reidar.vifty"
    static let initialDelay: TimeInterval = 5
    static let checkInterval: TimeInterval = 24 * 60 * 60

    let isEligible: Bool
    let currentVersion: ViftyReleaseVersion?
    let initialDelay: TimeInterval
    let checkInterval: TimeInterval

    static func live(bundle: Bundle = .main) -> Self {
        resolve(
            bundleIdentifier: bundle.bundleIdentifier,
            bundleVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            signatureIsEligible: ViftyUpdateBuildEligibility.isEligible()
        )
    }

    static func resolve(
        bundleIdentifier: String?,
        bundleVersion: String?,
        signatureIsEligible: Bool,
        initialDelay: TimeInterval = Self.initialDelay,
        checkInterval: TimeInterval = Self.checkInterval
    ) -> Self {
        let version = bundleVersion.flatMap(ViftyReleaseVersion.init(bundleVersion:))
        return Self(
            isEligible: bundleIdentifier == Self.bundleIdentifier
                && version != nil
                && signatureIsEligible,
            currentVersion: version,
            initialDelay: max(0, initialDelay),
            checkInterval: max(1, checkInterval)
        )
    }
}

enum ViftyUpdateBuildEligibility {
    static let teamIdentifier = "X88J3853S2"
    static let signingIdentifier = "tech.reidar.vifty"

    private static let requirementText = """
    anchor apple generic and identifier "tech.reidar.vifty" and certificate leaf[subject.OU] = "X88J3853S2" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
    """

    static func isEligible() -> Bool {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &dynamicCode) == errSecSuccess,
              let dynamicCode
        else {
            return false
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess,
              let requirement
        else {
            return false
        }

        let dynamicFlags = SecCSFlags(rawValue: kSecCSStrictValidate)
        guard SecCodeCheckValidity(dynamicCode, dynamicFlags, requirement) == errSecSuccess else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            return false
        }

        let staticFlags = SecCSFlags(
            rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode
        )
        guard SecStaticCodeCheckValidity(staticCode, staticFlags, requirement) == errSecSuccess else {
            return false
        }

        var information: CFDictionary?
        let informationFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, informationFlags, &information) == errSecSuccess,
              let signingInformation = information as? [String: Any]
        else {
            return false
        }

        return signingInformation[kSecCodeInfoIdentifier as String] as? String == signingIdentifier
            && signingInformation[kSecCodeInfoTeamIdentifier as String] as? String == teamIdentifier
    }
}

struct SoftwareUpdateHTTPResponse: Sendable {
    let statusCode: Int
    let finalURL: URL?
    let mimeType: String?
    let expectedContentLength: Int64
    let etag: String?
    let body: Data
}

protocol SoftwareUpdateHTTPTransport: Sendable {
    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws -> SoftwareUpdateHTTPResponse
}

final class SoftwareUpdateNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct SoftwareUpdateResponseAccumulator {
    private(set) var body: Data
    private let maximumResponseBytes: Int

    init(maximumResponseBytes: Int, expectedContentLength: Int64) {
        self.maximumResponseBytes = max(0, maximumResponseBytes)
        body = Data()
        body.reserveCapacity(
            max(0, min(self.maximumResponseBytes, Int(expectedContentLength)))
        )
    }

    mutating func append(_ byte: UInt8) throws {
        guard body.count < maximumResponseBytes else {
            throw SoftwareUpdateError.responseTooLarge
        }
        body.append(byte)
    }
}

final class URLSessionSoftwareUpdateHTTPTransport: SoftwareUpdateHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    convenience init() {
        self.init(configuration: Self.makeEphemeralConfiguration())
    }

    static func makeEphemeralConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        configuration.waitsForConnectivity = false
        return configuration
    }

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws -> SoftwareUpdateHTTPResponse {
        let delegate = SoftwareUpdateNoRedirectDelegate()
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        guard let httpResponse = response as? HTTPURLResponse else {
            bytes.task.cancel()
            throw SoftwareUpdateError.invalidHTTPResponse
        }

        if httpResponse.expectedContentLength > Int64(maximumResponseBytes) {
            bytes.task.cancel()
            throw SoftwareUpdateError.responseTooLarge
        }

        var accumulator = SoftwareUpdateResponseAccumulator(
            maximumResponseBytes: maximumResponseBytes,
            expectedContentLength: httpResponse.expectedContentLength
        )
        for try await byte in bytes {
            do {
                try accumulator.append(byte)
            } catch {
                bytes.task.cancel()
                throw error
            }
        }

        return SoftwareUpdateHTTPResponse(
            statusCode: httpResponse.statusCode,
            finalURL: httpResponse.url,
            mimeType: httpResponse.mimeType,
            expectedContentLength: httpResponse.expectedContentLength,
            etag: httpResponse.value(forHTTPHeaderField: "ETag"),
            body: accumulator.body
        )
    }
}

enum SoftwareUpdateFetchResult: Equatable, Sendable {
    case release(SoftwareUpdateRelease, etag: String?)
    case notModified
}

protocol SoftwareUpdateReleaseFetching: Sendable {
    func fetchLatest(
        currentVersion: ViftyReleaseVersion,
        etag: String?
    ) async throws -> SoftwareUpdateFetchResult
}

enum SoftwareUpdateError: Error, Equatable, LocalizedError, Sendable {
    case invalidHTTPResponse
    case unexpectedResponseURL
    case invalidContentType
    case responseTooLarge
    case httpStatus(Int)
    case invalidReleasePayload
    case notModifiedWithoutCachedRelease

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            "GitHub returned an invalid response."
        case .unexpectedResponseURL:
            "The update response came from an unexpected address."
        case .invalidContentType:
            "GitHub returned an unexpected update format."
        case .responseTooLarge:
            "The update response exceeded Vifty's safety limit."
        case .httpStatus(let status):
            "GitHub returned HTTP \(status)."
        case .invalidReleasePayload:
            "The latest GitHub release did not match Vifty's expected availability metadata."
        case .notModifiedWithoutCachedRelease:
            "GitHub reported no change, but Vifty has no validated release cached."
        }
    }
}

struct GitHubReleaseClient: SoftwareUpdateReleaseFetching, Sendable {
    static let endpoint = URL(
        string: "https://api.github.com/repos/Reedtrullz/Vifty/releases/latest"
    )!
    static let maximumResponseBytes = 512 * 1_024

    let transport: any SoftwareUpdateHTTPTransport

    init(transport: any SoftwareUpdateHTTPTransport = URLSessionSoftwareUpdateHTTPTransport()) {
        self.transport = transport
    }

    func fetchLatest(
        currentVersion: ViftyReleaseVersion,
        etag: String?
    ) async throws -> SoftwareUpdateFetchResult {
        let request = makeRequest(currentVersion: currentVersion, etag: etag)
        let response = try await transport.send(
            request,
            maximumResponseBytes: Self.maximumResponseBytes
        )
        return try validate(response)
    }

    func makeRequest(
        currentVersion: ViftyReleaseVersion,
        etag: String?
    ) -> URLRequest {
        var request = URLRequest(
            url: Self.endpoint,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Vifty/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if let etag = Self.safeETag(etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    func validate(_ response: SoftwareUpdateHTTPResponse) throws -> SoftwareUpdateFetchResult {
        guard response.finalURL?.absoluteString == Self.endpoint.absoluteString else {
            throw SoftwareUpdateError.unexpectedResponseURL
        }
        guard response.body.count <= Self.maximumResponseBytes else {
            throw SoftwareUpdateError.responseTooLarge
        }

        if response.statusCode == 304 {
            return .notModified
        }
        guard response.statusCode == 200 else {
            throw SoftwareUpdateError.httpStatus(response.statusCode)
        }
        guard let mimeType = response.mimeType?.lowercased(),
              mimeType == "application/json" || mimeType == "application/vnd.github+json"
        else {
            throw SoftwareUpdateError.invalidContentType
        }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(GitHubReleasePayload.self, from: response.body),
              !payload.draft,
              !payload.prerelease,
              let version = ViftyReleaseVersion(tag: payload.tagName)
        else {
            throw SoftwareUpdateError.invalidReleasePayload
        }

        let release = SoftwareUpdateRelease(version: version)
        guard payload.assets.count == release.requiredAssetNames.count,
              Set(payload.assets.map(\.name)) == release.requiredAssetNames,
              payload.assets.allSatisfy({ $0.state == "uploaded" && $0.size > 0 })
        else {
            throw SoftwareUpdateError.invalidReleasePayload
        }

        return .release(release, etag: Self.safeETag(response.etag))
    }

    private static func safeETag(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.utf8.count <= 512,
              !value.contains("\r"),
              !value.contains("\n")
        else {
            return nil
        }
        return value
    }
}

private struct GitHubReleasePayload: Decodable {
    struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int64
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }
}

struct SoftwareUpdateStoreSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var automaticChecksEnabled: Bool
    var lastAttemptAt: Date?
    var lastSuccessfulCheckAt: Date?
    var etag: String?
    var cachedRelease: SoftwareUpdateRelease?

    static let defaults = Self(
        schemaVersion: schemaVersion,
        automaticChecksEnabled: true,
        lastAttemptAt: nil,
        lastSuccessfulCheckAt: nil,
        etag: nil,
        cachedRelease: nil
    )
}

protocol SoftwareUpdateStateStoring: Sendable {
    func load() -> SoftwareUpdateStoreSnapshot
    func save(_ snapshot: SoftwareUpdateStoreSnapshot) throws
}

final class SoftwareUpdateStore: SoftwareUpdateStateStoring, @unchecked Sendable {
    static let maximumFileBytes = 64 * 1_024
    private static let ownerLockFileName = "software-update.owner.lock"

    let url: URL
    private let operationLock = NSLock()
    private var anchoredDirectory: SecureStorageDirectory?
    private var ownerDescriptor: Int32?
    private var ownerRegistryKey: SoftwareUpdateLockIdentity?
    private var ownershipDeniedUntilRelaunch = false

    init(url: URL? = nil) {
        self.url = url ?? Self.defaultURL()
    }

    deinit {
        operationLock.withLock {
            releaseOwnershipLocked()
        }
    }

    func load() -> SoftwareUpdateStoreSnapshot {
        operationLock.withLock {
            guard !ownershipDeniedUntilRelaunch else {
                return Self.failClosedDefaults
            }
            do {
                guard let directory = try secureDirectoryLocked(createIfMissing: true) else {
                    return Self.failClosedDefaults
                }
                try acquireOwnershipLocked(in: directory)
                try directory.tightenRegularFilePermissions(named: url.lastPathComponent)
                guard let data = try directory.readRegularFile(
                    named: url.lastPathComponent,
                    maximumBytes: Self.maximumFileBytes
                ) else {
                    return .defaults
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                guard var snapshot = try? decoder.decode(
                    SoftwareUpdateStoreSnapshot.self,
                    from: data
                ), snapshot.schemaVersion == SoftwareUpdateStoreSnapshot.schemaVersion else {
                    return Self.failClosedDefaults
                }
                if snapshot.cachedRelease == nil {
                    snapshot.etag = nil
                }
                return snapshot
            } catch {
                if Self.isOwnerUnavailable(error) {
                    ownershipDeniedUntilRelaunch = true
                }
                return Self.failClosedDefaults
            }
        }
    }

    func save(_ snapshot: SoftwareUpdateStoreSnapshot) throws {
        try operationLock.withLock {
            guard !ownershipDeniedUntilRelaunch else {
                throw SoftwareUpdateStoreError.ownerUnavailable
            }
            do {
                guard let directory = try secureDirectoryLocked(createIfMissing: true) else {
                    throw SoftwareUpdateStoreError.ownerUnavailable
                }
                try acquireOwnershipLocked(in: directory)
                try directory.tightenRegularFilePermissions(named: url.lastPathComponent)

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                guard data.count <= Self.maximumFileBytes else {
                    throw SoftwareUpdateStoreError.fileTooLarge
                }
                try directory.replaceRegularFile(
                    named: url.lastPathComponent,
                    data: data,
                    maximumBytes: Self.maximumFileBytes
                )
            } catch {
                if Self.isOwnerUnavailable(error) {
                    ownershipDeniedUntilRelaunch = true
                }
                throw error
            }
        }
    }

    private func secureDirectoryLocked(
        createIfMissing: Bool
    ) throws -> SecureStorageDirectory? {
        if let anchoredDirectory {
            do {
                try anchoredDirectory.validatePathIdentity()
                return anchoredDirectory
            } catch {
                do {
                    try anchoredDirectory.validatePathIdentityAllowingSafeLeafModeDrift()
                    try anchoredDirectory.tightenDirectoryPermissions()
                    return anchoredDirectory
                } catch {
                    releaseOwnershipLocked()
                    self.anchoredDirectory = nil
                    ownershipDeniedUntilRelaunch = true
                    throw SoftwareUpdateStoreError.ownerUnavailable
                }
            }
        }
        guard let migrationDirectory = try SecureStorageDirectory.open(
            directoryURL: url.deletingLastPathComponent(),
            requiredOwnerID: geteuid(),
            requiresExactMode: false,
            createIfMissing: createIfMissing
        ) else {
            return nil
        }
        try migrationDirectory.tightenDirectoryPermissions()
        guard let directory = try SecureStorageDirectory.open(
            directoryURL: url.deletingLastPathComponent(),
            requiredOwnerID: geteuid(),
            requiresExactMode: true,
            createIfMissing: false
        ) else {
            throw SoftwareUpdateStoreError.ownerUnavailable
        }
        anchoredDirectory = directory
        return directory
    }

    private func acquireOwnershipLocked(in directory: SecureStorageDirectory) throws {
        if let ownerDescriptor {
            try directory.validateOpenRegularFileDescriptor(
                ownerDescriptor,
                named: Self.ownerLockFileName
            )
            return
        }

        var descriptor: Int32?
        var registryKey: SoftwareUpdateLockIdentity?
        defer {
            if let descriptor {
                close(descriptor)
            }
            if let registryKey {
                SoftwareUpdateOwnerRegistry.shared.release(registryKey)
            }
        }

        let candidate: Int32
        do {
            candidate = try directory.openRegularFileDescriptor(
                named: Self.ownerLockFileName,
                createIfMissing: true,
                exclusiveLock: true
            )
        } catch SecureStorageError.lockUnavailable {
            throw SoftwareUpdateStoreError.ownerUnavailable
        }
        descriptor = candidate
        try directory.validateOpenRegularFileDescriptor(
            candidate,
            named: Self.ownerLockFileName
        )
        let identity = try SoftwareUpdateLockIdentity(descriptor: candidate)
        guard SoftwareUpdateOwnerRegistry.shared.reserve(identity) else {
            throw SoftwareUpdateStoreError.ownerUnavailable
        }
        registryKey = identity

        try directory.validateOpenRegularFileDescriptor(
            candidate,
            named: Self.ownerLockFileName
        )

        self.ownerDescriptor = candidate
        ownerRegistryKey = identity
        descriptor = nil
        registryKey = nil
    }

    private func releaseOwnershipLocked() {
        if let ownerDescriptor {
            close(ownerDescriptor)
            self.ownerDescriptor = nil
        }
        if let ownerRegistryKey {
            SoftwareUpdateOwnerRegistry.shared.release(ownerRegistryKey)
            self.ownerRegistryKey = nil
        }
    }

    private static func defaultURL() -> URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/software-update.json")
    }

    private static var failClosedDefaults: SoftwareUpdateStoreSnapshot {
        var snapshot = SoftwareUpdateStoreSnapshot.defaults
        snapshot.automaticChecksEnabled = false
        return snapshot
    }

    private static func isOwnerUnavailable(_ error: Error) -> Bool {
        guard let storeError = error as? SoftwareUpdateStoreError else {
            return false
        }
        if case .ownerUnavailable = storeError {
            return true
        }
        return false
    }
}

private enum SoftwareUpdateStoreError: Error {
    case fileTooLarge
    case ownerUnavailable
    case lockFailure(Int32)
}

private struct SoftwareUpdateLockIdentity: Hashable {
    let device: UInt64
    let inode: UInt64

    init(descriptor: Int32) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw SoftwareUpdateStoreError.lockFailure(errno)
        }
        device = UInt64(truncatingIfNeeded: metadata.st_dev)
        inode = UInt64(truncatingIfNeeded: metadata.st_ino)
    }
}

private final class SoftwareUpdateOwnerRegistry: @unchecked Sendable {
    static let shared = SoftwareUpdateOwnerRegistry()

    private let lock = NSLock()
    private var keys: Set<SoftwareUpdateLockIdentity> = []

    func reserve(_ key: SoftwareUpdateLockIdentity) -> Bool {
        lock.withLock { keys.insert(key).inserted }
    }

    func release(_ key: SoftwareUpdateLockIdentity) {
        _ = lock.withLock { keys.remove(key) }
    }
}

enum SoftwareUpdateStatus: Equatable, Sendable {
    case unavailable
    case ready
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(SoftwareUpdateRelease)
    case failed(String)
}

struct SoftwareUpdateAnnouncement: Equatable, Sendable {
    let id: UUID
    let message: String
}

@MainActor
protocol SoftwareUpdatePageOpening: AnyObject {
    func open(_ url: URL) -> Bool
}

@MainActor
final class SystemSoftwareUpdatePageOpener: SoftwareUpdatePageOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class SoftwareUpdateController: ObservableObject {
    enum CheckOrigin {
        case automatic
        case manual
    }

    @Published private(set) var status: SoftwareUpdateStatus
    @Published private(set) var automaticChecksEnabled: Bool
    @Published private(set) var isChecking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var errorAnnouncement: SoftwareUpdateAnnouncement?

    let configuration: SoftwareUpdateConfiguration

    private let client: any SoftwareUpdateReleaseFetching
    private let store: any SoftwareUpdateStateStoring
    private let pageOpener: any SoftwareUpdatePageOpening
    private let now: @Sendable () -> Date
    private let monotonicNow: @Sendable () -> TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var snapshot: SoftwareUpdateStoreSnapshot
    private var automaticTask: Task<Void, Never>?
    private var automaticTaskToken: UUID?
    private var checkTask: Task<SoftwareUpdateFetchResult, Error>?
    private var checkToken: UUID?
    private var currentCheckOrigin: CheckOrigin?
    private var statusBeforeCheck: SoftwareUpdateStatus?
    private var isStarted = false
    private var automaticNotBeforeUptime: TimeInterval?
    private(set) var settledCheckCount = 0

    init(
        configuration: SoftwareUpdateConfiguration,
        client: any SoftwareUpdateReleaseFetching,
        store: any SoftwareUpdateStateStoring,
        pageOpener: any SoftwareUpdatePageOpening,
        now: @escaping @Sendable () -> Date = Date.init,
        monotonicNow: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.configuration = configuration
        self.client = client
        self.store = store
        self.pageOpener = pageOpener
        self.now = now
        self.monotonicNow = monotonicNow
        self.sleep = sleep

        var snapshot: SoftwareUpdateStoreSnapshot
        if configuration.isEligible {
            snapshot = store.load()
        } else {
            snapshot = SoftwareUpdateStoreSnapshot.defaults
            snapshot.automaticChecksEnabled = false
        }
        let initializationDate = now()
        if let lastAttemptAt = snapshot.lastAttemptAt {
            let elapsed = max(0, initializationDate.timeIntervalSince(lastAttemptAt))
            automaticNotBeforeUptime = monotonicNow()
                + max(0, configuration.checkInterval - elapsed)
        }
        self.snapshot = snapshot
        automaticChecksEnabled = configuration.isEligible
            ? snapshot.automaticChecksEnabled
            : false
        if configuration.isEligible, let currentVersion = configuration.currentVersion {
            if let cachedRelease = snapshot.cachedRelease,
               cachedRelease.version > currentVersion {
                status = .updateAvailable(cachedRelease)
            } else {
                status = .ready
            }
        } else {
            status = .unavailable
        }
    }

    static func live() -> SoftwareUpdateController {
        SoftwareUpdateController(
            configuration: .live(),
            client: GitHubReleaseClient(),
            store: SoftwareUpdateStore(),
            pageOpener: SystemSoftwareUpdatePageOpener()
        )
    }

    static func inert() -> SoftwareUpdateController {
        SoftwareUpdateController(
            configuration: .resolve(
                bundleIdentifier: nil,
                bundleVersion: nil,
                signatureIsEligible: false
            ),
            client: GitHubReleaseClient(),
            store: SoftwareUpdateStore(
                url: FileManager.default.temporaryDirectory
                    .appendingPathComponent("vifty-software-update-inert")
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathComponent("software-update.json")
            ),
            pageOpener: SystemSoftwareUpdatePageOpener()
        )
    }

    var canCheck: Bool {
        configuration.isEligible && configuration.currentVersion != nil
    }

    var availableRelease: SoftwareUpdateRelease? {
        guard case .updateAvailable(let release) = status else { return nil }
        return release
    }

    var primaryActionTitle: String {
        availableRelease == nil ? "Check now" : "Update to latest version"
    }

    var menuActionTitle: String {
        availableRelease == nil ? "Check for Updates…" : "Update to Latest Version…"
    }

    var primaryActionHint: String {
        if availableRelease != nil {
            return "Opens Vifty's fixed GitHub release page in your default browser. "
                + "Vifty does not download or install the update."
        }
        return "Checks GitHub now and shows the result in Software Updates settings."
    }

    var statusText: String {
        switch status {
        case .unavailable:
            "Update checks are available only in eligible Developer ID-signed Vifty releases."
        case .ready:
            "Ready to check GitHub for the latest Vifty release metadata."
        case .checking:
            "Checking GitHub for the latest Vifty release metadata…"
        case .upToDate:
            if let version = configuration.currentVersion {
                "Vifty \(version) is up to date."
            } else {
                "Vifty is up to date."
            }
        case .updateAvailable(let release):
            "Vifty \(release.version) is available."
        case .failed(let message):
            message
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        scheduleAutomaticCheckIfNeeded()
    }

    func stop() {
        isStarted = false
        automaticTask?.cancel()
        automaticTask = nil
        automaticTaskToken = nil
        cancelCurrentCheckAndRestoreStatus()
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        guard canCheck, automaticChecksEnabled != enabled else { return }
        var candidate = snapshot
        candidate.automaticChecksEnabled = enabled

        if !enabled {
            snapshot = candidate
            automaticChecksEnabled = false
            automaticTask?.cancel()
            automaticTask = nil
            automaticTaskToken = nil
            if currentCheckOrigin == .automatic {
                cancelCurrentCheckAndRestoreStatus()
            }
            do {
                try store.save(candidate)
                clearSupplementalError()
            } catch {
                presentSupplementalError(
                    "Vifty couldn't save this preference for relaunch. "
                        + "Automatic checks are off for this session."
                )
            }
            return
        }

        do {
            try store.save(candidate)
        } catch {
            presentSupplementalError("Vifty couldn't save the update-check preference.")
            return
        }
        snapshot = candidate
        automaticChecksEnabled = enabled
        clearSupplementalError()

        scheduleAutomaticCheckIfNeeded()
    }

    func checkNow() async {
        automaticTask?.cancel()
        automaticTask = nil
        automaticTaskToken = nil
        await performCheck(origin: .manual)
        scheduleAutomaticCheckIfNeeded()
    }

    func performPrimaryAction() async {
        if let release = availableRelease {
            if pageOpener.open(release.releasePageURL) {
                clearSupplementalError()
            } else {
                presentSupplementalError("Vifty couldn't open its fixed GitHub release page.")
            }
            return
        }
        await checkNow()
    }

    private func scheduleAutomaticCheckIfNeeded() {
        guard automaticTask == nil,
              isStarted,
              canCheck,
              automaticChecksEnabled
        else {
            return
        }

        let currentDate = now()
        let elapsed = snapshot.lastAttemptAt.map { lastAttemptAt in
            // A wall-clock rollback must delay rather than accelerate the next
            // automatic request. Treat a future attempt as just completed.
            max(0, currentDate.timeIntervalSince(lastAttemptAt))
        }
        let untilInterval = elapsed.map { max(0, configuration.checkInterval - $0) } ?? 0
        let monotonicInterval = automaticNotBeforeUptime.map {
            max(0, $0 - monotonicNow())
        } ?? 0
        let delay = max(
            configuration.initialDelay,
            max(untilInterval, monotonicInterval)
        )

        let taskToken = UUID()
        automaticTaskToken = taskToken
        automaticTask = Task { [weak self, sleep] in
            do {
                try await sleep(delay)
                try Task.checkCancellation()
            } catch {
                return
            }
            await self?.automaticCheckDidFire(taskToken: taskToken)
        }
    }

    private func automaticCheckDidFire(taskToken: UUID) async {
        guard automaticTaskToken == taskToken else { return }
        automaticTask = nil
        automaticTaskToken = nil
        guard isStarted, automaticChecksEnabled else { return }
        await performCheck(origin: .automatic)
        scheduleAutomaticCheckIfNeeded()
    }

    private func cancelCurrentCheckAndRestoreStatus() {
        if isChecking {
            status = statusBeforeCheck ?? .ready
        }
        checkTask?.cancel()
        checkTask = nil
        checkToken = nil
        currentCheckOrigin = nil
        isChecking = false
        statusBeforeCheck = nil
    }

    private func performCheck(origin: CheckOrigin) async {
        guard canCheck, let currentVersion = configuration.currentVersion else {
            status = .unavailable
            return
        }
        guard checkTask == nil else { return }
        defer { settledCheckCount += 1 }

        let attemptDate = now()
        automaticNotBeforeUptime = monotonicNow() + configuration.checkInterval
        clearSupplementalError()
        snapshot.lastAttemptAt = attemptDate
        guard persistSnapshot() else {
            let message = "Vifty couldn't save the update-check attempt, so no request was sent."
            if let cachedRelease = snapshot.cachedRelease,
               cachedRelease.version > currentVersion {
                status = .updateAvailable(cachedRelease)
                presentSupplementalError(message)
            } else {
                let isRepeatedFailure = status == .failed(message)
                status = .failed(message)
                if isRepeatedFailure {
                    errorAnnouncement = SoftwareUpdateAnnouncement(id: UUID(), message: message)
                }
            }
            return
        }

        statusBeforeCheck = status
        status = .checking
        isChecking = true
        currentCheckOrigin = origin

        let token = UUID()
        checkToken = token
        let etag = snapshot.etag
        let client = client
        let task = Task {
            try await client.fetchLatest(currentVersion: currentVersion, etag: etag)
        }
        checkTask = task
        let result = await task.result
        let taskWasCancelled = task.isCancelled

        guard checkToken == token else { return }
        checkTask = nil
        checkToken = nil
        currentCheckOrigin = nil
        isChecking = false

        if taskWasCancelled {
            status = statusBeforeCheck ?? .ready
            statusBeforeCheck = nil
            return
        }

        switch result {
        case .success(let fetchResult):
            apply(fetchResult, currentVersion: currentVersion, checkedAt: now())
        case .failure(let error):
            if error is CancellationError {
                status = statusBeforeCheck ?? .ready
            } else {
                applyFailure(error, currentVersion: currentVersion)
            }
        }
        statusBeforeCheck = nil
    }

    private func apply(
        _ result: SoftwareUpdateFetchResult,
        currentVersion: ViftyReleaseVersion,
        checkedAt: Date
    ) {
        let release: SoftwareUpdateRelease
        switch result {
        case .release(let fetchedRelease, let etag):
            release = fetchedRelease
            snapshot.cachedRelease = fetchedRelease
            snapshot.etag = etag
        case .notModified:
            guard let cachedRelease = snapshot.cachedRelease else {
                snapshot.etag = nil
                _ = persistSnapshot()
                applyFailure(
                    SoftwareUpdateError.notModifiedWithoutCachedRelease,
                    currentVersion: currentVersion
                )
                return
            }
            release = cachedRelease
        }

        snapshot.lastSuccessfulCheckAt = checkedAt
        let stateWasSaved = persistSnapshot()
        status = release.version > currentVersion
            ? .updateAvailable(release)
            : .upToDate(checkedAt: checkedAt)
        if stateWasSaved {
            clearSupplementalError()
        } else {
            presentSupplementalError(
                "Vifty couldn't save update-check state. This result is available only for this session."
            )
        }
    }

    private func applyFailure(_ error: Error, currentVersion: ViftyReleaseVersion) {
        let message = Self.friendlyMessage(for: error)
        if let cachedRelease = snapshot.cachedRelease,
           cachedRelease.version > currentVersion {
            status = .updateAvailable(cachedRelease)
            presentSupplementalError(message)
        } else {
            errorMessage = message
            errorAnnouncement = nil
            status = .failed(message)
        }
    }

    @discardableResult
    private func persistSnapshot() -> Bool {
        do {
            try store.save(snapshot)
            return true
        } catch {
            return false
        }
    }

    private func presentSupplementalError(_ message: String) {
        errorMessage = message
        errorAnnouncement = SoftwareUpdateAnnouncement(id: UUID(), message: message)
    }

    private func clearSupplementalError() {
        errorMessage = nil
        errorAnnouncement = nil
    }

    private static func friendlyMessage(for error: Error) -> String {
        if case SoftwareUpdateError.httpStatus(let status) = error,
           status == 403 || status == 429 {
            return "GitHub temporarily limited update checks. Try again later."
        }
        if error is URLError {
            return "Couldn't reach GitHub. Check your internet connection and try again."
        }
        return (error as? LocalizedError)?.errorDescription
            ?? "Vifty couldn't check for updates."
    }
}
