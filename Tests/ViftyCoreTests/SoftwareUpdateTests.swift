import Darwin
import Foundation
import XCTest
@testable import Vifty

final class SoftwareUpdateValueTests: XCTestCase {
    func testAdHocXCTestProcessIsNotDeveloperIDSignedVifty() {
        XCTAssertFalse(ViftyUpdateBuildEligibility.isEligible())
    }

    func testVersionParsingComparisonAndCanonicalCodableShape() throws {
        let version = try XCTUnwrap(ViftyReleaseVersion(bundleVersion: "1.23.456"))
        XCTAssertEqual(version, ViftyReleaseVersion(tag: "v1.23.456"))
        XCTAssertEqual(version.description, "1.23.456")
        XCTAssertEqual(version.tagName, "v1.23.456")
        XCTAssertLessThan(
            try XCTUnwrap(ViftyReleaseVersion(bundleVersion: "1.9.9")),
            try XCTUnwrap(ViftyReleaseVersion(bundleVersion: "2.0.0"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(ViftyReleaseVersion(bundleVersion: "2.0.9")),
            try XCTUnwrap(ViftyReleaseVersion(bundleVersion: "2.1.0"))
        )

        let encoded = try JSONEncoder().encode(version)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"1.23.456\"")
        XCTAssertEqual(try JSONDecoder().decode(ViftyReleaseVersion.self, from: encoded), version)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ViftyReleaseVersion.self,
                from: Data("\"01.2.3\"".utf8)
            )
        )
    }

    func testVersionParserRejectsNonStableAndNonCanonicalForms() {
        let invalidBundleVersions = [
            "", "1", "1.2", "1.2.3.4", "v1.2.3", "1.2.3-beta",
            "01.2.3", "1.02.3", "1.2.03", "-1.2.3", "+1.2.3",
            "1. 2.3", "１.2.3", "1..3", "1.2.", "1.2.9223372036854775808"
        ]
        for value in invalidBundleVersions {
            XCTAssertNil(ViftyReleaseVersion(bundleVersion: value), value)
        }

        for tag in ["", "1.2.3", "vv1.2.3", "v1.2.3-beta", "v01.2.3"] {
            XCTAssertNil(ViftyReleaseVersion(tag: tag), tag)
        }
    }

    func testConfigurationRequiresExactBundleVersionAndDeveloperIDEligibility() throws {
        let eligible = SoftwareUpdateConfiguration.resolve(
            bundleIdentifier: "tech.reidar.vifty",
            bundleVersion: "1.3.2",
            signatureIsEligible: true
        )
        XCTAssertTrue(eligible.isEligible)
        XCTAssertEqual(
            eligible.currentVersion,
            try XCTUnwrap(ViftyReleaseVersion(bundleVersion: "1.3.2"))
        )

        XCTAssertFalse(SoftwareUpdateConfiguration.resolve(
            bundleIdentifier: "tech.reidar.vifty.debug",
            bundleVersion: "1.3.2",
            signatureIsEligible: true
        ).isEligible)
        XCTAssertFalse(SoftwareUpdateConfiguration.resolve(
            bundleIdentifier: "tech.reidar.vifty",
            bundleVersion: "1.3.2",
            signatureIsEligible: false
        ).isEligible)
        XCTAssertFalse(SoftwareUpdateConfiguration.resolve(
            bundleIdentifier: "tech.reidar.vifty",
            bundleVersion: "1.3.2-dev",
            signatureIsEligible: true
        ).isEligible)
    }

    func testReleasePageAndAssetNamesAreConstructedFromValidatedVersion() throws {
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v2.4.6"))
        )

        XCTAssertEqual(
            release.releasePageURL.absoluteString,
            "https://github.com/Reedtrullz/Vifty/releases/tag/v2.4.6"
        )
        XCTAssertEqual(release.requiredAssetNames, [
            "Vifty-v2.4.6.zip",
            "Vifty-v2.4.6.zip.sha256",
            "Vifty-v2.4.6-artifact-summary.json",
            "Vifty-v2.4.6-release-checklist.md"
        ])
    }
}

final class GitHubReleaseClientTests: XCTestCase {
    func testRequestUsesOnlyFixedEndpointPublicHeadersAndSafeETag() throws {
        let client = GitHubReleaseClient(transport: StubSoftwareUpdateTransport(
            response: validResponse(version: "1.4.0")
        ))
        let current = try XCTUnwrap(ViftyReleaseVersion(bundleVersion: "1.3.2"))
        let request = client.makeRequest(currentVersion: current, etag: "W/\"release-1\"")

        XCTAssertEqual(request.url, GitHubReleaseClient.endpoint)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Vifty/1.3.2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "W/\"release-1\"")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))

        let poisoned = client.makeRequest(
            currentVersion: current,
            etag: "safe\r\nAuthorization: secret"
        )
        XCTAssertNil(poisoned.value(forHTTPHeaderField: "If-None-Match"))
    }

    func testFetchAcceptsOnlyCanonicalReleaseAndForwardsStrictSizeLimit() async throws {
        let transport = StubSoftwareUpdateTransport(response: validResponse(
            version: "1.4.0",
            etag: "\"new-etag\""
        ))
        let result = try await GitHubReleaseClient(transport: transport).fetchLatest(
            currentVersion: try XCTUnwrap(ViftyReleaseVersion(bundleVersion: "1.3.2")),
            etag: nil
        )

        XCTAssertEqual(
            result,
            .release(
                SoftwareUpdateRelease(
                    version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
                ),
                etag: "\"new-etag\""
            )
        )
        let requestCount = await transport.requestCount()
        let maximumBytes = await transport.lastMaximumResponseBytes()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(maximumBytes, GitHubReleaseClient.maximumResponseBytes)
    }

    func testAPISuppliedLinksAreIgnoredInFavorOfFixedReleasePage() throws {
        let response = validResponse(
            version: "1.4.0",
            extraFields: [
                "html_url": "https://attacker.invalid/release",
                "zipball_url": "https://attacker.invalid/archive"
            ]
        )
        let result = try GitHubReleaseClient(
            transport: StubSoftwareUpdateTransport(response: response)
        ).validate(response)

        guard case .release(let release, _) = result else {
            return XCTFail("Expected a validated release")
        }
        XCTAssertEqual(
            release.releasePageURL.absoluteString,
            "https://github.com/Reedtrullz/Vifty/releases/tag/v1.4.0"
        )
    }

    func testDraftPrereleaseMalformedVersionAndAssetDriftFailClosed() throws {
        let canonicalAssets = assetDictionaries(version: "1.4.0")
        let variants: [[String: Any]] = [
            payload(version: "1.4.0", draft: true),
            payload(version: "1.4.0", prerelease: true),
            payload(version: "1.4.0-beta"),
            payload(version: "01.4.0"),
            payload(version: "1.4.0", assets: Array(canonicalAssets.dropLast())),
            payload(version: "1.4.0", assets: canonicalAssets + [[
                "name": "unexpected.txt", "state": "uploaded", "size": 1
            ]]),
            payload(version: "1.4.0", assets: canonicalAssets.enumerated().map { index, asset in
                var asset = asset
                if index == 0 { asset["state"] = "new" }
                return asset
            }),
            payload(version: "1.4.0", assets: canonicalAssets.enumerated().map { index, asset in
                var asset = asset
                if index == 0 { asset["size"] = 0 }
                return asset
            }),
            payload(version: "1.4.0", assets: [
                canonicalAssets[0], canonicalAssets[0], canonicalAssets[2], canonicalAssets[3]
            ])
        ]

        let client = GitHubReleaseClient(
            transport: StubSoftwareUpdateTransport(response: validResponse(version: "1.4.0"))
        )
        for variant in variants {
            let invalidResponse = response(payload: variant)
            XCTAssertThrowsError(try client.validate(invalidResponse)) { error in
                XCTAssertEqual(error as? SoftwareUpdateError, .invalidReleasePayload)
            }
        }
    }

    func testResponseOriginTypeStatusAndSizeAreValidated() {
        let client = GitHubReleaseClient(
            transport: StubSoftwareUpdateTransport(response: validResponse(version: "1.4.0"))
        )
        var response = validResponse(version: "1.4.0")

        response = SoftwareUpdateHTTPResponse(
            statusCode: response.statusCode,
            finalURL: URL(string: "https://attacker.invalid/latest"),
            mimeType: response.mimeType,
            expectedContentLength: response.expectedContentLength,
            etag: response.etag,
            body: response.body
        )
        XCTAssertThrowsError(try client.validate(response)) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .unexpectedResponseURL)
        }

        response = validResponse(version: "1.4.0", mimeType: "text/html")
        XCTAssertThrowsError(try client.validate(response)) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .invalidContentType)
        }

        response = validResponse(version: "1.4.0", statusCode: 429)
        XCTAssertThrowsError(try client.validate(response)) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .httpStatus(429))
        }

        response = SoftwareUpdateHTTPResponse(
            statusCode: 200,
            finalURL: GitHubReleaseClient.endpoint,
            mimeType: "application/json",
            expectedContentLength: Int64(GitHubReleaseClient.maximumResponseBytes + 1),
            etag: nil,
            body: Data(repeating: 0, count: GitHubReleaseClient.maximumResponseBytes + 1)
        )
        XCTAssertThrowsError(try client.validate(response)) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .responseTooLarge)
        }
    }

    func testNotModifiedNeedsNoBodyOrContentType() throws {
        let response = SoftwareUpdateHTTPResponse(
            statusCode: 304,
            finalURL: GitHubReleaseClient.endpoint,
            mimeType: nil,
            expectedContentLength: 0,
            etag: nil,
            body: Data()
        )
        let client = GitHubReleaseClient(
            transport: StubSoftwareUpdateTransport(response: response)
        )
        XCTAssertEqual(try client.validate(response), .notModified)
    }

    func testTransportConfigurationIsEphemeralAndStateless() {
        let configuration = URLSessionSoftwareUpdateHTTPTransport.makeEphemeralConfiguration()

        XCTAssertEqual(configuration.timeoutIntervalForRequest, 10)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 15)
        XCTAssertEqual(
            configuration.requestCachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpAdditionalHeaders)
        XCTAssertFalse(configuration.waitsForConnectivity)
    }

    func testRedirectDelegateRefusesRedirectRequest() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://api.github.com/start"))
        let redirectURL = try XCTUnwrap(URL(string: "https://attacker.invalid/latest"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: sourceURL)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: sourceURL,
            statusCode: 302,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": redirectURL.absoluteString]
        ))
        var completionWasCalled = false
        var acceptedRedirect: URLRequest?

        SoftwareUpdateNoRedirectDelegate().urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: redirectURL)
        ) { request in
            completionWasCalled = true
            acceptedRedirect = request
        }

        XCTAssertTrue(completionWasCalled)
        XCTAssertNil(acceptedRedirect)
    }

    func testStreamAccumulatorRejectsFirstBytePastLimit() throws {
        var accumulator = SoftwareUpdateResponseAccumulator(
            maximumResponseBytes: 2,
            expectedContentLength: NSURLSessionTransferSizeUnknown
        )

        try accumulator.append(0x01)
        try accumulator.append(0x02)
        XCTAssertEqual(accumulator.body, Data([0x01, 0x02]))
        XCTAssertThrowsError(try accumulator.append(0x03)) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .responseTooLarge)
        }
        XCTAssertEqual(accumulator.body, Data([0x01, 0x02]))
    }

    func testProductionTransportRefusesRedirects() async throws {
        let server = try LocalSoftwareUpdateHTTPServer(mode: .redirect)
        defer { server.stop() }
        let transport = URLSessionSoftwareUpdateHTTPTransport(
            configuration: testTransportConfiguration()
        )
        let request = URLRequest(url: server.url)

        let response = try await transport.send(request, maximumResponseBytes: 128)

        XCTAssertEqual(response.statusCode, 302)
        XCTAssertEqual(response.finalURL, server.url)
        try server.waitUntilFinished()
        XCTAssertFalse(server.redirectWasFollowed)
    }

    func testProductionTransportCancelsStreamAtFirstBytePastLimit() async throws {
        let server = try LocalSoftwareUpdateHTTPServer(mode: .oversize)
        defer { server.stop() }
        let transport = URLSessionSoftwareUpdateHTTPTransport(
            configuration: testTransportConfiguration()
        )

        do {
            _ = try await transport.send(
                URLRequest(url: server.url),
                maximumResponseBytes: 2
            )
            XCTFail("Expected the streamed response to exceed the two-byte cap")
        } catch {
            XCTAssertEqual(error as? SoftwareUpdateError, .responseTooLarge)
        }
    }

    func testProductionTransportCancellationStopsHangingRequestPromptly() async throws {
        let server = try LocalSoftwareUpdateHTTPServer(mode: .hanging)
        defer { server.stop() }
        let transport = URLSessionSoftwareUpdateHTTPTransport(
            configuration: testTransportConfiguration()
        )
        let requestTask = Task {
            try await transport.send(
                URLRequest(url: server.url),
                maximumResponseBytes: 128
            )
        }
        try server.waitUntilAccepted()

        let cancellationStartedAt = Date()
        requestTask.cancel()
        do {
            _ = try await requestTask.value
            XCTFail("Expected cancellation to stop the hanging request")
        } catch is CancellationError {
            // Swift concurrency may surface direct task cancellation.
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancellationStartedAt), 1.5)
    }

    private func testTransportConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionSoftwareUpdateHTTPTransport.makeEphemeralConfiguration()
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        return configuration
    }

}

final class SoftwareUpdateStoreTests: XCTestCase {
    func testRoundTripUsesPrivatePermissionsAndTightensLegacyModes() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Vifty/software-update.json")
        let store = SoftwareUpdateStore(url: url)
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
        )
        let snapshot = SoftwareUpdateStoreSnapshot(
            schemaVersion: SoftwareUpdateStoreSnapshot.schemaVersion,
            automaticChecksEnabled: false,
            lastAttemptAt: Date(timeIntervalSince1970: 1_000),
            lastSuccessfulCheckAt: Date(timeIntervalSince1970: 2_000),
            etag: "\"etag\"",
            cachedRelease: release
        )

        try store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)
        XCTAssertEqual(try permissions(at: url.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(at: url), 0o600)

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: url.deletingLastPathComponent().path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: url.path
        )
        _ = store.load()
        XCTAssertEqual(try permissions(at: url.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(at: url), 0o600)
    }

    func testGroupOrWorldWritableLegacyStateIsRejectedWithoutTrustingOrRewritingIt() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Vifty", isDirectory: true)
        let url = directory.appendingPathComponent("software-update.json")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let poisoned = Data("""
        {
          "schemaVersion": 1,
          "automaticChecksEnabled": true,
          "cachedRelease": {"version": "99.0.0"}
        }
        """.utf8)
        try poisoned.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o666)],
            ofItemAtPath: url.path
        )
        let store = SoftwareUpdateStore(url: url)

        let loaded = store.load()

        XCTAssertFalse(loaded.automaticChecksEnabled)
        XCTAssertNil(loaded.cachedRelease)
        XCTAssertEqual(try permissions(at: url), 0o666)
        XCTAssertEqual(try Data(contentsOf: url), poisoned)
        XCTAssertThrowsError(try store.save(.defaults))
        XCTAssertEqual(try Data(contentsOf: url), poisoned)
    }

    func testMissingCorruptFutureSchemaAndNoncanonicalCachedVersionUseDefaults() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("software-update.json")
        let store = SoftwareUpdateStore(url: url)

        XCTAssertEqual(store.load(), .defaults)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)
        XCTAssertFalse(store.load().automaticChecksEnabled)

        let future = """
        {"schemaVersion":2,"automaticChecksEnabled":true}
        """
        try Data(future.utf8).write(to: url, options: .atomic)
        XCTAssertFalse(store.load().automaticChecksEnabled)

        let poisoned = """
        {
          "schemaVersion": 1,
          "automaticChecksEnabled": true,
          "cachedRelease": {"version": "-1.4.0"}
        }
        """
        try Data(poisoned.utf8).write(to: url, options: .atomic)
        XCTAssertFalse(store.load().automaticChecksEnabled)
    }

    func testLoadRejectsOversizedSymlinkAndFIFOStateWithoutFollowingOrBlocking() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("software-update.json")
        let store = SoftwareUpdateStore(url: url)

        try Data(repeating: 0, count: SoftwareUpdateStore.maximumFileBytes + 1).write(to: url)
        XCTAssertFalse(store.load().automaticChecksEnabled)
        try FileManager.default.removeItem(at: url)

        let target = root.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        XCTAssertFalse(store.load().automaticChecksEnabled)
        XCTAssertEqual(try Data(contentsOf: target), Data("{}".utf8))
        try FileManager.default.removeItem(at: url)

        XCTAssertEqual(mkfifo(url.path, 0o600), 0)
        XCTAssertFalse(store.load().automaticChecksEnabled)
    }

    func testOrphanedETagIsDiscardedWhenNoValidatedReleaseExists() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SoftwareUpdateStore(
            url: root.appendingPathComponent("software-update.json")
        )
        try store.save(SoftwareUpdateStoreSnapshot(
            schemaVersion: SoftwareUpdateStoreSnapshot.schemaVersion,
            automaticChecksEnabled: true,
            lastAttemptAt: nil,
            lastSuccessfulCheckAt: nil,
            etag: "\"orphaned\"",
            cachedRelease: nil
        ))

        XCTAssertNil(store.load().etag)
    }

    func testSymlinkedParentIsRejectedWithoutMutatingItsTarget() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target", isDirectory: true)
        let linkedParent = root.appendingPathComponent("Vifty", isDirectory: true)
        try FileManager.default.createDirectory(
            at: target,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let sentinel = target.appendingPathComponent("sentinel")
        try Data("unchanged".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: target
        )
        let store = SoftwareUpdateStore(
            url: linkedParent.appendingPathComponent("software-update.json")
        )

        XCTAssertFalse(store.load().automaticChecksEnabled)
        XCTAssertThrowsError(try store.save(.defaults))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("unchanged".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: target.appendingPathComponent("software-update.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: target.appendingPathComponent("software-update.owner.lock").path
            )
        )
    }

    func testOnlyOneStoreInstanceCanOwnSharedPersistentState() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Vifty/software-update.json")
        var first: SoftwareUpdateStore? = SoftwareUpdateStore(url: url)
        let second = SoftwareUpdateStore(url: url)

        XCTAssertTrue(try XCTUnwrap(first).load().automaticChecksEnabled)
        XCTAssertFalse(second.load().automaticChecksEnabled)
        XCTAssertThrowsError(try second.save(.defaults))

        var optedOut = SoftwareUpdateStoreSnapshot.defaults
        optedOut.automaticChecksEnabled = false
        try XCTUnwrap(first).save(optedOut)
        XCTAssertFalse(try XCTUnwrap(first).load().automaticChecksEnabled)

        first = nil
        XCTAssertThrowsError(
            try second.save(.defaults),
            "an instance denied during load must remain fail-closed until relaunch"
        )

        let relaunched = SoftwareUpdateStore(url: url)
        XCTAssertFalse(relaunched.load().automaticChecksEnabled)
        try relaunched.save(.defaults)
        XCTAssertTrue(relaunched.load().automaticChecksEnabled)
    }

    func testDataVolumePathAliasCannotBypassSameProcessOwnership() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard repositoryRoot.path.hasPrefix("/Users/") else {
            throw XCTSkip("The macOS Data-volume alias applies to /Users paths")
        }
        let root = repositoryRoot
            .appendingPathComponent(".build/test-scratch/software-update-alias")
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let primaryURL = root.appendingPathComponent("Vifty/software-update.json")
        let aliasURL = URL(
            fileURLWithPath: "/System/Volumes/Data" + primaryURL.path,
            isDirectory: false
        )
        let first = SoftwareUpdateStore(url: primaryURL)

        XCTAssertTrue(first.load().automaticChecksEnabled)
        guard FileManager.default.fileExists(
            atPath: aliasURL.deletingLastPathComponent().path
        ) else {
            throw XCTSkip("The host does not expose the /System/Volumes/Data alias")
        }
        let second = SoftwareUpdateStore(url: aliasURL)
        XCTAssertFalse(second.load().automaticChecksEnabled)
        XCTAssertThrowsError(try second.save(.defaults))
    }

    func testStoreFileLockExcludesAnotherProcessAndReleasesOnDeinit() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Vifty/software-update.json")
        let lockURL = url.deletingLastPathComponent()
            .appendingPathComponent("software-update.owner.lock")
        var store: SoftwareUpdateStore? = SoftwareUpdateStore(url: url)

        XCTAssertTrue(try XCTUnwrap(store).load().automaticChecksEnabled)
        XCTAssertEqual(try Self.runFileLockHelper(lockURL), 75)

        store = nil
        XCTAssertEqual(try Self.runFileLockHelper(lockURL), 0)
    }

    func testAnchoredDirectoryReplacementPermanentlyDeniesStaleStore() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Vifty", isDirectory: true)
        let movedDirectory = root.appendingPathComponent("Vifty-old", isDirectory: true)
        let url = directory.appendingPathComponent("software-update.json")
        let staleStore = SoftwareUpdateStore(url: url)

        XCTAssertTrue(staleStore.load().automaticChecksEnabled)
        try FileManager.default.moveItem(at: directory, to: movedDirectory)

        var replacementStore: SoftwareUpdateStore? = SoftwareUpdateStore(url: url)
        var replacementSnapshot = SoftwareUpdateStoreSnapshot.defaults
        replacementSnapshot.automaticChecksEnabled = false
        replacementSnapshot.lastAttemptAt = Date(timeIntervalSince1970: 42_000)
        try XCTUnwrap(replacementStore).save(replacementSnapshot)
        replacementStore = nil

        XCTAssertThrowsError(try staleStore.save(.defaults))
        XCTAssertFalse(staleStore.load().automaticChecksEnabled)

        let relaunched = SoftwareUpdateStore(url: url)
        XCTAssertEqual(relaunched.load(), replacementSnapshot)
    }

    private static func runFileLockHelper(_ lockURL: URL) throws -> Int32 {
        let productsDirectory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        let helper = productsDirectory.appendingPathComponent("ViftyLockTestHelper")
        var metadata = stat()
        guard lstat(helper.path, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw NSError(
                domain: "SoftwareUpdateStoreTests",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "ViftyLockTestHelper is not a regular executable sibling of the test bundle"
                ]
            )
        }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["attemptFileLock", lockURL.path, String(geteuid())]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

@MainActor
final class SoftwareUpdateControllerTests: XCTestCase {
    func testManualCheckWorksWhenAutomaticChecksAreOffAndFindsNewerRelease() async throws {
        let fetcher = StubSoftwareUpdateFetcher(outcomes: [
            .result(.release(
                SoftwareUpdateRelease(
                    version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
                ),
                etag: "\"etag\""
            ))
        ])
        let controller = makeController(fetcher: fetcher)
        controller.setAutomaticChecksEnabled(false)

        await controller.checkNow()

        XCTAssertEqual(
            controller.status,
            .updateAvailable(SoftwareUpdateRelease(
                version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
            ))
        )
        let callCount = await fetcher.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testIneligibleBuildNeverFetchesForStartOrManualCheck() async {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fetcher = StubSoftwareUpdateFetcher(outcomes: [])
        let controller = makeController(
            fetcher: fetcher,
            configuration: .resolve(
                bundleIdentifier: "tech.reidar.vifty",
                bundleVersion: "1.3.2",
                signatureIsEligible: false,
                initialDelay: 0,
                checkInterval: 10
            ),
            store: SoftwareUpdateStore(
                url: root.appendingPathComponent("Vifty/software-update.json")
            )
        )

        controller.start()
        await controller.checkNow()

        XCTAssertEqual(controller.status, .unavailable)
        let callCount = await fetcher.callCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testOnlyOwningControllerCanRequestWithSharedPersistentState() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Vifty/software-update.json")
        let firstFetcher = StubSoftwareUpdateFetcher(outcomes: [
            .result(.release(
                SoftwareUpdateRelease(
                    version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.3.2"))
                ),
                etag: nil
            ))
        ])
        let secondFetcher = StubSoftwareUpdateFetcher(outcomes: [
            .result(.notModified)
        ])
        let sleeper = ManualSoftwareUpdateSleeper()
        let first = makeController(
            fetcher: firstFetcher,
            store: SoftwareUpdateStore(url: url),
            sleep: { seconds in try await sleeper.sleep(seconds) }
        )
        let second = makeController(
            fetcher: secondFetcher,
            store: SoftwareUpdateStore(url: url)
        )

        XCTAssertTrue(first.automaticChecksEnabled)
        XCTAssertFalse(second.automaticChecksEnabled)
        await second.checkNow()
        let blockedCallCount = await secondFetcher.callCount()
        XCTAssertEqual(blockedCallCount, 0)
        guard case .failed = second.status else {
            return XCTFail("The non-owning controller must fail before a request")
        }

        first.start()
        _ = await sleeper.nextRequestedDelay()
        await sleeper.resumeNext()
        await firstFetcher.waitForCall(count: 1)
        let firstCallCount = await firstFetcher.callCount()
        let secondCallCount = await secondFetcher.callCount()
        XCTAssertEqual(firstCallCount, 1)
        XCTAssertEqual(secondCallCount, 0)

        first.stop()
        second.stop()
        await sleeper.cancelAll()
    }

    func testSameOrOlderReleaseReportsCurrentVersionUpToDate() async throws {
        for tag in ["v1.3.2", "v1.2.9"] {
            let fetcher = StubSoftwareUpdateFetcher(outcomes: [
                .result(.release(
                    SoftwareUpdateRelease(version: try XCTUnwrap(ViftyReleaseVersion(tag: tag))),
                    etag: nil
                ))
            ])
            let controller = makeController(fetcher: fetcher)
            await controller.checkNow()
            guard case .upToDate = controller.status else {
                return XCTFail("Expected \(tag) not to supersede 1.3.2")
            }
            controller.stop()
        }
    }

    func testNotModifiedUsesValidatedCacheAndFailsWithoutIt() async throws {
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
        )
        let cachedStore = temporaryStore()
        try cachedStore.save(SoftwareUpdateStoreSnapshot(
            schemaVersion: SoftwareUpdateStoreSnapshot.schemaVersion,
            automaticChecksEnabled: true,
            lastAttemptAt: nil,
            lastSuccessfulCheckAt: nil,
            etag: "\"cached\"",
            cachedRelease: release
        ))
        let cachedFetcher = StubSoftwareUpdateFetcher(outcomes: [.result(.notModified)])
        let cachedController = makeController(fetcher: cachedFetcher, store: cachedStore)
        await cachedController.checkNow()
        XCTAssertEqual(cachedController.status, .updateAvailable(release))
        let calls = await cachedFetcher.recordedCalls()
        XCTAssertEqual(calls.first?.etag, "\"cached\"")
        cachedController.stop()

        let emptyController = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: [.result(.notModified)])
        )
        await emptyController.checkNow()
        guard case .failed(let message) = emptyController.status else {
            return XCTFail("Expected a missing-cache 304 to fail closed")
        }
        XCTAssertTrue(message.contains("no validated release cached"))
        emptyController.stop()
    }

    func testOrphanedNotModifiedResponseClearsETagAndNextCheckCanRecover() async throws {
        let store = temporaryStore()
        try store.save(SoftwareUpdateStoreSnapshot(
            schemaVersion: SoftwareUpdateStoreSnapshot.schemaVersion,
            automaticChecksEnabled: true,
            lastAttemptAt: nil,
            lastSuccessfulCheckAt: nil,
            etag: "\"orphaned\"",
            cachedRelease: nil
        ))
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
        )
        let fetcher = StubSoftwareUpdateFetcher(outcomes: [
            .result(.notModified),
            .result(.release(release, etag: "\"recovered\""))
        ])
        let controller = makeController(fetcher: fetcher, store: store)

        await controller.checkNow()
        guard case .failed = controller.status else {
            return XCTFail("Expected the orphaned 304 to fail closed")
        }
        await controller.checkNow()

        XCTAssertEqual(controller.status, .updateAvailable(release))
        let calls = await fetcher.recordedCalls()
        XCTAssertEqual(calls.map(\.etag), [nil, nil])
        controller.stop()
    }

    func testUpdateActionOpensOnlyLocallyConstructedCanonicalPage() async throws {
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
        )
        let store = temporaryStore()
        try store.save(SoftwareUpdateStoreSnapshot(
            schemaVersion: SoftwareUpdateStoreSnapshot.schemaVersion,
            automaticChecksEnabled: false,
            lastAttemptAt: nil,
            lastSuccessfulCheckAt: nil,
            etag: nil,
            cachedRelease: release
        ))
        let opener = RecordingSoftwareUpdatePageOpener()
        let controller = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: []),
            store: store,
            opener: opener
        )

        XCTAssertEqual(controller.primaryActionTitle, "Update to latest version")
        XCTAssertEqual(controller.menuActionTitle, "Update to Latest Version…")
        await controller.performPrimaryAction()

        XCTAssertEqual(opener.openedURLs, [release.releasePageURL])
    }

    func testRateLimitAndNetworkErrorsUseNontechnicalMessages() async {
        let limited = makeController(fetcher: StubSoftwareUpdateFetcher(outcomes: [
            .softwareError(.httpStatus(429))
        ]))
        await limited.checkNow()
        XCTAssertEqual(
            limited.errorMessage,
            "GitHub temporarily limited update checks. Try again later."
        )
        limited.stop()

        let offline = makeController(fetcher: StubSoftwareUpdateFetcher(outcomes: [
            .urlError(.notConnectedToInternet)
        ]))
        await offline.checkNow()
        XCTAssertEqual(
            offline.errorMessage,
            "Couldn't reach GitHub. Check your internet connection and try again."
        )
        offline.stop()
    }

    func testUnwritableAttemptStateFailsClosedBeforeAnyRequest() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("blocking-file".utf8).write(to: root)
        let fetcher = StubSoftwareUpdateFetcher(outcomes: [
            .result(.notModified)
        ])
        let controller = makeController(
            fetcher: fetcher,
            store: SoftwareUpdateStore(
                url: root.appendingPathComponent("software-update.json")
            )
        )

        await controller.checkNow()

        let callCount = await fetcher.callCount()
        XCTAssertEqual(callCount, 0)
        guard case .failed(let message) = controller.status else {
            return XCTFail("Expected persistence failure to block the request")
        }
        XCTAssertTrue(message.contains("no request was sent"))
        XCTAssertNil(controller.errorMessage)
        controller.stop()
    }

    func testRepeatedAttemptPersistenceFailurePublishesFreshAnnouncement() async {
        let controller = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: []),
            store: FailingSoftwareUpdateStore(snapshot: .defaults)
        )

        await controller.checkNow()
        XCTAssertNil(controller.errorAnnouncement)
        await controller.checkNow()
        let secondAnnouncement = controller.errorAnnouncement
        XCTAssertEqual(secondAnnouncement?.message, controller.statusText)
        await controller.checkNow()
        XCTAssertNotEqual(controller.errorAnnouncement?.id, secondAnnouncement?.id)
        controller.stop()
    }

    func testAttemptPersistenceFailurePreservesKnownNewerReleaseAction() async throws {
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
        )
        let store = SequencedSoftwareUpdateStore(
            initialSnapshot: SoftwareUpdateStoreSnapshot(
                schemaVersion: SoftwareUpdateStoreSnapshot.schemaVersion,
                automaticChecksEnabled: true,
                lastAttemptAt: nil,
                lastSuccessfulCheckAt: Date(timeIntervalSince1970: 1_000),
                etag: "\"cached\"",
                cachedRelease: release
            ),
            failingSaveNumbers: [1]
        )
        let fetcher = StubSoftwareUpdateFetcher(outcomes: [])
        let controller = makeController(fetcher: fetcher, store: store)

        await controller.checkNow()

        let callCount = await fetcher.callCount()
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(controller.status, .updateAvailable(release))
        XCTAssertEqual(controller.primaryActionTitle, "Update to latest version")
        XCTAssertEqual(
            controller.errorMessage,
            "Vifty couldn't save the update-check attempt, so no request was sent."
        )
        XCTAssertEqual(controller.errorAnnouncement?.message, controller.errorMessage)
        controller.stop()
    }

    func testResultPersistenceFailureKeepsSessionResultAndExplainsBoundary() async throws {
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
        )
        let store = SequencedSoftwareUpdateStore(failingSaveNumbers: [2])
        let controller = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: [
                .result(.release(release, etag: "\"fresh\""))
            ]),
            store: store
        )

        await controller.checkNow()

        XCTAssertEqual(controller.status, .updateAvailable(release))
        XCTAssertEqual(
            controller.errorMessage,
            "Vifty couldn't save update-check state. This result is available only for this session."
        )
        XCTAssertEqual(controller.errorAnnouncement?.message, controller.errorMessage)
        XCTAssertEqual(store.saveCount, 2)
        controller.stop()
    }

    func testUnwritableOptOutDisablesSessionWithoutClaimingRelaunchPersistence() throws {
        let store = FailingSoftwareUpdateStore(snapshot: .defaults)
        let controller = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: []),
            store: store
        )

        XCTAssertTrue(controller.automaticChecksEnabled)
        controller.setAutomaticChecksEnabled(false)

        XCTAssertFalse(controller.automaticChecksEnabled)
        XCTAssertEqual(
            controller.errorMessage,
            "Vifty couldn't save this preference for relaunch. "
                + "Automatic checks are off for this session."
        )
        let reloaded = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: []),
            store: store
        )
        XCTAssertTrue(reloaded.automaticChecksEnabled)
    }

    func testFailedOptOutPersistenceStillCancelsInFlightAutomaticCheck() async throws {
        let sleeper = ManualSoftwareUpdateSleeper()
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v9.0.0"))
        )
        let fetcher = GatedSoftwareUpdateFetcher(result: .release(release, etag: nil))
        let store = SequencedSoftwareUpdateStore(failingSaveNumbers: [2])
        let controller = makeController(
            fetcher: fetcher,
            store: store,
            sleep: { seconds in try await sleeper.sleep(seconds) }
        )

        controller.start()
        _ = await sleeper.nextRequestedDelay()
        await sleeper.resumeNext()
        await fetcher.waitUntilCalled()
        controller.setAutomaticChecksEnabled(false)

        XCTAssertFalse(controller.automaticChecksEnabled)
        XCTAssertFalse(controller.isChecking)
        XCTAssertEqual(controller.status, .ready)
        XCTAssertTrue(controller.errorMessage?.contains("off for this session") == true)

        await fetcher.release()
        await waitUntil { controller.settledCheckCount == 1 }
        XCTAssertEqual(controller.status, .ready)
        XCTAssertNil(controller.availableRelease)
        let requestedDelays = await sleeper.allRequestedDelays()
        XCTAssertEqual(requestedDelays, [5])
        await sleeper.cancelAll()
    }

    func testToggleChangedDuringManualFetchIsNotOverwrittenByResult() async throws {
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.4.0"))
        )
        let fetcher = GatedSoftwareUpdateFetcher(result: .release(release, etag: nil))
        let store = temporaryStore()
        let controller = makeController(fetcher: fetcher, store: store)

        let check = Task { @MainActor in
            await controller.checkNow()
        }
        await fetcher.waitUntilCalled()
        controller.setAutomaticChecksEnabled(false)
        await fetcher.release()
        await check.value

        XCTAssertFalse(controller.automaticChecksEnabled)
        XCTAssertFalse(store.load().automaticChecksEnabled)
        XCTAssertEqual(controller.status, .updateAvailable(release))
        controller.stop()
    }

    func testAutomaticSchedulerUsesInitialDelayThenDailyAttemptBoundary() async throws {
        let sleeper = ManualSoftwareUpdateSleeper()
        let fixedNow = Date(timeIntervalSince1970: 10_000)
        let fetcher = StubSoftwareUpdateFetcher(outcomes: [
            .result(.release(
                SoftwareUpdateRelease(
                    version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.3.2"))
                ),
                etag: nil
            ))
        ])
        let controller = makeController(
            fetcher: fetcher,
            configuration: eligibleConfiguration(initialDelay: 5, checkInterval: 86_400),
            now: { fixedNow },
            sleep: { seconds in try await sleeper.sleep(seconds) }
        )

        controller.start()
        controller.start()
        let initialDelay = await sleeper.nextRequestedDelay()
        XCTAssertEqual(initialDelay, 5)
        await sleeper.resumeNext()
        await fetcher.waitForCall(count: 1)
        let repeatDelay = await sleeper.nextRequestedDelay()
        XCTAssertEqual(repeatDelay, 86_400)

        controller.stop()
        await sleeper.cancelAll()
    }

    func testTurningAutomaticChecksOffInvalidatesCancellationIgnoringFetch() async throws {
        let sleeper = ManualSoftwareUpdateSleeper()
        let fetcher = GatedSoftwareUpdateFetcher(result: .release(
            SoftwareUpdateRelease(
                version: try XCTUnwrap(ViftyReleaseVersion(tag: "v9.0.0"))
            ),
            etag: nil
        ))
        let controller = makeController(
            fetcher: fetcher,
            configuration: eligibleConfiguration(initialDelay: 5, checkInterval: 86_400),
            sleep: { seconds in try await sleeper.sleep(seconds) }
        )

        controller.start()
        _ = await sleeper.nextRequestedDelay()
        await sleeper.resumeNext()
        await fetcher.waitUntilCalled()
        controller.setAutomaticChecksEnabled(false)
        XCTAssertFalse(controller.isChecking)
        XCTAssertEqual(controller.status, .ready)
        await fetcher.release()
        await waitUntil { controller.settledCheckCount == 1 }

        XCTAssertFalse(controller.automaticChecksEnabled)
        XCTAssertEqual(controller.status, .ready)
        XCTAssertNil(controller.availableRelease)
        await sleeper.cancelAll()
    }

    func testStopInvalidatesInFlightAutomaticCheckWithoutRescheduling() async throws {
        let sleeper = ManualSoftwareUpdateSleeper()
        let fetcher = GatedSoftwareUpdateFetcher(result: .release(
            SoftwareUpdateRelease(
                version: try XCTUnwrap(ViftyReleaseVersion(tag: "v9.0.0"))
            ),
            etag: nil
        ))
        let controller = makeController(
            fetcher: fetcher,
            sleep: { seconds in try await sleeper.sleep(seconds) }
        )

        controller.start()
        _ = await sleeper.nextRequestedDelay()
        await sleeper.resumeNext()
        await fetcher.waitUntilCalled()
        controller.stop()
        XCTAssertFalse(controller.isChecking)
        XCTAssertEqual(controller.status, .ready)

        await fetcher.release()
        await waitUntil { controller.settledCheckCount == 1 }
        let requestedDelays = await sleeper.allRequestedDelays()
        XCTAssertEqual(requestedDelays, [5])
        XCTAssertEqual(controller.status, .ready)
        XCTAssertNil(controller.availableRelease)
        await sleeper.cancelAll()
    }

    func testFuturePersistedAttemptCannotSuppressChecks() async throws {
        let sleeper = ManualSoftwareUpdateSleeper()
        let now = Date(timeIntervalSince1970: 1_000)
        let store = temporaryStore()
        try store.save(SoftwareUpdateStoreSnapshot(
            schemaVersion: SoftwareUpdateStoreSnapshot.schemaVersion,
            automaticChecksEnabled: true,
            lastAttemptAt: Date(timeIntervalSince1970: 99_999),
            lastSuccessfulCheckAt: nil,
            etag: nil,
            cachedRelease: nil
        ))
        let controller = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: []),
            store: store,
            now: { now },
            sleep: { seconds in try await sleeper.sleep(seconds) }
        )

        controller.start()
        let initialDelay = await sleeper.nextRequestedDelay()
        XCTAssertEqual(initialDelay, 86_400)
        controller.stop()
        await sleeper.cancelAll()
    }

    func testFuturePersistedAttemptSurvivesRollbackAndCorrectionAcrossRelaunch() async throws {
        let futureAttempt = Date(timeIntervalSince1970: 100_000)
        let clock = SoftwareUpdateTestClock(Date(timeIntervalSince1970: 13_600))
        let store = SequencedSoftwareUpdateStore(
            initialSnapshot: SoftwareUpdateStoreSnapshot(
                schemaVersion: SoftwareUpdateStoreSnapshot.schemaVersion,
                automaticChecksEnabled: true,
                lastAttemptAt: futureAttempt,
                lastSuccessfulCheckAt: nil,
                etag: nil,
                cachedRelease: nil
            ),
            failingSaveNumbers: []
        )
        let rolledBackSleeper = ManualSoftwareUpdateSleeper()
        var rolledBackController: SoftwareUpdateController? = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: []),
            store: store,
            now: { clock.value },
            sleep: { seconds in try await rolledBackSleeper.sleep(seconds) }
        )

        rolledBackController?.start()
        let rollbackDelay = await rolledBackSleeper.nextRequestedDelay()
        XCTAssertEqual(rollbackDelay, 86_400)
        rolledBackController?.stop()
        rolledBackController = nil
        await rolledBackSleeper.cancelAll()
        XCTAssertEqual(store.load().lastAttemptAt, futureAttempt)

        clock.value = futureAttempt
        let correctedSleeper = ManualSoftwareUpdateSleeper()
        let correctedController = makeController(
            fetcher: StubSoftwareUpdateFetcher(outcomes: []),
            store: store,
            now: { clock.value },
            sleep: { seconds in try await correctedSleeper.sleep(seconds) }
        )
        correctedController.start()
        let correctedDelay = await correctedSleeper.nextRequestedDelay()
        XCTAssertEqual(correctedDelay, 86_400)
        correctedController.stop()
        await correctedSleeper.cancelAll()
    }

    func testRuntimeClockRollbackKeepsFullAutomaticCheckInterval() async throws {
        let sleeper = ManualSoftwareUpdateSleeper()
        let clock = SoftwareUpdateTestClock(Date(timeIntervalSince1970: 10_000))
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.3.2"))
        )
        let fetcher = GatedSoftwareUpdateFetcher(result: .release(release, etag: nil))
        let controller = makeController(
            fetcher: fetcher,
            configuration: eligibleConfiguration(initialDelay: 5, checkInterval: 86_400),
            now: { clock.value },
            sleep: { seconds in try await sleeper.sleep(seconds) }
        )

        controller.start()
        let initialDelay = await sleeper.nextRequestedDelay()
        XCTAssertEqual(initialDelay, 5)
        await sleeper.resumeNext()
        await fetcher.waitUntilCalled()
        clock.value = Date(timeIntervalSince1970: 9_000)
        await fetcher.release()

        let repeatDelay = await sleeper.nextRequestedDelay()
        XCTAssertEqual(repeatDelay, 86_400)
        controller.stop()
        await sleeper.cancelAll()
    }

    func testRuntimeClockJumpForwardCannotShortenMonotonicCheckInterval() async throws {
        let sleeper = ManualSoftwareUpdateSleeper()
        let clock = SoftwareUpdateTestClock(Date(timeIntervalSince1970: 10_000))
        let uptime = SoftwareUpdateTestUptime(100)
        let release = SoftwareUpdateRelease(
            version: try XCTUnwrap(ViftyReleaseVersion(tag: "v1.3.2"))
        )
        let fetcher = GatedSoftwareUpdateFetcher(result: .release(release, etag: nil))
        let controller = makeController(
            fetcher: fetcher,
            configuration: eligibleConfiguration(initialDelay: 5, checkInterval: 86_400),
            now: { clock.value },
            monotonicNow: { uptime.value },
            sleep: { seconds in try await sleeper.sleep(seconds) }
        )

        controller.start()
        let initialDelay = await sleeper.nextRequestedDelay()
        XCTAssertEqual(initialDelay, 5)
        await sleeper.resumeNext()
        await fetcher.waitUntilCalled()
        clock.value = Date(timeIntervalSince1970: 200_000)
        await fetcher.release()

        let repeatDelay = await sleeper.nextRequestedDelay()
        XCTAssertEqual(repeatDelay, 86_400)
        controller.stop()
        await sleeper.cancelAll()
    }

    private func makeController(
        fetcher: any SoftwareUpdateReleaseFetching,
        configuration: SoftwareUpdateConfiguration = eligibleConfiguration(),
        store: (any SoftwareUpdateStateStoring)? = nil,
        opener: RecordingSoftwareUpdatePageOpener = RecordingSoftwareUpdatePageOpener(),
        now: @escaping @Sendable () -> Date = Date.init,
        monotonicNow: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in
            try await Task.sleep(for: .seconds(3_600))
        }
    ) -> SoftwareUpdateController {
        SoftwareUpdateController(
            configuration: configuration,
            client: fetcher,
            store: store ?? temporaryStore(),
            pageOpener: opener,
            now: now,
            monotonicNow: monotonicNow,
            sleep: sleep
        )
    }
}

private actor StubSoftwareUpdateTransport: SoftwareUpdateHTTPTransport {
    private let response: SoftwareUpdateHTTPResponse
    private var requests: [URLRequest] = []
    private var maximumResponseBytes: [Int] = []

    init(response: SoftwareUpdateHTTPResponse) {
        self.response = response
    }

    func send(
        _ request: URLRequest,
        maximumResponseBytes: Int
    ) async throws -> SoftwareUpdateHTTPResponse {
        requests.append(request)
        self.maximumResponseBytes.append(maximumResponseBytes)
        return response
    }

    func requestCount() -> Int {
        requests.count
    }

    func lastMaximumResponseBytes() -> Int? {
        maximumResponseBytes.last
    }
}

private final class LocalSoftwareUpdateHTTPServer: @unchecked Sendable {
    enum Mode: String {
        case redirect
        case oversize
        case hanging
    }

    private static let script = #"""
    require "socket"

    port_path, accepted_path, finished_path, redirect_path, mode = ARGV
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    File.write(port_path, port.to_s)

    client = nil
    begin
      client = server.accept
      request = +""
      loop do
        request << client.readpartial(4096)
        break if request.include?("\r\n\r\n")
      end

      case mode
      when "redirect"
        location = "http://127.0.0.1:#{port}/redirected"
        client.write(
          "HTTP/1.1 302 Found\r\n" \
          "Location: #{location}\r\n" \
          "Content-Length: 0\r\n" \
          "Connection: close\r\n\r\n"
        )
        client.flush
        File.write(accepted_path, "accepted")
        client.close
        client = nil

        if IO.select([server], nil, nil, 0.75)
          redirected = server.accept
          File.write(redirect_path, "followed")
          begin
            redirected.readpartial(4096)
          rescue EOFError
          end
          redirected.write(
            "HTTP/1.1 200 OK\r\n" \
            "Content-Type: application/json\r\n" \
            "Content-Length: 2\r\n" \
            "Connection: close\r\n\r\n{}"
          )
          redirected.close
        end
      when "oversize"
        client.write(
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: application/json\r\n" \
          "Transfer-Encoding: chunked\r\n" \
          "Connection: close\r\n\r\n"
        )
        client.flush
        File.write(accepted_path, "accepted")
        client.write("2\r\nab\r\n")
        client.flush
        sleep 0.05
        client.write("1\r\nc\r\n0\r\n\r\n")
        client.flush
      when "hanging"
        client.write(
          "HTTP/1.1 200 OK\r\n" \
          "Content-Type: application/json\r\n" \
          "Transfer-Encoding: chunked\r\n" \
          "Connection: close\r\n\r\n"
        )
        client.flush
        File.write(accepted_path, "accepted")
        client.write("1\r\n{\r\n")
        client.flush
        sleep 30
      else
        raise "unknown mode"
      end
    rescue EOFError, Errno::EPIPE, Errno::ECONNRESET
    ensure
      client.close rescue nil
      server.close rescue nil
      File.write(finished_path, "finished") rescue nil
    end
    """#

    private let process = Process()
    private let standardError = Pipe()
    private let root: URL
    private let portFile: URL
    private let acceptedFile: URL
    private let finishedFile: URL
    private let redirectFile: URL
    private var stopped = false

    let url: URL

    init(mode: Mode) throws {
        root = temporaryRoot().appendingPathComponent("http-server", isDirectory: true)
        portFile = root.appendingPathComponent("port")
        acceptedFile = root.appendingPathComponent("accepted")
        finishedFile = root.appendingPathComponent("finished")
        redirectFile = root.appendingPathComponent("redirect-followed")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ruby", "-e", Self.script,
            portFile.path, acceptedFile.path, finishedFile.path,
            redirectFile.path, mode.rawValue
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = standardError
        try process.run()

        do {
            try Self.waitForFile(portFile, process: process, standardError: standardError)
            let portText = try String(contentsOf: portFile, encoding: .utf8)
            guard let port = UInt16(portText),
                  let serverURL = URL(string: "http://127.0.0.1:\(port)/latest") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            url = serverURL
        } catch {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    var redirectWasFollowed: Bool {
        FileManager.default.fileExists(atPath: redirectFile.path)
    }

    func waitUntilAccepted() throws {
        try Self.waitForFile(acceptedFile, process: process, standardError: standardError)
    }

    func waitUntilFinished() throws {
        try Self.waitForFile(finishedFile, process: process, standardError: standardError)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: root)
    }

    deinit {
        stop()
    }

    private static func waitForFile(
        _ url: URL,
        process: Process,
        standardError: Pipe,
        timeout: TimeInterval = 3
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            if !process.isRunning {
                process.waitUntilExit()
                let data = standardError.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: data, as: UTF8.self)
                throw NSError(
                    domain: "LocalSoftwareUpdateHTTPServer",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "LocalSoftwareUpdateHTTPServer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(url.lastPathComponent)"]
            )
        }
    }
}

private final class FailingSoftwareUpdateStore: SoftwareUpdateStateStoring, @unchecked Sendable {
    private let snapshot: SoftwareUpdateStoreSnapshot

    init(snapshot: SoftwareUpdateStoreSnapshot) {
        self.snapshot = snapshot
    }

    func load() -> SoftwareUpdateStoreSnapshot {
        snapshot
    }

    func save(_ snapshot: SoftwareUpdateStoreSnapshot) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

private final class SequencedSoftwareUpdateStore: SoftwareUpdateStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: SoftwareUpdateStoreSnapshot
    private let failingSaveNumbers: Set<Int>
    private var storedSaveCount = 0

    init(
        initialSnapshot: SoftwareUpdateStoreSnapshot = .defaults,
        failingSaveNumbers: Set<Int>
    ) {
        snapshot = initialSnapshot
        self.failingSaveNumbers = failingSaveNumbers
    }

    var saveCount: Int {
        lock.withLock { storedSaveCount }
    }

    func load() -> SoftwareUpdateStoreSnapshot {
        lock.withLock { snapshot }
    }

    func save(_ snapshot: SoftwareUpdateStoreSnapshot) throws {
        try lock.withLock {
            storedSaveCount += 1
            if failingSaveNumbers.contains(storedSaveCount) {
                throw CocoaError(.fileWriteNoPermission)
            }
            self.snapshot = snapshot
        }
    }
}

private actor StubSoftwareUpdateFetcher: SoftwareUpdateReleaseFetching {
    struct Call: Equatable, Sendable {
        let currentVersion: ViftyReleaseVersion
        let etag: String?
    }

    enum Outcome: Sendable {
        case result(SoftwareUpdateFetchResult)
        case softwareError(SoftwareUpdateError)
        case urlError(URLError.Code)
    }

    private var outcomes: [Outcome]
    private var calls: [Call] = []
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func fetchLatest(
        currentVersion: ViftyReleaseVersion,
        etag: String?
    ) async throws -> SoftwareUpdateFetchResult {
        calls.append(Call(currentVersion: currentVersion, etag: etag))
        let ready = callWaiters.filter { calls.count >= $0.0 }
        callWaiters.removeAll { calls.count >= $0.0 }
        ready.forEach { $0.1.resume() }
        guard !outcomes.isEmpty else {
            throw SoftwareUpdateError.invalidReleasePayload
        }
        let outcome = outcomes.removeFirst()
        switch outcome {
        case .result(let result):
            return result
        case .softwareError(let error):
            throw error
        case .urlError(let code):
            throw URLError(code)
        }
    }

    func callCount() -> Int {
        calls.count
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func waitForCall(count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((count, continuation))
        }
    }
}

private actor GatedSoftwareUpdateFetcher: SoftwareUpdateReleaseFetching {
    private let result: SoftwareUpdateFetchResult
    private var called = false
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(result: SoftwareUpdateFetchResult) {
        self.result = result
    }

    func fetchLatest(
        currentVersion: ViftyReleaseVersion,
        etag: String?
    ) async throws -> SoftwareUpdateFetchResult {
        called = true
        callWaiters.forEach { $0.resume() }
        callWaiters.removeAll()
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
        return result
    }

    func waitUntilCalled() async {
        guard !called else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append(continuation)
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private final class RecordingSoftwareUpdatePageOpener: SoftwareUpdatePageOpening {
    var openedURLs: [URL] = []
    var result = true

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return result
    }
}

private final class SoftwareUpdateTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) {
        storedValue = value
    }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class SoftwareUpdateTestUptime: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: TimeInterval

    init(_ value: TimeInterval) {
        storedValue = value
    }

    var value: TimeInterval {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private actor ManualSoftwareUpdateSleeper {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var requestedDelays: [TimeInterval] = []
    private var allDelays: [TimeInterval] = []
    private var delayWaiters: [CheckedContinuation<TimeInterval, Never>] = []
    private var sleepWaiters: [Waiter] = []
    private var cancelledWaiterIDs: Set<UUID> = []

    func sleep(_ seconds: TimeInterval) async throws {
        let id = UUID()
        allDelays.append(seconds)
        if !delayWaiters.isEmpty {
            delayWaiters.removeFirst().resume(returning: seconds)
        } else {
            requestedDelays.append(seconds)
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if cancelledWaiterIDs.remove(id) != nil {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepWaiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func nextRequestedDelay() async -> TimeInterval {
        if !requestedDelays.isEmpty {
            return requestedDelays.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            delayWaiters.append(continuation)
        }
    }

    func resumeNext() {
        guard !sleepWaiters.isEmpty else { return }
        sleepWaiters.removeFirst().continuation.resume()
    }

    func cancelAll() {
        let waiters = sleepWaiters
        sleepWaiters.removeAll()
        waiters.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }

    func allRequestedDelays() -> [TimeInterval] {
        allDelays
    }

    private func cancel(id: UUID) {
        if let index = sleepWaiters.firstIndex(where: { $0.id == id }) {
            sleepWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
        } else {
            cancelledWaiterIDs.insert(id)
        }
    }
}

private func eligibleConfiguration(
    initialDelay: TimeInterval = 5,
    checkInterval: TimeInterval = 86_400
) -> SoftwareUpdateConfiguration {
    .resolve(
        bundleIdentifier: "tech.reidar.vifty",
        bundleVersion: "1.3.2",
        signatureIsEligible: true,
        initialDelay: initialDelay,
        checkInterval: checkInterval
    )
}

private func temporaryStore() -> SoftwareUpdateStore {
    SoftwareUpdateStore(
        url: temporaryRoot()
            .appendingPathComponent("Vifty")
            .appendingPathComponent("software-update.json")
    )
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vifty-software-update-tests")
        .appendingPathComponent(UUID().uuidString)
}

private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private func validResponse(
    version: String,
    statusCode: Int = 200,
    mimeType: String? = "application/json",
    etag: String? = nil,
    extraFields: [String: Any] = [:]
) -> SoftwareUpdateHTTPResponse {
    response(
        statusCode: statusCode,
        mimeType: mimeType,
        etag: etag,
        payload: payload(version: version, extraFields: extraFields)
    )
}

private func response(
    statusCode: Int = 200,
    mimeType: String? = "application/json",
    etag: String? = nil,
    payload: [String: Any]
) -> SoftwareUpdateHTTPResponse {
    let body = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    return SoftwareUpdateHTTPResponse(
        statusCode: statusCode,
        finalURL: GitHubReleaseClient.endpoint,
        mimeType: mimeType,
        expectedContentLength: Int64(body.count),
        etag: etag,
        body: body
    )
}

private func payload(
    version: String,
    draft: Bool = false,
    prerelease: Bool = false,
    assets: [[String: Any]]? = nil,
    extraFields: [String: Any] = [:]
) -> [String: Any] {
    var value: [String: Any] = [
        "tag_name": "v\(version)",
        "draft": draft,
        "prerelease": prerelease,
        "assets": assets ?? assetDictionaries(version: version)
    ]
    for (key, item) in extraFields {
        value[key] = item
    }
    return value
}

private func assetDictionaries(version: String) -> [[String: Any]] {
    [
        "Vifty-v\(version).zip",
        "Vifty-v\(version).zip.sha256",
        "Vifty-v\(version)-artifact-summary.json",
        "Vifty-v\(version)-release-checklist.md"
    ].map { name in
        ["name": name, "state": "uploaded", "size": 1]
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repositoryRoot.appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 1,
    condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        await Task.yield()
    }
}
