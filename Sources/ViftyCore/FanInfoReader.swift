import Foundation

public enum SMCFanControlKeys {
    public static func isValidFanID(_ fanID: Int) -> Bool {
        (0...9).contains(fanID)
    }

    public static func modeKeyCandidates(forFanID fanID: Int) -> [String] {
        ["F\(fanID)Md", "F\(fanID)md"]
    }

    public static func targetKey(forFanID fanID: Int) -> String {
        "F\(fanID)Tg"
    }
}

public enum SMCFanInfoReader {
    public typealias ReadValue = (String) throws -> SMCValue

    public static func readFans(read: ReadValue) -> [Fan] {
        let decodedFanCount = (try? read("FNum"))
            .flatMap(SMCDecoding.decodeFanControlByte)
            .map(Int.init)
        let fanCountIsTrusted = decodedFanCount.map { (1...10).contains($0) } == true
        let fanIDs: [Int]
        if let decodedFanCount, fanCountIsTrusted {
            fanIDs = Array(0..<decodedFanCount)
        } else {
            // Missing FNum must not erase useful read-only telemetry. Probe only
            // the allowlisted fan ID range and mark every discovered fan
            // ineligible so the inferred domain can never authorize a write.
            fanIDs = (0...9).filter { fanID in
                valueIfAvailable("F\(fanID)Ac", read: read) != nil
                    || valueIfAvailable("F\(fanID)Mn", read: read) != nil
                    || valueIfAvailable("F\(fanID)Mx", read: read) != nil
                    || firstDecodedInteger(
                        keys: SMCFanControlKeys.modeKeyCandidates(forFanID: fanID),
                        read: read
                    ) != nil
            }
        }

        return fanIDs.map { index in
            let actualValue = valueIfAvailable("F\(index)Ac", read: read)
            let minimumValue = valueIfAvailable("F\(index)Mn", read: read)
            let maximumValue = valueIfAvailable("F\(index)Mx", read: read)
            let actual = actualValue.flatMap(decodeDisplayRPM) ?? 0
            let decodedMinimum = minimumValue.flatMap(decodeWholeRPM)
            let decodedMaximum = maximumValue.flatMap(decodeWholeRPM)
            let minimum = decodedMinimum ?? 1200
            let maximum = decodedMaximum ?? max(actual, 6000)
            let mode = firstDecodedInteger(
                keys: SMCFanControlKeys.modeKeyCandidates(forFanID: index),
                read: read
            )
            let hardwareMode = FanHardwareMode(rawValue: mode?.value)
            let targetValue = valueIfAvailable(SMCFanControlKeys.targetKey(forFanID: index), read: read)
            let target = targetValue.flatMap(SMCDecoding.decodeFanTargetRPM)
            let eligibility = controlEligibility(
                fanID: index,
                fanCountIsTrusted: fanCountIsTrusted,
                minimumRPM: decodedMinimum,
                maximumRPM: decodedMaximum,
                hardwareMode: hardwareMode,
                hardwareModeKey: mode?.key,
                targetKeyIsReadable: target != nil
            )

            return Fan(
                id: index,
                name: fanName(index),
                currentRPM: actual,
                minimumRPM: minimum,
                maximumRPM: maximum,
                controllable: eligibility.canApplyFixedRPM,
                hardwareMode: hardwareMode,
                hardwareModeKey: mode?.key,
                targetRPM: target,
                controlEligibility: eligibility
            )
        }
    }

    static func controlEligibility(
        fanID: Int,
        fanCountIsTrusted: Bool,
        minimumRPM: Int?,
        maximumRPM: Int?,
        hardwareMode: FanHardwareMode?,
        hardwareModeKey: String?,
        targetKeyIsReadable: Bool
    ) -> FanControlEligibility {
        var reasons: [FanControlIneligibilityReason] = []
        if !SMCFanControlKeys.isValidFanID(fanID) { reasons.append(.invalidFanID) }
        if !fanCountIsTrusted { reasons.append(.missingFanCount) }
        if minimumRPM == nil { reasons.append(.missingMinimumRPM) }
        if maximumRPM == nil { reasons.append(.missingMaximumRPM) }

        let modeIsRecognized: Bool
        switch hardwareMode {
        case .automatic?, .forced?, .system?:
            modeIsRecognized = true
        case .unknown?, nil:
            modeIsRecognized = false
        }
        if hardwareModeKey == nil || !modeIsRecognized { reasons.append(.missingModeKey) }
        if !targetKeyIsReadable { reasons.append(.missingTargetKey) }

        if let minimumRPM, let maximumRPM,
           (minimumRPM < 0 || maximumRPM <= 0 || minimumRPM >= maximumRPM) {
            reasons.append(.invalidRPMRange)
        }

        let fixedBlockers: Set<FanControlIneligibilityReason> = [
            .legacyUnspecified,
            .missingFanCount,
            .missingMinimumRPM,
            .missingMaximumRPM,
            .missingModeKey,
            .missingTargetKey,
            .invalidRPMRange,
            .invalidFanID
        ]
        let recoveryBlockers: Set<FanControlIneligibilityReason> = [
            .legacyUnspecified,
            .missingFanCount,
            .missingModeKey,
            .invalidFanID
        ]

        return FanControlEligibility(
            canApplyFixedRPM: reasons.allSatisfy { !fixedBlockers.contains($0) },
            canRestoreOSManagedMode: reasons.allSatisfy { !recoveryBlockers.contains($0) },
            reasons: reasons
        )
    }

    private static func fanName(_ index: Int) -> String {
        switch index {
        case 0: "Left Fan"
        case 1: "Right Fan"
        default: "Fan \(index + 1)"
        }
    }

    private static func firstDecodedInteger(keys: [String], read: ReadValue) -> (value: Int, key: String)? {
        for key in keys {
            if let value = try? read(key),
               let decoded = SMCDecoding.decodeFanControlByte(value) {
                return (Int(decoded), key)
            }
        }
        return nil
    }

    private static func decodeDisplayRPM(_ value: SMCValue) -> Int? {
        guard let decoded = SMCDecoding.decodeFloat(value),
              decoded.isFinite,
              decoded >= 0,
              decoded <= Double(Int32.max) else {
            return nil
        }
        return Int(decoded.rounded())
    }

    private static func decodeWholeRPM(_ value: SMCValue) -> Int? {
        guard let decoded = SMCDecoding.decodeFloat(value),
              decoded.isFinite,
              decoded >= 0,
              decoded <= Double(Int32.max),
              decoded.rounded() == decoded else {
            return nil
        }
        return Int(decoded)
    }

    private static func valueIfAvailable(_ key: String, read: ReadValue) -> SMCValue? {
        try? read(key)
    }
}
