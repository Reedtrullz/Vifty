import Foundation
import ViftyCore

struct FanCurveDraft: Equatable {
    var startTemperature: Double
    var startRPM: Double
    var rampTemperature: Double
    var rampRPM: Double
    var highTemperature: Double
    var highRPM: Double
}

struct FanControlDraft: Equatable {
    var mode: ModeSelection
    var manualRunLimit: ManualRunLimit
    var fixedRPM: Double
    var fixedFanTargets: [FixedFanTarget]
    var usePerFanFixedRPM: Bool
    var curve: FanCurveDraft
    var selectedSensorID: String?
    var usePerFanOverrides: Bool
    var fanOverrides: [FanCurveOverride]

    func isDirty(comparedTo applied: FanControlDraft) -> Bool {
        self != applied
    }
}

enum FanControlApplyResult: Equatable {
    case applied
    case superseded
    case blocked(reason: String)
    case failed(message: String)
}

enum FanControlApplyState: Equatable {
    case applied
    case pending
    case applying
    case blocked(reason: String)
    case failed(message: String)
}
