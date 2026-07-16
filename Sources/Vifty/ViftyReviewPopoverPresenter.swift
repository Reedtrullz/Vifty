#if DEBUG
import AppKit
import Foundation
import SwiftUI

struct ViftyReviewPopoverRetryDeadline: Equatable, Sendable {
    let uptime: TimeInterval

    func boundedDelay(
        now: TimeInterval,
        preferredDelay: TimeInterval
    ) -> TimeInterval? {
        guard now.isFinite,
              preferredDelay.isFinite,
              preferredDelay >= 0,
              now < uptime else { return nil }
        return min(preferredDelay, uptime - now)
    }
}

@MainActor
final class ViftyReviewPopoverPresenter: NSObject, NSPopoverDelegate {
    private struct StatusItemAnchor: Equatable {
        let windowObject: ObjectIdentifier
        let windowNumber: Int
        let buttonSize: NSSize
    }

    private let runtime: ViftyReviewFixtureRuntime
    private let statusItem: NSStatusItem
    private let retryDeadline: ViftyReviewPopoverRetryDeadline
    private let currentUptime: () -> TimeInterval
    private let popover = NSPopover()
    private var hostingController: NSViewController?
    private var pendingShowWorkItem: DispatchWorkItem?
    private var anchorCandidate: StatusItemAnchor?
    private var anchorStableSampleCount = 0
    private var statusItemRemoved = false
    private var deadlineFailureRecorded = false
    private(set) var didShow = false

    init(
        runtime: ViftyReviewFixtureRuntime,
        currentUptime: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.runtime = runtime
        self.currentUptime = currentUptime
        let now = currentUptime()
        retryDeadline = ViftyReviewPopoverRetryDeadline(
            uptime: runtime.request.readinessDeadlineUptime
                ?? now + min(5, runtime.request.timeoutSeconds)
        )
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
    }

    func show() {
        guard pendingShowWorkItem == nil,
              !statusItemRemoved,
              !popover.isShown,
              !didShow else { return }
        scheduleShow()
    }

    private func scheduleShow() {
        guard !statusItemRemoved, !popover.isShown, !didShow else { return }
        guard retryDeadline.boundedDelay(
            now: currentUptime(),
            preferredDelay: 0
        ) != nil else {
            recordDeadlineFailure()
            return
        }
        guard let button = statusItem.button,
              let window = button.window,
              button.bounds.width > 0,
              button.bounds.height > 0 else {
            resetAnchorStability()
            scheduleRetry()
            return
        }
        let anchor = StatusItemAnchor(
            windowObject: ObjectIdentifier(window),
            windowNumber: window.windowNumber,
            buttonSize: button.bounds.size
        )
        if anchorCandidate == anchor {
            anchorStableSampleCount += 1
        } else {
            anchorCandidate = anchor
            anchorStableSampleCount = 1
        }
        guard anchorStableSampleCount >= 5 else {
            scheduleRetry()
            return
        }
        pendingShowWorkItem = nil

        let rootView = ViftyReviewFixtureSceneHost(
            runtime: runtime,
            provenance: "ns-popover-status-item"
        ) {
            MenuBarView(
                openMainWindow: { [recorder = runtime.recorder] in
                    recorder.recordExternalMutation("menu-open-main-window")
                },
                onRestoreAuto: { [recorder = runtime.recorder] in
                    recorder.recordHardwareCommand("menu-restore-auto")
                },
                onQuit: { [recorder = runtime.recorder] in
                    recorder.recordExternalMutation("menu-quit")
                }
            )
        }
        let controller = NSHostingController(rootView: rootView)
        controller.view.appearance = runtime.request.appearance.nativeAppearance
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = runtime.request.appearance.resolvedWindowBackgroundColor.cgColor
        controller.view.layer?.isOpaque = true
        controller.view.layoutSubtreeIfNeeded()
        let fittingHeight = max(1, ceil(controller.view.fittingSize.height))
        popover.contentSize = NSSize(width: 320, height: fittingHeight)
        popover.contentViewController = controller
        hostingController = controller

        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        schedulePostShowVerification()
    }

    private func scheduleRetry() {
        guard let delay = retryDeadline.boundedDelay(
            now: currentUptime(),
            preferredDelay: 0.05
        ) else {
            recordDeadlineFailure()
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShowWorkItem = nil
            self.scheduleShow()
        }
        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func schedulePostShowVerification() {
        guard let delay = retryDeadline.boundedDelay(
            now: currentUptime(),
            preferredDelay: 0.25
        ) else {
            if !popover.isShown, !didShow, !runtime.hasReadyObservation {
                recordDeadlineFailure()
            }
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShowWorkItem = nil
            guard !self.statusItemRemoved,
                  !self.runtime.hasReadyObservation,
                  !self.popover.isShown,
                  !self.didShow else { return }
            self.resetAnchorStability()
            self.scheduleShow()
        }
        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func recordDeadlineFailure() {
        guard !deadlineFailureRecorded else { return }
        deadlineFailureRecorded = true
        pendingShowWorkItem = nil
        runtime.recordFailure(ViftyReviewFixtureError.observationUnavailable)
    }

    private func resetAnchorStability() {
        anchorCandidate = nil
        anchorStableSampleCount = 0
    }

    func dispose() {
        guard !statusItemRemoved else { return }
        statusItemRemoved = true
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        if popover.isShown {
            popover.performClose(nil)
        }
        popover.delegate = nil
        popover.contentViewController = nil
        hostingController = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        didShow = false
    }

    func popoverDidShow(_ notification: Notification) {
        didShow = true
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        guard let window = popover.contentViewController?.view.window else { return }
        window.appearance = runtime.request.appearance.nativeAppearance
        window.identifier = NSUserInterfaceItemIdentifier(runtime.request.windowIdentifier)
        window.setAccessibilityIdentifier(runtime.request.windowAccessibilityIdentifier)
    }

    func popoverDidClose(_ notification: Notification) {
        didShow = false
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        guard !statusItemRemoved, !runtime.hasReadyObservation else { return }
        resetAnchorStability()
        show()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: "fan",
            accessibilityDescription: "Vifty UI review fixture"
        )
        image?.isTemplate = true
        button.image = image
        button.title = ""
        button.setAccessibilityLabel("Vifty UI review fixture")
    }

    private func configurePopover() {
        // The fixture records native WindowServer pixels as soon as SwiftUI reports
        // stable logical geometry. Keep the DEBUG-only popover off AppKit's scale
        // animation so those pixels cannot represent an in-flight presentation frame.
        popover.animates = false
        popover.behavior = .transient
        popover.appearance = runtime.request.appearance.nativeAppearance
        popover.delegate = self
    }
}
#endif
