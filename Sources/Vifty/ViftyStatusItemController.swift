import AppKit
import Combine
import SwiftUI

@MainActor
final class ViftyStatusItemController: NSObject {
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
        primeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            model.start()
            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)
            updateStatusItem()
        }
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
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if model.menuBarLabelUsesFanIcon {
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
            button.title = model.menuBarLabelText
        }
        button.toolTip = model.menuTitle
        button.setAccessibilityLabel(model.menuBarLabelText)
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
            await model.primeMenuBarStatusItemTelemetry(maxAttempts: 3)
            updateStatusItem()
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func performOpenMainWindow() {
        popover.performClose(nil)
        openMainWindow()
    }
}
