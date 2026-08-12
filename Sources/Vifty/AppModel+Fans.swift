import Foundation
import SwiftUI
import ViftyCore

@MainActor
extension AppModel {
    func targetRPMPreview(for fan: Fan) -> Int? {
        guard fan.controllable else { return nil }
        switch selectedMode {
        case .auto:
            return nil
        case .fixed:
            if perFanFixedRPMApplies {
                return fixedFanTargetRPM(for: fan)
            }
            return FanCurve.clamp(Int(fixedRPM.rounded()), fan.minimumRPM, fan.maximumRPM)
        case .curve:
            guard let sensor = selectedSensor else { return nil }
            return FanCurveTargetResolver.targetRPM(
                baseCurve: currentCurve(),
                fan: fan,
                temperature: sensor.celsius,
                overrides: usePerFanOverrides ? fanOverrides : []
            )
        }
    }

    func appliedTargetRPM(for fan: Fan) -> Int? {
        let targetRPM = fan.targetRPM ?? (controlState.manualControlActive ? controlState.lastAppliedRPM[fan.id] : nil)
        return targetRPM.map { FanCurve.clamp($0, fan.minimumRPM, fan.maximumRPM) }
    }

    func draftTargetRPMPreview(for fan: Fan) -> Int? {
        guard selectedMode != .auto, hasPendingFanControlChanges else { return nil }
        let draftTargetRPM = targetRPMPreview(for: fan)
        return draftTargetRPM == appliedTargetRPM(for: fan) ? nil : draftTargetRPM
    }

    func publishTelemetrySession() {
        assignIfChanged(\.telemetryOverviewSummary, telemetrySession.overviewSummary)
        assignIfChanged(\.compactTelemetryOverviewSummary, telemetrySession.compactSummary)
        assignIfChanged(\.recentTelemetryTrendSummary, telemetrySession.recentTrendSummary)
    }

    func ensureFixedFanTargets(for fans: [Fan]) {
        let controllableFans = fans.filter(\.controllable)
        let baseRatio = fixedRPMBaseRangeRatio(for: fixedRPMBaseBounds(for: controllableFans))
        let existingByFanID = fixedFanTargets.reduce(into: [Int: FixedFanTarget]()) { targetsByID, target in
            targetsByID[target.fanID] = target
        }
        let nextTargets = controllableFans.map { fan in
            if let existing = existingByFanID[fan.id] {
                return FixedFanTarget(
                    fanID: fan.id,
                    rpm: FanCurve.clamp(existing.rpm, fan.minimumRPM, fan.maximumRPM)
                )
            }
            return defaultFixedFanTarget(for: fan, baseRatio: baseRatio)
        }
        guard nextTargets != fixedFanTargets else { return }
        fixedFanTargets = nextTargets
        persistAppPreferences()
    }

    func fixedFanTarget(for fanID: Int) -> FixedFanTarget? {
        fixedFanTargets.first { $0.fanID == fanID }
    }

    func fixedFanTargetRPM(for fan: Fan) -> Int {
        fixedFanTarget(for: fan.id)?.rpm ?? defaultFixedFanTargetRPM(for: fan)
    }

    func fixedFanSliderRPM(for fan: Fan) -> Int {
        fixedFanTargetRPM(for: fan)
    }

    func fixedFanTargetPercent(for fan: Fan) -> Int {
        rpmPercent(fixedFanTargetRPM(for: fan), for: fan)
    }

    func setFixedFanRPM(_ rpm: Int, for fan: Fan, persist: Bool = true) {
        updateFixedFanTarget(for: fan) { target in
            target.rpm = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
        if persist {
            persistAppPreferences()
        }
    }

    func commitFixedFanTargetsAndApply() {
        persistAppPreferences()
        markFanControlDraftPending()
    }

    func commitFixedFanTargetsAndApplyNow() async {
        persistAppPreferences()
        markFanControlDraftPending()
    }

    func ensureFanOverrides(for fans: [Fan]) {
        let existingByFanID = fanOverrides.reduce(into: [Int: FanCurveOverride]()) { overridesByID, override in
            overridesByID[override.fanID] = override
        }
        fanOverrides = fans.filter(\.controllable).map { fan in
            existingByFanID[fan.id] ?? defaultFanOverride(for: fan)
        }
    }

    func fanOverride(for fanID: Int) -> FanCurveOverride? {
        fanOverrides.last { $0.fanID == fanID }
    }

    func setOverrideStartRPM(_ rpm: Int, for fan: Fan) {
        guard fan.controllable else { return }
        updateFanOverride(for: fan) { override in
            override.startRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    func setOverrideMidRPM(_ rpm: Int, for fan: Fan) {
        guard fan.controllable else { return }
        updateFanOverride(for: fan) { override in
            override.midRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    func setOverrideMaxRPM(_ rpm: Int, for fan: Fan) {
        guard fan.controllable else { return }
        updateFanOverride(for: fan) { override in
            override.maxRPM = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        }
    }

    func defaultFanOverride(for fan: Fan) -> FanCurveOverride {
        FanCurveOverride(
            fanID: fan.id,
            startRPM: FanCurve.clamp(Int(curveStartRPM.rounded()), fan.minimumRPM, fan.maximumRPM),
            midRPM: FanCurve.clamp(Int(curveMidRPM.rounded()), fan.minimumRPM, fan.maximumRPM),
            maxRPM: FanCurve.clamp(Int(curveMaxRPM.rounded()), fan.minimumRPM, fan.maximumRPM)
        )
    }

    func defaultFixedFanTarget(for fan: Fan) -> FixedFanTarget {
        FixedFanTarget(
            fanID: fan.id,
            rpm: defaultFixedFanTargetRPM(for: fan)
        )
    }

    var fixedRPMBaseBounds: (minimumRPM: Int, maximumRPM: Int) {
        fixedRPMBaseBounds(for: snapshot?.fans ?? [])
    }

    func fixedRPMBaseBounds(for fans: [Fan]) -> (minimumRPM: Int, maximumRPM: Int) {
        let fan = fans.first(where: \.controllable) ?? fans.first
        return (
            minimumRPM: fan?.minimumRPM ?? 1200,
            maximumRPM: fan?.maximumRPM ?? 6500
        )
    }

    var fixedRPMBaseRangeRatio: Double {
        fixedRPMBaseRangeRatio(for: fixedRPMBaseBounds)
    }

    func fixedRPMBaseRangeRatio(for bounds: (minimumRPM: Int, maximumRPM: Int)) -> Double {
        guard bounds.maximumRPM > bounds.minimumRPM else { return 0 }
        let clamped = FanCurve.clamp(Int(fixedRPM.rounded()), bounds.minimumRPM, bounds.maximumRPM)
        return Double(clamped - bounds.minimumRPM) / Double(bounds.maximumRPM - bounds.minimumRPM)
    }

    func defaultFixedFanTargetRPM(for fan: Fan) -> Int {
        defaultFixedFanTarget(for: fan, baseRatio: fixedRPMBaseRangeRatio).rpm
    }

    func defaultFixedFanTarget(for fan: Fan, baseRatio: Double) -> FixedFanTarget {
        guard fan.maximumRPM > fan.minimumRPM else {
            return FixedFanTarget(
                fanID: fan.id,
                rpm: FanCurve.clamp(Int(fixedRPM.rounded()), fan.minimumRPM, fan.maximumRPM)
            )
        }
        let rpm = Double(fan.minimumRPM) + Double(fan.maximumRPM - fan.minimumRPM) * baseRatio
        return FixedFanTarget(
            fanID: fan.id,
            rpm: FanCurve.clamp(Int(rpm.rounded()), fan.minimumRPM, fan.maximumRPM)
        )
    }

    func rpmPercent(_ rpm: Int, for fan: Fan) -> Int {
        guard fan.maximumRPM > fan.minimumRPM else { return 0 }
        let clamped = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        let ratio = Double(clamped - fan.minimumRPM) / Double(fan.maximumRPM - fan.minimumRPM)
        return min(100, max(0, Int((ratio * 100).rounded())))
    }

    func updateFixedFanTarget(for fan: Fan, mutate: (inout FixedFanTarget) -> Void) {
        if let index = fixedFanTargets.firstIndex(where: { $0.fanID == fan.id }) {
            mutate(&fixedFanTargets[index])
        } else {
            var target = defaultFixedFanTarget(for: fan)
            mutate(&target)
            fixedFanTargets.append(target)
        }
        fixedFanTargets = fixedFanTargets.reduce(into: [Int: FixedFanTarget]()) { targetsByID, target in
            targetsByID[target.fanID] = target
        }
        .sorted { $0.key < $1.key }
        .map(\.value)
    }

    func updateFanOverride(for fan: Fan, mutate: (inout FanCurveOverride) -> Void) {
        // Fan-curve resolution and presentation are deliberately last-wins for
        // duplicate persisted records. Mutate that same effective record before
        // canonicalizing, otherwise the untouched final duplicate would erase
        // the user's edit during the reduction below.
        if let index = fanOverrides.lastIndex(where: { $0.fanID == fan.id }) {
            mutate(&fanOverrides[index])
        } else {
            var override = defaultFanOverride(for: fan)
            mutate(&override)
            fanOverrides.append(override)
        }
        fanOverrides = fanOverrides.reduce(into: [Int: FanCurveOverride]()) { overridesByID, override in
            overridesByID[override.fanID] = override
        }
        .sorted { $0.key < $1.key }
        .map(\.value)
    }

}
