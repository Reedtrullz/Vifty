import AppKit
import SwiftUI
import ViftyCore

@main
struct ViftyApp: App {
    @NSApplicationDelegateAdaptor(ViftyAppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
#if DEBUG
    private let reviewFixtureRuntime: ViftyReviewFixtureRuntime?
#endif

    @MainActor
    init() {
        let helperServiceRequest: HelperServiceManagementRequest?
        let helperServiceBridgeError: Error?
        do {
            helperServiceRequest = try HelperServiceManagementRequest.parse(
                arguments: CommandLine.arguments
            )
            helperServiceBridgeError = nil
        } catch {
            helperServiceRequest = nil
            helperServiceBridgeError = error
        }
#if DEBUG
        let reviewFixtureRuntime: ViftyReviewFixtureRuntime?
        do {
            reviewFixtureRuntime = try ViftyReviewFixtureRuntime.parse(
                arguments: CommandLine.arguments
            )
        } catch {
            fatalError(error.localizedDescription)
        }
        self.reviewFixtureRuntime = reviewFixtureRuntime
        if let reviewFixtureRuntime {
            reviewFixtureRuntime.request.appearance.apply()
        }
        let model = reviewFixtureRuntime?.model ?? AppModel()
#else
        let model = AppModel()
#endif
        _model = StateObject(wrappedValue: model)
        appDelegate.model = model
        appDelegate.helperServiceRequest = helperServiceRequest
        appDelegate.helperServiceBridgeError = helperServiceBridgeError
        if helperServiceRequest != nil || helperServiceBridgeError != nil {
            NSApplication.shared.setActivationPolicy(.prohibited)
            return
        }
#if DEBUG
        appDelegate.reviewFixtureRuntime = reviewFixtureRuntime
        guard reviewFixtureRuntime == nil else { return }
#endif
        model.start()
    }

    var body: some Scene {
        Window("Vifty", id: "main") {
            Group {
#if DEBUG
                if let reviewFixtureRuntime {
                    switch reviewFixtureRuntime.route {
                    case .main:
                        ViftyReviewFixtureSceneHost(
                            runtime: reviewFixtureRuntime,
                            provenance: "swiftui-main-window"
                        ) {
                            ContentView(daemonInstaller: reviewFixtureRuntime.daemonInstaller)
                        }
                    case .settings, .popover:
                        ViftyReviewFixtureLaunchBridge(runtime: reviewFixtureRuntime)
                    }
                } else {
                    ContentView()
                }
#else
                ContentView()
#endif
            }
                .environmentObject(model)
                .viftyTextScale(model.textScale)
                .frame(minWidth: initialWindowWidth, minHeight: initialWindowHeight)
                .onAppear {
                    appDelegate.openMainWindowHandler = { openWindow(id: "main") }
                }
        }
#if DEBUG
        .defaultSize(width: initialWindowWidth, height: initialWindowHeight)
        .restorationBehavior(reviewFixtureRuntime == nil ? .automatic : .disabled)
        .defaultLaunchBehavior(reviewFixtureRuntime == nil ? .automatic : .presented)
#else
        .defaultSize(width: 1180, height: 820)
#endif
        .windowResizability(.contentMinSize)
        .commands {
#if DEBUG
            if reviewFixtureRuntime == nil {
                ViftyCommands(model: model, openWindow: openWindow)
            }
#else
            ViftyCommands(model: model, openWindow: openWindow)
#endif
        }

        Settings {
            Group {
#if DEBUG
                if let reviewFixtureRuntime {
                    if case .settings(let settingsTab) = reviewFixtureRuntime.route {
                        ViftyReviewFixtureSceneHost(
                            runtime: reviewFixtureRuntime,
                            provenance: "swiftui-settings-scene"
                        ) {
                            ViftySettingsView(
                                model: model,
                                initialTab: settingsTab
                            )
                        }
                    } else {
                        EmptyView()
                    }
                } else {
                    ViftySettingsView(model: model)
                }
#else
                ViftySettingsView(model: model)
#endif
            }
            .viftyTextScale(model.textScale)
        }
#if DEBUG
        .restorationBehavior(reviewFixtureRuntime == nil ? .automatic : .disabled)
#endif
    }

    private var initialWindowWidth: CGFloat {
#if DEBUG
        guard let reviewFixtureRuntime else { return 1180 }
        switch reviewFixtureRuntime.route {
        case .main:
            return reviewFixtureRuntime.request.window.size.width
        case .settings, .popover:
            return ViftyReviewFixtureWindow.native.size.width
        }
#else
        1180
#endif
    }

    private var initialWindowHeight: CGFloat {
#if DEBUG
        guard let reviewFixtureRuntime else { return 820 }
        switch reviewFixtureRuntime.route {
        case .main:
            return reviewFixtureRuntime.request.window.size.height
        case .settings, .popover:
            return ViftyReviewFixtureWindow.native.size.height
        }
#else
        820
#endif
    }
}

@MainActor
final class ViftyAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    var helperServiceRequest: HelperServiceManagementRequest?
    var helperServiceBridgeError: Error?
#if DEBUG
    var reviewFixtureRuntime: ViftyReviewFixtureRuntime?
#endif
    var openMainWindowHandler: (() -> Void)? {
        didSet {
            statusItemController?.openMainWindow = { [weak self] in
                self?.openMainWindow()
            }
        }
    }

    private var statusItemController: ViftyStatusItemController?
    private let terminationCoordinator = AppTerminationCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let helperServiceBridgeError {
            writeHelperServiceBridgeError(helperServiceBridgeError)
            exit(75)
        }
        if let helperServiceRequest {
            Task { @MainActor in
                do {
                    let backend = try SystemHelperServiceManagementBackend()
                    let report = try await HelperServiceManagementBridge.perform(
                        helperServiceRequest,
                        backend: backend,
                        maintenanceReportReader: {
                            try ViftyCtlRunner.readMaintenanceReport(atPath: $0)
                        },
                        maintenanceAuthorizer: { request in
                            try await ViftyDaemonClient().consumeHelperMaintenanceToken(request)
                        }
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(report)
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                    exit(report.complete ? 0 : 75)
                } catch {
                    writeHelperServiceBridgeError(error)
                    exit(75)
                }
            }
            return
        }
#if DEBUG
        guard reviewFixtureRuntime == nil else { return }
#endif
        guard let model else { return }
        statusItemController = ViftyStatusItemController(
            model: model,
            openMainWindow: { [weak self] in
                self?.openMainWindow()
            },
            onRestoreAuto: { [weak model] in
                model?.restoreAuto()
            }
        )
        statusItemController?.openMainWindow = { [weak self] in
            self?.openMainWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard helperServiceRequest == nil, helperServiceBridgeError == nil else { return }
#if DEBUG
        guard reviewFixtureRuntime == nil else { return }
#endif
        guard let model else { return }
        Task { @MainActor in
            await model.refreshSystemSettingsStateOnActivation()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
#if DEBUG
        if let reviewFixtureRuntime {
            do {
                try reviewFixtureRuntime.finalize()
                return .terminateNow
            } catch {
                FileHandle.standardError.write(Data("UI review fixture failed: \(error.localizedDescription)\n".utf8))
                exit(70)
            }
        }
#endif
        guard let model else { return .terminateCancel }

        _ = terminationCoordinator.beginTermination(
            restore: {
                await model.stopAndRestore()
            },
            completion: { [weak self, weak sender] result in
                if !result.canTerminate {
                    self?.openMainWindow()
                }
                sender?.reply(toApplicationShouldTerminate: result.canTerminate)
            }
        )
        return .terminateLater
    }

    private func openMainWindow() {
        if let openMainWindowHandler {
            openMainWindowHandler()
        } else if let window = NSApplication.shared.windows.first(where: { $0.title == "Vifty" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func writeHelperServiceBridgeError(_ error: Error) {
        let payload: [String: Any] = [
            "complete": false,
            "operatorActionRequired": false,
            "error": error.localizedDescription
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
