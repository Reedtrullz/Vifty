import AppKit
import Combine
import SwiftUI

@MainActor
final class ViftyStatusItemController: NSObject {
    private static let launchPrimePolicy = MenuBarTelemetryPrimePolicy.launch
    private static let popoverPrimePolicy = MenuBarTelemetryPrimePolicy.popover

    var openMainWindow: () -> Void

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var primeTask: Task<Void, Never>?
    private var lastAppliedPresentation: MenuBarStatusItemPresentation?

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
        model.$menuBarStatusItemPresentation
            .removeDuplicates()
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
        let presentation = model.menuBarStatusItemPresentation
        guard presentation != lastAppliedPresentation else { return }
        lastAppliedPresentation = presentation

        switch presentation.content {
        case .fanIcon(let accessibilityDescription):
            let image = NSImage(systemSymbolName: "fan", accessibilityDescription: accessibilityDescription)
            image?.isTemplate = true
            button.image = image
            button.title = ""
        case .text(let text):
            button.image = nil
            button.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
            button.title = text
        }
        statusItem.length = NSStatusItem.variableLength
        button.toolTip = presentation.tooltip
        button.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    private func scheduleTelemetryPrimeIfNeeded() {
        guard model.menuBarStatusItemPresentation.needsTelemetryPrime else { return }
        guard primeTask == nil else { return }
        primeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.primeTask = nil }
            await self.primeStatusItemUntilTelemetryResolved(policy: Self.launchPrimePolicy)
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
            await primeStatusItemUntilTelemetryResolved(policy: Self.popoverPrimePolicy)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func primeStatusItemUntilTelemetryResolved(
        policy: MenuBarTelemetryPrimePolicy
    ) async {
        model.start()
        for attempt in 1...policy.maxAttempts {
            guard policy.shouldAttempt(
                attempt,
                needsTelemetryPrime: model.menuBarLabelNeedsTelemetryPrime,
                hasCompletedHardwarePoll: model.hasCompletedHardwarePoll
            ) else { return }

            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 1)
            updateStatusItem()

            guard policy.shouldAttempt(
                attempt + 1,
                needsTelemetryPrime: model.menuBarLabelNeedsTelemetryPrime,
                hasCompletedHardwarePoll: model.hasCompletedHardwarePoll
            ) else { return }

            try? await Task.sleep(for: policy.retryDelay(after: attempt))
        }
    }

    private func performOpenMainWindow() {
        popover.performClose(nil)
        openMainWindow()
    }
}
