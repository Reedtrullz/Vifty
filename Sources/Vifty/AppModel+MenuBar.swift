import Foundation
import SwiftUI
import ViftyCore

@MainActor
extension AppModel {
    var selectedSensor: TemperatureSensor? {
        curveTemperatureSelection.curveMetric
    }

    var effectiveSelectedSensorID: String? {
        selectedSensor?.id
    }

    var curveTemperatureSelection: TemperatureSensorSelection {
        TemperatureSensorSelection.resolve(
            sensors: snapshot?.temperatureSensors ?? [],
            selectedSensorID: userSelectedSensorID
        )
    }

    var resolvedCurveSensorID: String? {
        guard snapshot?.temperatureSensors.isEmpty == false else { return selectedSensorID }
        return effectiveSelectedSensorID
    }

    var temperatureAttentionSummary: String? {
        guard thermalPressure.menuSummary == nil else { return nil }
        guard let sensor = snapshot?.highestTemperature else { return nil }
        return sensor.celsius >= Self.highTemperatureAttentionThreshold ? "High temp" : nil
    }

    var fanWriteBlockedWhileHotSummary: String? {
        guard helperWritePathBlockedSummary != nil,
              let sensor = snapshot?.highestTemperature,
              sensor.celsius >= Self.highTemperatureAttentionThreshold else {
            return nil
        }
        return "High temp · fan writes blocked"
    }

    var fanWriteBlockedWhileHotRecoverySuggestion: String? {
        guard fanWriteBlockedWhileHotSummary != nil else { return nil }
        switch controlState.mode {
        case .auto:
            return "Reduce heavy work now. Keep Auto selected, then Repair/Reinstall Helper; writes stay blocked until the daemon responds."
        case .fixedRPM, .temperatureCurve:
            return "Reduce heavy work now. Repair/Reinstall Helper; Vifty will retry \(manualModeName) when the daemon responds. Use \(autoRestoreActionTitle) to stop retries."
        }
    }

    var visibleLastError: String? {
        guard let lastError else { return nil }
        guard !lastErrorIsCoveredByHelperRecovery(lastError) else { return nil }
        return lastError
    }

    var resolvedMenuBarPresentation: MenuBarPresentation {
        let currentDate = now()
        let lease = agentControlStatus?.activeLease
        return MenuBarPresentationProvider.resolve(MenuBarPresentationInput(
            displayMode: menuBarDisplayMode,
            customFields: menuBarCustomFields,
            snapshotIsAvailable: snapshot != nil,
            selectedTemperature: selectedSensor ?? snapshot?.highestTemperature,
            selectedTemperatureLabel: curveTemperatureSelection.curveMetricLabel,
            fans: snapshot?.fans ?? [],
            power: powerSnapshot,
            thermalPressure: thermalPressure,
            temperatureAttentionSummary: temperatureAttentionSummary,
            fanWriteBlockedWhileHotSummary: fanWriteBlockedWhileHotSummary,
            helperState: helperHealthState,
            hasCompletedHardwarePoll: hasCompletedHardwarePoll,
            daemonReachable: daemonReachable,
            daemonResponding: daemonResponding,
            lastErrorIsPresent: lastError != nil,
            agentCoolingMenuSummary: agentCoolingMenuSummary,
            agentStatusIsUnavailable: agentControlStatusError != nil,
            shouldPreferHelperRecoveryOverAgentStatusError: shouldPreferHelperRecoveryOverAgentStatusError,
            hasAgentLease: lease != nil,
            agentLeaseNeedsAttention: agentControlStatusError != nil
                || lease.map { !$0.isActive(at: currentDate) } == true,
            fanControlOwnershipStatus: fanControlOwnershipStatus,
            controlMode: controlState.mode,
            controlOwnershipNeedsAttention: controlOwnershipNeedsAttention,
            autoHardwareModeIsUncertain: !autoForcedModeFans.isEmpty
                || !autoUnknownModeFans.isEmpty
                || !autoMissingModeFans.isEmpty,
            codexUsageSnapshot: codexUsageSnapshot,
            codexUsageDisplayPreferences: codexUsageDisplayPreferences,
            currentDate: currentDate
        ))
    }

    var menuBarPanelAttentionText: String? {
        resolvedMenuBarPresentation.panelAttentionText
    }

    var menuTitle: String {
        resolvedMenuBarPresentation.title
    }

    var menuPanelTitle: String {
        resolvedMenuBarPresentation.panelTitle
    }

    var menuBarLabelText: String {
        resolvedMenuBarPresentation.labelText
    }

    var menuBarStatusItemText: String? {
        resolvedMenuBarPresentation.statusItemText
    }

    var menuBarLabelNeedsTelemetryPrime: Bool {
        resolvedMenuBarPresentation.labelNeedsTelemetryPrime
    }

    var menuBarDisplaysCodexUsage: Bool {
        MenuBarPresentationProvider.displaysCodexUsage(
            menuBarDisplayMode,
            customFields: menuBarCustomFields
        )
    }

    var menuBarAllowsPlaceholderStatusItemText: Bool {
        resolvedMenuBarPresentation.allowsPlaceholderStatusItemText
    }

    func isMenuBarCustomFieldEnabled(_ field: MenuBarField) -> Bool {
        menuBarCustomFields.contains(field)
    }

    func setMenuBarCustomField(_ field: MenuBarField, enabled: Bool) {
        var fields = menuBarCustomFields
        if enabled {
            guard !fields.contains(field) else { return }
            fields.append(field)
        } else {
            fields.removeAll { $0 == field }
            guard !fields.isEmpty else { return }
        }
        menuBarCustomFields = MenuBarField.normalized(fields)
    }

    var codexUsageSummary: String {
        CodexUsageFormatter.summaryText(
            for: codexUsageSnapshot,
            options: codexUsageDisplayPreferences,
            now: now
        )
    }

    var codexUsageDetailSummary: String? {
        CodexUsageFormatter.detailText(
            for: codexUsageSnapshot,
            options: codexUsageDisplayPreferences
        )
    }

    var codexUsageDetailLines: [String] {
        CodexUsageFormatter.detailLines(
            for: codexUsageSnapshot,
            options: codexUsageDisplayPreferences,
            now: now
        )
    }

    var menuBarFanOwnerText: String {
        resolvedMenuBarPresentation.fanOwnerText
    }

    var menuBarLabelUsesFanIcon: Bool {
        resolvedMenuBarPresentation.labelUsesFanIcon
    }

    func persistAppPreferences() {
        preferencesStore.save(AppPreferences(
            menuBarDisplayMode: menuBarDisplayMode,
            menuBarCustomFields: menuBarCustomFields,
            startupMode: startupMode,
            textScale: textScale,
            notificationSettings: notificationSettings,
            usePerFanFixedRPM: usePerFanFixedRPM,
            fixedFanTargets: fixedFanTargets,
            codexUsageDisplayPreferences: codexUsageDisplayPreferences
        ))
    }

    var codexUsageDisplayPreferences: CodexUsageDisplayPreferences {
        CodexUsageDisplayPreferences(
            displayStyle: codexUsageDisplayStyle,
            metricMode: codexUsageMetricMode,
            resetMode: codexUsageResetMode,
            refreshCadence: codexUsageRefreshCadence
        )
    }

    func codexUsageDisplayPreferenceDidChange() {
        persistAppPreferences()
        if menuBarDisplaysCodexUsage {
            refreshMenuBarStatusItemIfNeeded()
        }
    }

    var helperWritePathBlockedSummary: String? {
        helperHealthState.writePathBlockedSummary
    }

    func lastErrorIsCoveredByHelperRecovery(_ error: String) -> Bool {
        guard helperWritePathBlockedSummary != nil else { return false }
        return error.lowercased().hasPrefix("manual fan control blocked:")
    }

    var shouldPreferHelperRecoveryOverAgentStatusError: Bool {
        agentControlStatus?.activeLease == nil
            && agentControlStatusError != nil
            && helperWritePathBlockedSummary != nil
    }

    var agentCoolingMenuSummary: String? {
        guard let lease = agentControlStatus?.activeLease else {
            if shouldPreferHelperRecoveryOverAgentStatusError { return nil }
            return agentControlStatusError == nil ? nil : "Agent status unavailable"
        }
        if agentControlStatusError != nil {
            return "Agent status warning"
        }
        return lease.isActive(at: now()) ? "Agent cooling" : "Agent restore pending"
    }

    var agentCoolingPanelTitle: String {
        if agentControlStatusError != nil {
            if shouldPreferHelperRecoveryOverAgentStatusError { return "Agent cooling unavailable" }
            return agentControlStatus?.activeLease == nil ? "Agent status unavailable" : "Agent status warning"
        }
        return agentCoolingNeedsAttention ? "Agent restore pending" : "Agent cooling active"
    }

    var agentCoolingSummary: String? {
        guard let lease = agentControlStatus?.activeLease else {
            if shouldPreferHelperRecoveryOverAgentStatusError { return nil }
            guard agentControlStatusError != nil else { return nil }
            return "Agent cooling status unavailable; repair helper before requesting cooling."
        }

        let state = if lease.isActive(at: now()) {
            "Agent \(lease.request.workload.displayName) cooling until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))"
        } else {
            "Agent \(lease.request.workload.displayName) cooling expired; waiting for Auto restore"
        }

        let targets = lease.targetRPMByFanID
            .sorted { $0.key < $1.key }
            .map { "F\($0.key) \($0.value) RPM" }
            .joined(separator: ", ")

        let baseSummary = targets.isEmpty ? state : "\(state) · \(targets)"
        if agentControlStatusError != nil {
            return "\(baseSummary) · status refresh failed; do not start another workload"
        }
        return baseSummary
    }

    var agentCoolingRecoverySuggestion: String? {
        if agentControlStatusError != nil {
            if shouldPreferHelperRecoveryOverAgentStatusError { return nil }
            guard agentControlStatus?.activeLease != nil else {
                return "Repair Helper before requesting agent cooling."
            }
            return "Do not start another workload; use Auto to restore cooling, then check viftyctl status/audit after helper repair."
        }
        guard let lease = agentControlStatus?.activeLease, !lease.isActive(at: now()) else {
            return nil
        }
        return "Use Auto to restore daemon control before starting another workload."
    }

    var agentCoolingRestoreActionAvailable: Bool {
        agentControlStatus?.activeLease != nil
    }

    var autoRestoreActionTitle: String {
        helperWritePathBlockedSummary == nil ? "Auto" : "Request Auto"
    }

    var autoRestoreActionHelp: String {
        if helperWritePathBlockedSummary == nil {
            return "Restore Auto"
        }
        return "Request Auto restore; the write cannot be confirmed until the helper responds"
    }

    var modeSelectionActionTitle: String {
        modeSelectionActionRestoresAuto ? autoRestoreActionTitle : "Apply"
    }

    var modeSelectionActionHelp: String {
        modeSelectionActionRestoresAuto
            ? autoRestoreActionHelp
            : (manualFanControlBlockedReason ?? "Apply selected fan mode")
    }

    var modeSelectionActionRestoresAuto: Bool {
        selectedMode == .auto || manualControlAttentionSummary != nil
    }

    var modeSelectionActionDisabled: Bool {
        !modeSelectionActionRestoresAuto && !manualFanControlAvailable
    }

    var agentCoolingRestoreActionTitle: String {
        autoRestoreActionTitle
    }

    var agentCoolingRestoreActionHelp: String {
        if helperWritePathBlockedSummary == nil {
            return "Restore Auto before starting another agent workload"
        }
        return autoRestoreActionHelp
    }

    var agentCoolingNeedsAttention: Bool {
        if agentControlStatusError != nil {
            if shouldPreferHelperRecoveryOverAgentStatusError { return false }
            return true
        }
        guard let lease = agentControlStatus?.activeLease else { return false }
        return !lease.isActive(at: now())
    }

    var controlOwnershipSummary: String {
        if let lease = agentControlStatus?.activeLease {
            let statusWarning = agentControlStatusError == nil ? "" : " · status refresh failed"
            if lease.isActive(at: now()) {
                return "Agent \(lease.request.workload.displayName) owns cooling until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))\(statusWarning)"
            }
            return "Agent \(lease.request.workload.displayName) lease expired; restore Auto to clear daemon control\(statusWarning)"
        }

        if let manualHelperWriteBlockedSummary {
            return manualHelperWriteBlockedSummary
        }

        if controlState.mode == .auto, helperWritePathBlockedSummary != nil {
            return autoControlOwnershipSummary
        }

        if agentControlStatusError != nil {
            return "Agent control status unavailable; fan ownership uncertain"
        }

        switch controlState.mode {
        case .auto:
            return autoControlOwnershipSummary
        case .fixedRPM(let rpm):
            if let manualControlDriftSummary {
                return manualControlDriftSummary
            }
            return "Vifty Fixed owns fan targets · \(fixedModeTargetSummary(fallbackRPM: rpm)) · \(manualRunOwnershipSummary)"
        case .temperatureCurve:
            if let manualControlDriftSummary {
                return manualControlDriftSummary
            }
            if let sensor = selectedSensor {
                return "Vifty Curve owns fan targets · \(sensor.name) · \(manualRunOwnershipSummary)"
            }
            return "Vifty Curve owns fan targets · \(manualRunOwnershipSummary)"
        }
    }

    var compactControlOwnershipSummary: String {
        if let lease = agentControlStatus?.activeLease {
            if lease.isActive(at: now()) {
                return "Owner: Agent until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Owner: Agent restore pending"
        }

        if let manualHelperWriteBlockedSummary {
            return manualHelperWriteBlockedSummary
        }

        if controlState.mode == .auto, helperWritePathBlockedSummary != nil {
            return "Owner: Mac?"
        }

        if agentControlStatusError != nil {
            return "Owner: uncertain"
        }

        switch controlState.mode {
        case .auto:
            return "Owner: \(menuBarFanOwnerText)"
        case .fixedRPM:
            return "Owner: Vifty Fixed"
        case .temperatureCurve:
            return "Owner: Vifty Curve"
        }
    }

    var controlOwnershipNeedsAttention: Bool {
        if let lease = agentControlStatus?.activeLease {
            return agentControlStatusError != nil || !lease.isActive(at: now())
        }
        if agentControlStatusError != nil {
            return true
        }

        guard controlState.mode == .auto else {
            return manualHelperWriteBlockedSummary != nil || manualControlDriftSummary != nil
        }
        guard let fans = snapshot?.fans, !fans.isEmpty else {
            return hasCompletedHardwarePoll || daemonReachable
        }
        return !autoSystemModeFans.isEmpty
            || !autoForcedModeFans.isEmpty
            || !autoUnknownModeFans.isEmpty
            || !autoMissingModeFans.isEmpty
            || helperWritePathBlockedSummary != nil
    }

    var helperHealthState: HelperHealthState {
        HelperHealthPresentation.resolve(HelperHealthPresentationInput(
            hardwareIsSupported: snapshot.map { $0.isAppleSilicon && $0.isMacBookPro },
            hasCompletedHardwarePoll: hasCompletedHardwarePoll,
            daemonReachable: daemonReachable,
            daemonResponding: daemonResponding,
            fanCount: snapshot?.fans.count ?? 0,
            hasControllableFan: snapshot?.fans.contains(where: \.controllable) == true,
            lastError: lastError
        ))
    }

    var helperHealthSummary: String {
        helperHealthState.summary
    }

    var helperHealthMenuSummary: String {
        helperHealthState.menuSummary
    }

    var helperHealthNeedsAttention: Bool {
        helperHealthState.needsAttention
    }

    var helperRepairActionAvailable: Bool {
        helperHealthState.repairActionAvailable
    }

    var helperRecoverySuggestion: String? {
        helperHealthState.recoverySuggestion
    }

    var helperInstallRuntimeContext: String? {
        helperHealthState.installRuntimeContext
    }

    var helperFailureNotificationBody: String {
        fanWriteBlockedWhileHotRecoverySuggestion
            ?? helperRecoverySuggestion
            ?? "Repair or approve the fan helper before requesting fan control."
    }

    var helperFailureNotificationTitle: String {
        fanWriteBlockedWhileHotSummary == nil
            ? "Vifty fan helper needs attention"
            : "Vifty fan writes are blocked while hot"
    }

    var helperSupportEvidenceContext: HelperSupportEvidenceContext {
        var lines: [String] = [
            "selectedMode=\(selectedMode.rawValue)",
            "manualRun=\(manualRunLimit.label)",
            "daemon=reachable=\(daemonReachable) responding=\(daemonResponding)",
            "helper=\(helperHealthSummary)",
            "controlOwner=\(controlOwnershipSummary)"
        ]

        if let helperInstallRuntimeContext {
            lines.append("helperRuntime=\(helperInstallRuntimeContext)")
        }
        if let helperRecoverySuggestion {
            lines.append("helperRecovery=\(helperRecoverySuggestion)")
        }
        if let fanWriteBlockedWhileHotSummary {
            lines.append("hotFanWrites=\(fanWriteBlockedWhileHotSummary)")
        }
        if let fanWriteBlockedWhileHotRecoverySuggestion {
            lines.append("hotRecovery=\(fanWriteBlockedWhileHotRecoverySuggestion)")
        }
        if let sensor = selectedSensor ?? snapshot?.highestTemperature {
            lines.append("selectedTemperature=\(sensor.name) \(String(format: "%.1f", sensor.celsius)) C")
        }
        if let fans = snapshot?.fans, !fans.isEmpty {
            let fanSummary = fans
                .map { "\($0.name) \($0.currentRPM) RPM (\($0.percentage)%)" }
                .joined(separator: "; ")
            lines.append("fans=\(fanSummary)")
        }
        if let agentCoolingSummary {
            lines.append("agentCooling=\(agentCoolingSummary)")
        }
        if let lastError {
            lines.append("lastError=\(lastError)")
        }

        return HelperSupportEvidenceContext(lines: lines)
    }

    var helperMenuRecoverySuggestion: String? {
        if fanWriteBlockedWhileHotSummary != nil {
            return nil
        }
        return helperHealthState.menuRecoverySuggestion
    }

    var manualFanControlAvailable: Bool {
        manualFanControlBlockedReason == nil
    }

    var manualFanControlBlockedReason: String? {
        guard let snapshot else {
            return daemonResponding
                ? "Waiting for fan telemetry before manual fan control."
                : "Install or repair the fan helper before manual fan control."
        }
        guard snapshot.isAppleSilicon, snapshot.isMacBookPro else {
            return "Unsupported hardware. Manual fan control stays blocked."
        }
        if helperHealthState == .runtimeMismatch {
            return "Repair/Reinstall Helper before manual fan control; the installed helper does not match this Vifty app."
        }
        guard daemonResponding else {
            return daemonReachable
                ? "Repair/Reinstall Helper before manual fan control; fan telemetry is available but daemon writes are blocked."
                : "Install or repair the fan helper before manual fan control."
        }
        if let lease = agentControlStatus?.activeLease {
            if lease.isActive(at: now()) {
                return "Agent \(lease.request.workload.displayName) cooling owns fan control; restore Auto before manual fan control."
            }
            return "Agent cooling restore is pending; restore Auto before manual fan control."
        }
        if agentControlStatusError != nil {
            return "Agent control status is unavailable; repair helper before manual fan control."
        }
        guard !snapshot.fans.isEmpty else {
            return "Fan data is unavailable. Manual fan control stays blocked."
        }
        guard snapshot.fans.contains(where: \.controllable) else {
            return "No controllable fans are available. Manual fan control stays blocked."
        }
        guard !snapshot.temperatureSensors.isEmpty else {
            return "Temperature sensors are unavailable. Manual fan control stays blocked."
        }
        let confirmedOwnership = FanControlOwnershipPresentation.resolve(fanControlOwnershipStatus)
        switch confirmedOwnership.owner {
        case .macOS, .viftyManual:
            break
        case .agent:
            return "Agent cooling owns fan control; restore Auto before manual fan control."
        case .recovery:
            return "Fan recovery is pending; restore Auto before manual fan control."
        case .mixedOrUnknown:
            return "Fan ownership is unconfirmed; manual fan control stays blocked."
        }
        return nil
    }

    var manualControlAttentionSummary: String? {
        guard controlState.mode != .auto,
              helperWritePathBlockedSummary != nil else {
            return nil
        }
        return "\(manualModeName) request pending · fan writes blocked"
    }

    var manualControlAttentionRecoverySuggestion: String? {
        guard manualControlAttentionSummary != nil else { return nil }
        return "Vifty will retry \(manualModeName) when the helper responds. Use \(autoRestoreActionTitle) to stop retries; copy support evidence if repair does not clear it."
    }

    var manualHelperWriteBlockedSummary: String? {
        guard controlState.mode != .auto,
              let helperWritePathBlockedSummary else {
            return nil
        }
        return "\(helperWritePathBlockedSummary) · Vifty will retry \(manualModeName) when the helper responds"
    }

    var manualModeName: String {
        switch controlState.mode {
        case .auto:
            return "manual control"
        case .fixedRPM:
            return "Fixed"
        case .temperatureCurve:
            return "Curve"
        }
    }

    var manualRunOwnershipSummary: String {
        let runLimitSummary = manualSessionExpiresAt.map {
            "until \($0.formatted(date: .omitted, time: .shortened))"
        } ?? "until changed"
        return "\(runLimitSummary); reasserts if macOS drifts"
    }

    var autoControlOwnershipSummary: String {
        guard let fans = snapshot?.fans, !fans.isEmpty else {
            return daemonReachable
                ? "Auto selected · fan hardware state unavailable"
                : "Auto selected · fan writes blocked until helper responds"
        }

        if let helperWritePathBlockedSummary {
            return helperWritePathBlockedSummary
        }
        if !autoSystemModeFans.isEmpty {
            return "macOS System/protected owns fan control · \(fanIDList(autoSystemModeFans))"
        }
        if !autoForcedModeFans.isEmpty {
            return "Hardware reports Forced mode while Vifty is Auto · \(fanIDList(autoForcedModeFans))"
        }
        if !autoUnknownModeFans.isEmpty {
            return "Auto selected · unknown hardware mode on \(fanIDList(autoUnknownModeFans))"
        }
        if !autoMissingModeFans.isEmpty {
            return "Auto selected · hardware mode unavailable on \(fanIDList(autoMissingModeFans))"
        }
        return "macOS Auto owns fan control"
    }

    var manualControlDriftSummary: String? {
        guard controlState.mode != .auto,
              let fans = snapshot?.fans.filter(\.controllable),
              !fans.isEmpty else {
            return nil
        }

        let reclaimed = fans.filter { fan in
            guard let mode = fan.hardwareMode else { return false }
            return mode != .forced
        }
        if !reclaimed.isEmpty {
            let modes = reclaimed.reduce(into: [String]()) { names, fan in
                guard let name = fan.hardwareMode?.displayName, !names.contains(name) else { return }
                names.append(name)
            }.joined(separator: "/")
            let modeLabel = modes.isEmpty ? "non-forced mode" : modes
            return "Hardware reports \(modeLabel) while Vifty manual is selected; Vifty will reassert · \(fanIDList(reclaimed))"
        }

        let drifted = manualTargetDriftAttentionFans
        if !drifted.isEmpty {
            return "Hardware fan target drift detected; Vifty will reassert · \(fanIDList(drifted))"
        }

        let unconfirmedResponse = fans.filter { fan in
            guard fan.targetRPM == nil,
                  manualResponseAttentionIsWarranted,
                  let expectedRPM = expectedManualTargetRPM(for: fan) else {
                return false
            }
            return expectedRPM - fan.currentRPM >= Self.manualResponseRPMGapThreshold
        }
        guard !unconfirmedResponse.isEmpty else { return nil }
        return "Manual fan response not confirmed; current RPM is still below requested target · \(fanIDList(unconfirmedResponse))"
    }

    var currentManualTargetDriftFans: [Fan] {
        guard controlState.mode != .auto,
              let fans = snapshot?.fans.filter(\.controllable),
              !fans.isEmpty else {
            return []
        }

        return fans.filter { fan in
            guard !manualTargetSettlingFanIDs.contains(fan.id),
                  fan.hardwareMode == .forced,
                  let targetRPM = fan.targetRPM,
                  let expectedRPM = expectedManualTargetRPM(for: fan) else {
                return false
            }
            return abs(targetRPM - expectedRPM) >= Self.manualTargetDriftRPMThreshold
        }
    }

    var manualTargetDriftAttentionFans: [Fan] {
        let drifted = currentManualTargetDriftFans
        if !hasCompletedHardwarePoll {
            return drifted
        }
        return drifted.filter { fan in
            (manualTargetDriftSampleCounts[fan.id] ?? 0) >= Self.manualTargetDriftAttentionSampleCount
        }
    }

}
