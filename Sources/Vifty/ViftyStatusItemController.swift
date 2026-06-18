import AppKit
import Combine
import SwiftUI

@MainActor
final class ViftyStatusItemController: NSObject {
    private static let launchPrimeAttempts = 120
    private static let launchPrimeRetryDelay: Duration = .milliseconds(750)

    var openMainWindow: () -> Void

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var primeTask: Task<Void, Never>?

    init(model: AppModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        observeModel()
        updateStatusItem()
        scheduleTelemetryPrimeIfNeeded()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(openMainWindow: { [weak self] in
                self?.performOpenMainWindow()
            })
            .environmentObject(model)
        )
    }

    private func observeModel() {
        model.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.updateStatusItem()
                    self?.scheduleTelemetryPrimeIfNeeded()
                }
            }
            .store(in: &cancellables)

        model.$menuBarStatusItemRevision
            .sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.updateStatusItem()
                    self?.scheduleTelemetryPrimeIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let statusItemText = resolvedStatusItemText
        if statusItemText == nil {
            let image = NSImage(systemSymbolName: "fan", accessibilityDescription: model.menuBarLabelText)
            image?.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
            button.title = statusItemText ?? ""
        }
        button.toolTip = model.menuTitle
        button.setAccessibilityLabel(model.menuBarLabelText)
    }

    private var resolvedStatusItemText: String? {
        guard let text = model.menuBarStatusItemText, !text.contains("--") else {
            return nil
        }
        return text
    }

    private func scheduleTelemetryPrimeIfNeeded() {
        guard model.menuBarLabelNeedsTelemetryPrime else { return }
        guard primeTask == nil else { return }
        primeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.primeTask = nil }
            await self.primeStatusItemUntilTelemetryResolved(
                maxAttempts: Self.launchPrimeAttempts,
                retryDelay: Self.launchPrimeRetryDelay
            )
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        model.start()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await primeStatusItemUntilTelemetryResolved(maxAttempts: 3, retryDelay: .milliseconds(250))
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func primeStatusItemUntilTelemetryResolved(
        maxAttempts: Int,
        retryDelay: Duration
    ) async {
        model.start()
        let attempts = max(1, maxAttempts)
        for attempt in 1...attempts {
            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 1)
            updateStatusItem()
            guard model.menuBarLabelNeedsTelemetryPrime else { return }
            if attempt < attempts {
                try? await Task.sleep(for: retryDelay)
            }
        }
    }

    private func performOpenMainWindow() {
        popover.performClose(nil)
        openMainWindow()
    }
}
