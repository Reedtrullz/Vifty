import Foundation
import XCTest
@testable import Vifty

@MainActor
final class DaemonInstallerTests: XCTestCase {
    func testHelperActionPresentationComesFromBackendStateInsteadOfStatusCopy() {
        let cases: [(DaemonInstallerBackendStatus, String, HelperActionKind)] = [
            (.notRegistered, "Install Helper", .install),
            (.requiresApproval, "Approve Helper", .approve),
            (.enabled, "Reinstall Helper", .reinstall),
            (.unknown, "Helper Status Unknown", .unavailable)
        ]

        for (status, title, kind) in cases {
            let installer = DaemonInstaller(
                backend: InstallerBackendFixture(status: status),
                installService: InstallerServiceFixture(result: .blockedResult)
            )
            installer.statusText = "arbitrary localized or transient copy"

            XCTAssertEqual(installer.actionPresentation.kind, kind)
            XCTAssertEqual(installer.actionPresentation.title, title)
        }
    }

    func testUnavailableHelperActionIsStructuredAndNonActionable() {
        let installer = DaemonInstaller(
            backend: InstallerBackendFixture(status: .notFound),
            installService: InstallerServiceFixture(result: .blockedResult)
        )
        installer.refresh()

        XCTAssertEqual(installer.actionPresentation.kind, .unavailable)
        XCTAssertEqual(installer.actionPresentation.title, "Helper Unavailable")
        XCTAssertFalse(installer.actionPresentation.isAvailable)
    }

    func testWorkingHelperKeepsAccurateActionNameButDisablesReentry() {
        let presentation = HelperActionPresentation.resolve(
            backendStatus: .enabled,
            canInstall: false,
            isWorking: true,
            unavailableMessage: "unavailable"
        )

        XCTAssertEqual(presentation.kind, .reinstall)
        XCTAssertEqual(presentation.title, "Reinstall Helper")
        XCTAssertFalse(presentation.isAvailable)
    }

    func testHelperActionCopyDescribesVerifiedLifecycle() {
        let backend = InstallerBackendFixture(status: .notRegistered)
        let installer = DaemonInstaller(
            backend: backend,
            installService: InstallerServiceFixture(result: .blockedResult)
        )

        installer.refresh()
        XCTAssertEqual(installer.actionTitle, "Install Helper")
        XCTAssertTrue(installer.actionDescription.contains("Registers the bundled root LaunchDaemon"))
        XCTAssertFalse(installer.actionDescription.contains("ownership preflight"))

        backend.status = .enabled
        installer.refresh()
        XCTAssertEqual(installer.actionTitle, "Reinstall Helper")
        XCTAssertEqual(installer.actionHelp, "Safely reinstall or repair the privileged fan helper")
        XCTAssertTrue(installer.actionDescription.contains("before any helper teardown or replacement"))
    }

    func testUnknownHelperStatusDoesNotOfferARepairActionThatAlwaysBlocks() {
        let installer = DaemonInstaller(
            backend: InstallerBackendFixture(status: .unknown),
            installService: InstallerServiceFixture(result: .blockedResult)
        )

        installer.refresh()

        XCTAssertEqual(installer.actionPresentation.kind, .unavailable)
        XCTAssertEqual(installer.actionPresentation.title, "Helper Status Unknown")
        XCTAssertFalse(installer.actionPresentation.isAvailable)
        XCTAssertTrue(installer.actionPresentation.description.contains("confirmed registration state"))
    }

    func testRefreshMapsServiceManagementStatusWithoutStartingLifecycle() async {
        let backend = InstallerBackendFixture(status: .enabled)
        let service = InstallerServiceFixture(result: .blockedResult)
        let installer = DaemonInstaller(backend: backend, installService: service)

        installer.refresh()

        XCTAssertEqual(installer.statusText, "Fan helper enabled")
        XCTAssertTrue(installer.canInstall)
        let serviceCallCount = await service.callCount()
        XCTAssertEqual(serviceCallCount, 0)
    }

    func testEnabledHelperUsesAsyncLifecycleServiceAndFailsClosedOnBlockedPreflight() async {
        let backend = InstallerBackendFixture(status: .enabled)
        let service = InstallerServiceFixture(result: .blockedResult)
        let app = URL(fileURLWithPath: "/Applications/Vifty.app")
        let script = app.appendingPathComponent("Contents/Resources/vifty-helper-lifecycle.sh")
        let installer = DaemonInstaller(
            backend: backend,
            installService: service,
            bundleURL: app,
            lifecycleScriptURL: script
        )

        let result = await installer.installOrOpenApproval()

        let serviceCallCount = await service.callCount()
        XCTAssertEqual(serviceCallCount, 1)
        let call = await service.lastCall()
        XCTAssertEqual(call?.operation, .repair)
        XCTAssertEqual(call?.appBundleURL, app)
        XCTAssertEqual(call?.lifecycleScriptURL, script)
        XCTAssertEqual(
            installer.statusText,
            "Helper maintenance is blocked until Vifty confirms Auto/System ownership with a valid maintenance token."
        )
        XCTAssertFalse(installer.isWorking)
        XCTAssertTrue(installer.canInstall)
        XCTAssertEqual(backend.openSettingsCount, 0)
        XCTAssertEqual(result, .blocked)
        XCTAssertFalse(result.shouldRefreshHelperState)
    }

    func testApprovalOpensLoginItemsWithoutCallingLifecycle() async {
        let backend = InstallerBackendFixture(status: .requiresApproval)
        let service = InstallerServiceFixture(result: .blockedResult)
        let installer = DaemonInstaller(backend: backend, installService: service)

        let result = await installer.installOrOpenApproval()

        XCTAssertEqual(backend.openSettingsCount, 1)
        let serviceCallCount = await service.callCount()
        XCTAssertEqual(serviceCallCount, 0)
        XCTAssertEqual(result, .approvalOpened)
        XCTAssertTrue(result.shouldRefreshHelperState)
    }

    func testFirstInstallRegistersSMAppServiceWithoutRunningDestructiveLifecycle() async {
        let backend = InstallerBackendFixture(status: .notRegistered)
        let service = InstallerServiceFixture(result: .blockedResult)
        let installer = DaemonInstaller(backend: backend, installService: service)

        let result = await installer.installOrOpenApproval()

        XCTAssertEqual(result, .completed)
        XCTAssertEqual(backend.registerCount, 1)
        XCTAssertEqual(backend.status, .enabled)
        let firstInstallLifecycleCalls = await service.callCount()
        XCTAssertEqual(firstInstallLifecycleCalls, 0)
    }

    func testUnknownServiceStateFailsClosedWithoutRegisterOrLifecycle() async {
        let backend = InstallerBackendFixture(status: .unknown)
        let service = InstallerServiceFixture(result: .blockedResult)
        let installer = DaemonInstaller(backend: backend, installService: service)

        let result = await installer.installOrOpenApproval()

        XCTAssertEqual(result, .blocked)
        XCTAssertEqual(backend.registerCount, 0)
        let unknownLifecycleCalls = await service.callCount()
        XCTAssertEqual(unknownLifecycleCalls, 0)
        XCTAssertTrue(installer.statusText.contains("unknown"))
    }

    func testUIWrapperContainsNoProcessOrPrivilegedLifecycleImplementation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let installer = try String(
            contentsOf: root.appendingPathComponent("Sources/Vifty/DaemonInstaller.swift"),
            encoding: .utf8
        )
        let content = try String(
            contentsOf: root.appendingPathComponent("Sources/Vifty/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(installer.contains("Process()"))
        XCTAssertFalse(installer.contains("waitUntilExit"))
        XCTAssertFalse(installer.contains("launchctl"))
        XCTAssertFalse(installer.contains("osascript"))
        XCTAssertFalse(installer.contains("isExecutableFile(atPath: lifecycleScriptURL.path)"))
        XCTAssertTrue(content.contains("let actionResult = await daemonInstaller.installOrOpenApproval()"))
        XCTAssertTrue(content.contains("guard actionResult.shouldRefreshHelperState else { return }"))
        XCTAssertFalse(content.contains("helperActionDisabled: !daemonInstaller.canInstall"))
        XCTAssertTrue(content.contains("helperActionPresentation.isAvailable"))
    }
}

@MainActor
private final class InstallerBackendFixture: DaemonInstallerBackend {
    var status: DaemonInstallerBackendStatus
    let requiresBundledDaemonResources = false
    private(set) var openSettingsCount = 0
    private(set) var registerCount = 0
    var statusAfterRegister: DaemonInstallerBackendStatus = .enabled

    init(status: DaemonInstallerBackendStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        status = statusAfterRegister
    }

    func openLoginItemsSettings() {
        openSettingsCount += 1
    }
}

private actor InstallerServiceFixture: DaemonInstallServicing {
    struct Call: Sendable {
        var operation: DaemonInstallOperation
        var appBundleURL: URL
        var lifecycleScriptURL: URL
    }

    private let result: DaemonInstallResult
    private var calls: [Call] = []

    init(result: DaemonInstallResult) {
        self.result = result
    }

    func perform(
        operation: DaemonInstallOperation,
        appBundleURL: URL,
        lifecycleScriptURL: URL
    ) async -> DaemonInstallResult {
        calls.append(Call(
            operation: operation,
            appBundleURL: appBundleURL,
            lifecycleScriptURL: lifecycleScriptURL
        ))
        return result
    }

    func callCount() -> Int { calls.count }
    func lastCall() -> Call? { calls.last }
}

private extension DaemonInstallResult {
    static let blockedResult = DaemonInstallResult(
        outcome: .blocked,
        operatorMessage: "Helper maintenance is blocked until Vifty confirms Auto/System ownership with a valid maintenance token."
    )
}
