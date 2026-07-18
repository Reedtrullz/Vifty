import Foundation

public enum ViftyDaemonConstants {
    public static let machServiceName = "tech.reidar.vifty.daemon"
    public static let plistName = "tech.reidar.vifty.daemon.plist"
    public static let fanControlProtocolVersion = FanControlProtocolVersion.current
}

@objc public protocol ViftyDaemonProtocol {
    func ping(reply: @escaping (Bool) -> Void)
    func snapshot(reply: @escaping (NSDictionary?, String?) -> Void)
    func agentControlStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func agentControlAudit(_ limit: Int, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func prepareAgentControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func restoreAgentControl(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func prepareAgentControlV2(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func restoreAgentControlV2(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func fanControlOwnershipStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func applyManualFanControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func restoreAllAuto(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
    func prepareHelperMaintenance(
        _ operation: String,
        helperSHA256: String,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    )
    func consumeHelperMaintenanceToken(
        _ request: NSDictionary,
        reply: @escaping @Sendable (NSDictionary?, String?) -> Void
    )
    func cancelHelperMaintenance(reply: @escaping @Sendable (Bool, String?) -> Void)
    func setFixedRPM(
        _ fanID: Int,
        rpm: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
    func restoreAuto(
        _ fanID: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
}

public enum XPCFanControlCoding {
    public static func encode(_ request: ManualFanControlRequest) -> NSDictionary {
        [
            "transactionID": request.transactionID,
            "sessionID": request.sessionID,
            "expectedFanIDs": request.expectedFanIDs,
            "targetRPMByFanID": encodeTargets(request.targetRPMByFanID),
            "reason": request.reason
        ] as NSDictionary
    }

    public static func decodeManualRequest(_ dictionary: NSDictionary) -> ManualFanControlRequest? {
        guard let transactionID = dictionary["transactionID"] as? String,
              let sessionID = dictionary["sessionID"] as? String,
              let expectedFanIDs = intArray(dictionary["expectedFanIDs"]),
              let targetRPMByFanID = decodeTargets(dictionary["targetRPMByFanID"]),
              let reason = dictionary["reason"] as? String else {
            return nil
        }
        return ManualFanControlRequest(
            transactionID: transactionID,
            sessionID: sessionID,
            expectedFanIDs: expectedFanIDs,
            targetRPMByFanID: targetRPMByFanID,
            reason: reason
        )
    }

    public static func encode(_ request: AutoRestoreRequest) -> NSDictionary {
        var encoded: [String: Any] = [
            "transactionID": request.transactionID,
            "expectedFanIDs": request.expectedFanIDs,
            "reason": request.reason,
            "allowRestoreAllTrustedFans": request.allowRestoreAllTrustedFans
        ]
        if let authority = request.unreadableJournalRecoveryAuthority {
            encoded["unreadableJournalRecoveryAuthority"] = authority.rawValue
        }
        return encoded as NSDictionary
    }

    public static func decodeAutoRestoreRequest(_ dictionary: NSDictionary) -> AutoRestoreRequest? {
        guard let transactionID = dictionary["transactionID"] as? String,
              let expectedFanIDs = intArray(dictionary["expectedFanIDs"]),
              let reason = dictionary["reason"] as? String,
              let allowRestoreAllTrustedFans = bool(dictionary["allowRestoreAllTrustedFans"]) else {
            return nil
        }
        return AutoRestoreRequest(
            transactionID: transactionID,
            expectedFanIDs: expectedFanIDs,
            reason: reason,
            allowRestoreAllTrustedFans: allowRestoreAllTrustedFans,
            unreadableJournalRecoveryAuthority: (dictionary["unreadableJournalRecoveryAuthority"] as? String)
                .flatMap(UnreadableJournalRecoveryAuthority.init(rawValue:))
        )
    }

    public static func encode(_ status: FanControlOwnershipStatus) -> NSDictionary {
        var encoded: [String: Any] = [
            "protocolVersion": status.protocolVersion,
            "expectedFanIDs": status.expectedFanIDs,
            "confirmedOSManagedFanIDs": status.confirmedOSManagedFanIDs,
            "recoveryPending": status.recoveryPending,
            "recoveryAttemptCount": status.recoveryAttemptCount
        ]
        if let owner = status.owner { encoded["owner"] = encode(owner) }
        if let phase = status.phase { encoded["phase"] = phase.rawValue }
        if let transactionID = status.transactionID { encoded["transactionID"] = transactionID }
        if let errorCode = status.errorCode { encoded["errorCode"] = errorCode }
        if let errorMessage = status.errorMessage { encoded["errorMessage"] = errorMessage }
        return encoded as NSDictionary
    }

    public static func decodeOwnershipStatus(_ dictionary: NSDictionary) -> FanControlOwnershipStatus? {
        guard let protocolVersion = int(dictionary["protocolVersion"]),
              let expectedFanIDs = intArray(dictionary["expectedFanIDs"]),
              let confirmedOSManagedFanIDs = intArray(dictionary["confirmedOSManagedFanIDs"]),
              let recoveryPending = bool(dictionary["recoveryPending"]) else {
            return nil
        }
        let owner: FanControlOwner?
        if let value = dictionary["owner"] {
            guard let ownerDictionary = value as? NSDictionary,
                  let decoded = decodeOwner(ownerDictionary) else { return nil }
            owner = decoded
        } else {
            owner = nil
        }
        let phase: FanControlPhase?
        if let value = dictionary["phase"] {
            guard let raw = value as? String, let decoded = FanControlPhase(rawValue: raw) else { return nil }
            phase = decoded
        } else {
            phase = nil
        }
        return FanControlOwnershipStatus(
            protocolVersion: protocolVersion,
            owner: owner,
            phase: phase,
            transactionID: dictionary["transactionID"] as? String,
            expectedFanIDs: expectedFanIDs,
            confirmedOSManagedFanIDs: confirmedOSManagedFanIDs,
            recoveryPending: recoveryPending,
            errorCode: dictionary["errorCode"] as? String,
            errorMessage: dictionary["errorMessage"] as? String,
            recoveryAttemptCount: int(dictionary["recoveryAttemptCount"]) ?? 0
        )
    }

    public static func encode(_ result: FanControlTransactionResult) -> NSDictionary {
        var encoded: [String: Any] = [
            "transactionID": result.transactionID,
            "expectedFanIDs": result.expectedFanIDs,
            "confirmedFanIDs": result.confirmedFanIDs,
            "warnings": result.warnings
        ]
        if let owner = result.owner { encoded["owner"] = encode(owner) }
        if let phase = result.phase { encoded["phase"] = phase.rawValue }
        return encoded as NSDictionary
    }

    public static func decodeTransactionResult(_ dictionary: NSDictionary) -> FanControlTransactionResult? {
        guard let transactionID = dictionary["transactionID"] as? String,
              let expectedFanIDs = intArray(dictionary["expectedFanIDs"]),
              let confirmedFanIDs = intArray(dictionary["confirmedFanIDs"]),
              let warnings = dictionary["warnings"] as? [String] else {
            return nil
        }
        let owner: FanControlOwner?
        if let value = dictionary["owner"] {
            guard let ownerDictionary = value as? NSDictionary,
                  let decoded = decodeOwner(ownerDictionary) else { return nil }
            owner = decoded
        } else {
            owner = nil
        }
        let phase: FanControlPhase?
        if let value = dictionary["phase"] {
            guard let raw = value as? String, let decoded = FanControlPhase(rawValue: raw) else { return nil }
            phase = decoded
        } else {
            phase = nil
        }
        return FanControlTransactionResult(
            transactionID: transactionID,
            owner: owner,
            phase: phase,
            expectedFanIDs: expectedFanIDs,
            confirmedFanIDs: confirmedFanIDs,
            warnings: warnings
        )
    }

    private static func encode(_ owner: FanControlOwner) -> NSDictionary {
        switch owner {
        case .manual(let sessionID):
            ["type": "manual", "sessionID": sessionID] as NSDictionary
        case .agent(let leaseID):
            ["type": "agent", "leaseID": leaseID] as NSDictionary
        case .recovery:
            ["type": "recovery"] as NSDictionary
        }
    }

    private static func decodeOwner(_ dictionary: NSDictionary) -> FanControlOwner? {
        switch dictionary["type"] as? String {
        case "manual":
            guard let sessionID = dictionary["sessionID"] as? String else { return nil }
            return .manual(sessionID: sessionID)
        case "agent":
            guard let leaseID = dictionary["leaseID"] as? String else { return nil }
            return .agent(leaseID: leaseID)
        case "recovery":
            return .recovery
        default:
            return nil
        }
    }

    private static func encodeTargets(_ targets: [Int: Int]) -> NSDictionary {
        NSDictionary(dictionary: Dictionary(uniqueKeysWithValues: targets.map { (String($0.key), $0.value) }))
    }

    private static func decodeTargets(_ value: Any?) -> [Int: Int]? {
        guard let dictionary = value as? NSDictionary else { return nil }
        var targets: [Int: Int] = [:]
        for (key, value) in dictionary {
            guard let key = key as? String,
                  let fanID = Int(key),
                  let rpm = int(value),
                  targets[fanID] == nil else { return nil }
            targets[fanID] = rpm
        }
        return targets
    }

    private static func intArray(_ value: Any?) -> [Int]? {
        guard let values = value as? [Any] else { return nil }
        var result: [Int] = []
        for value in values {
            guard let decoded = int(value) else { return nil }
            result.append(decoded)
        }
        return result
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}

public enum XPCSnapshotCoding {
    public static func encode(_ snapshot: HardwareSnapshot) -> NSDictionary {
        [
            "modelIdentifier": snapshot.modelIdentifier,
            "isAppleSilicon": snapshot.isAppleSilicon,
            "isMacBookPro": snapshot.isMacBookPro,
            "fanControlProtocolVersion": snapshot.fanControlProtocolVersion,
            "fans": snapshot.fans.map { fan in
                var encodedFan: [String: Any] = [
                    "id": fan.id,
                    "name": fan.name,
                    "currentRPM": fan.currentRPM,
                    "minimumRPM": fan.minimumRPM,
                    "maximumRPM": fan.maximumRPM,
                    "controllable": fan.controllable,
                    "controlEligibility": [
                        "canApplyFixedRPM": fan.controlEligibility.canApplyFixedRPM,
                        "canRestoreOSManagedMode": fan.controlEligibility.canRestoreOSManagedMode,
                        "reasons": fan.controlEligibility.reasons.map(\.rawValue)
                    ] as NSDictionary
                ]
                if let hardwareMode = fan.hardwareMode {
                    encodedFan["hardwareMode"] = hardwareMode.rawValue
                }
                if let hardwareModeKey = fan.hardwareModeKey {
                    encodedFan["hardwareModeKey"] = hardwareModeKey
                }
                if let targetRPM = fan.targetRPM {
                    encodedFan["targetRPM"] = targetRPM
                }
                return encodedFan as NSDictionary
            },
            "temperatureSensors": snapshot.temperatureSensors.map { sensor in
                [
                    "id": sensor.id,
                    "name": sensor.name,
                    "celsius": sensor.celsius,
                    "source": sensor.source.rawValue
                ] as NSDictionary
            }
        ] as NSDictionary
    }

    public static func decode(_ dictionary: NSDictionary) -> HardwareSnapshot? {
        guard let modelIdentifier = dictionary["modelIdentifier"] as? String,
              let isAppleSilicon = dictionary["isAppleSilicon"] as? Bool,
              let isMacBookPro = dictionary["isMacBookPro"] as? Bool else {
            return nil
        }

        let protocolVersion = integer(dictionary["fanControlProtocolVersion"])
            ?? FanControlProtocolVersion.legacy

        guard let fanItems = dictionary["fans"] as? [NSDictionary],
              let sensorItems = dictionary["temperatureSensors"] as? [NSDictionary] else {
            return nil
        }
        var fans: [Fan] = []
        for item in fanItems {
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String,
                  let currentRPM = item["currentRPM"] as? Int,
                  let minimumRPM = item["minimumRPM"] as? Int,
                  let maximumRPM = item["maximumRPM"] as? Int,
                  let controllable = item["controllable"] as? Bool else {
                return nil
            }
            let hardwareModeRaw = item["hardwareMode"] as? Int
            let hardwareModeKey = item["hardwareModeKey"] as? String
            let targetRPM = item["targetRPM"] as? Int
            let eligibility: FanControlEligibility
            if protocolVersion >= FanControlProtocolVersion.current {
                guard let decoded = decodeEligibility(item["controlEligibility"]) else { return nil }
                eligibility = decoded
            } else {
                eligibility = .legacyUnspecified
            }
            fans.append(Fan(
                id: id,
                name: name,
                currentRPM: currentRPM,
                minimumRPM: minimumRPM,
                maximumRPM: maximumRPM,
                controllable: controllable,
                hardwareMode: FanHardwareMode(rawValue: hardwareModeRaw),
                hardwareModeKey: hardwareModeKey,
                targetRPM: targetRPM,
                controlEligibility: eligibility
            ))
        }

        var sensors: [TemperatureSensor] = []
        for item in sensorItems {
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String,
                  let celsius = item["celsius"] as? Double,
                  let sourceRaw = item["source"] as? String,
                  let source = SensorSource(rawValue: sourceRaw) else {
                return nil
            }
            sensors.append(TemperatureSensor(id: id, name: name, celsius: celsius, source: source))
        }

        return HardwareSnapshot(
            fans: fans,
            temperatureSensors: sensors,
            modelIdentifier: modelIdentifier,
            isAppleSilicon: isAppleSilicon,
            isMacBookPro: isMacBookPro,
            fanControlProtocolVersion: protocolVersion
        )
    }

    private static func decodeEligibility(_ value: Any?) -> FanControlEligibility? {
        guard let dictionary = value as? NSDictionary,
              let canApplyFixedRPM = dictionary["canApplyFixedRPM"] as? Bool,
              let canRestoreOSManagedMode = dictionary["canRestoreOSManagedMode"] as? Bool,
              let reasonValues = dictionary["reasons"] as? [String] else {
            return nil
        }
        let reasons = reasonValues.compactMap(FanControlIneligibilityReason.init(rawValue:))
        guard reasons.count == reasonValues.count else { return nil }
        return FanControlEligibility(
            canApplyFixedRPM: canApplyFixedRPM,
            canRestoreOSManagedMode: canRestoreOSManagedMode,
            reasons: reasons
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

public enum XPCAgentControlCoding {
    public static func encode(_ request: AgentControlRequest) -> NSDictionary {
        [
            "workload": request.workload.rawValue,
            "durationSeconds": request.durationSeconds,
            "maxRPMPercent": request.maxRPMPercent,
            "reason": request.reason,
            "idempotencyKey": request.idempotencyKey
        ] as NSDictionary
    }

    public static func decodeRequest(_ dictionary: NSDictionary) -> AgentControlRequest? {
        guard let workloadRaw = dictionary["workload"] as? String,
              let workload = AgentControlWorkload(rawValue: workloadRaw),
              let durationSeconds = intValue(dictionary["durationSeconds"]),
              let maxRPMPercent = intValue(dictionary["maxRPMPercent"]),
              let reason = dictionary["reason"] as? String,
              let idempotencyKey = dictionary["idempotencyKey"] as? String else {
            return nil
        }

        return AgentControlRequest(
            workload: workload,
            durationSeconds: durationSeconds,
            maxRPMPercent: maxRPMPercent,
            reason: reason,
            idempotencyKey: idempotencyKey
        )
    }

    public static func encode(_ status: AgentControlStatus) -> NSDictionary {
        var encoded: [String: Any] = [
            "enabled": status.enabled
        ]
        if let activeLease = status.activeLease {
            encoded["activeLease"] = encodeLease(activeLease)
        }
        if let lastDecision = status.lastDecision {
            encoded["lastDecision"] = encodeDecision(lastDecision)
        }
        if let lastErrorCode = status.lastErrorCode {
            encoded["lastErrorCode"] = lastErrorCode.rawValue
        }
        if let policy = status.policy {
            encoded["policy"] = encodePolicy(policy)
        }
        return encoded as NSDictionary
    }

    public static func decodeStatus(_ dictionary: NSDictionary) -> AgentControlStatus? {
        guard let enabled = boolValue(dictionary["enabled"]) else {
            return nil
        }

        var activeLease: AgentCoolingLease?
        if let value = dictionary["activeLease"] {
            guard let leaseDictionary = value as? NSDictionary,
                  let decodedLease = decodeLease(leaseDictionary) else {
                return nil
            }
            activeLease = decodedLease
        }

        var lastDecision: AgentControlDecision?
        if let value = dictionary["lastDecision"] {
            guard let decisionDictionary = value as? NSDictionary,
                  let decodedDecision = decodeDecision(decisionDictionary) else {
                return nil
            }
            lastDecision = decodedDecision
        }

        var lastErrorCode: AgentControlErrorCode?
        if let value = dictionary["lastErrorCode"] {
            guard let rawValue = value as? String,
                  let decodedErrorCode = AgentControlErrorCode(rawValue: rawValue) else {
                return nil
            }
            lastErrorCode = decodedErrorCode
        }

        var policy: AgentControlPolicySnapshot?
        if let value = dictionary["policy"] {
            guard let policyDictionary = value as? NSDictionary,
                  let decodedPolicy = decodePolicy(policyDictionary) else {
                return nil
            }
            policy = decodedPolicy
        }

        return AgentControlStatus(
            enabled: enabled,
            activeLease: activeLease,
            lastDecision: lastDecision,
            lastErrorCode: lastErrorCode,
            policy: policy
        )
    }

    public static func encodeAuditEvents(_ events: [AgentControlAuditEvent]) -> NSDictionary {
        [
            "events": events.map(encodeAuditEvent)
        ] as NSDictionary
    }

    public static func decodeAuditEvents(_ dictionary: NSDictionary) -> [AgentControlAuditEvent]? {
        guard let eventDictionaries = dictionary["events"] as? [NSDictionary] else {
            return nil
        }

        var events: [AgentControlAuditEvent] = []
        for eventDictionary in eventDictionaries {
            guard let event = decodeAuditEvent(eventDictionary) else {
                return nil
            }
            events.append(event)
        }
        return events
    }

    private static func encodePolicy(_ policy: AgentControlPolicySnapshot) -> NSDictionary {
        [
            "enabled": policy.enabled,
            "minimumAgentRPMPercent": policy.minimumAgentRPMPercent,
            "maximumAllowedRPMPercent": policy.maximumAllowedRPMPercent,
            "maxDurationSeconds": policy.maxDurationSeconds,
            "prepareCooldownSeconds": policy.prepareCooldownSeconds
        ] as NSDictionary
    }

    private static func decodePolicy(_ dictionary: NSDictionary) -> AgentControlPolicySnapshot? {
        guard let enabled = boolValue(dictionary["enabled"]),
              let minimumAgentRPMPercent = intValue(dictionary["minimumAgentRPMPercent"]),
              let maximumAllowedRPMPercent = intValue(dictionary["maximumAllowedRPMPercent"]),
              let maxDurationSeconds = intValue(dictionary["maxDurationSeconds"]),
              let prepareCooldownSeconds = intValue(dictionary["prepareCooldownSeconds"]) else {
            return nil
        }

        return AgentControlPolicySnapshot(
            enabled: enabled,
            minimumAgentRPMPercent: minimumAgentRPMPercent,
            maximumAllowedRPMPercent: maximumAllowedRPMPercent,
            maxDurationSeconds: maxDurationSeconds,
            prepareCooldownSeconds: prepareCooldownSeconds
        )
    }

    private static func encodeAuditEvent(_ event: AgentControlAuditEvent) -> NSDictionary {
        var encoded: [String: Any] = [
            "timestamp": event.timestamp.timeIntervalSince1970,
            "action": event.action,
            "message": event.message
        ]
        if let leaseID = event.leaseID {
            encoded["leaseID"] = leaseID
        }
        return encoded as NSDictionary
    }

    private static func decodeAuditEvent(_ dictionary: NSDictionary) -> AgentControlAuditEvent? {
        guard let timestamp = doubleValue(dictionary["timestamp"]),
              let action = dictionary["action"] as? String,
              let message = dictionary["message"] as? String else {
            return nil
        }

        var leaseID: String?
        if let value = dictionary["leaseID"] {
            guard let decodedLeaseID = value as? String else {
                return nil
            }
            leaseID = decodedLeaseID
        }

        return AgentControlAuditEvent(
            timestamp: Date(timeIntervalSince1970: timestamp),
            action: action,
            leaseID: leaseID,
            message: message
        )
    }

    private static func encodeLease(_ lease: AgentCoolingLease) -> NSDictionary {
        var encoded: [String: Any] = [
            "id": lease.id,
            "request": encode(lease.request),
            "createdAt": lease.createdAt.timeIntervalSince1970,
            "expiresAt": lease.expiresAt.timeIntervalSince1970,
            "targetRPMByFanID": encodeRPMMap(lease.targetRPMByFanID)
        ]
        if let restoredAt = lease.restoredAt {
            encoded["restoredAt"] = restoredAt.timeIntervalSince1970
        }
        return encoded as NSDictionary
    }

    private static func decodeLease(_ dictionary: NSDictionary) -> AgentCoolingLease? {
        guard let id = dictionary["id"] as? String,
              let requestDictionary = dictionary["request"] as? NSDictionary,
              let request = decodeRequest(requestDictionary),
              let createdAt = doubleValue(dictionary["createdAt"]),
              let expiresAt = doubleValue(dictionary["expiresAt"]),
              let targetRPMByFanID = decodeRPMMap(dictionary["targetRPMByFanID"]) else {
            return nil
        }

        var restoredAt: Date?
        if let value = dictionary["restoredAt"] {
            guard let timeInterval = doubleValue(value) else {
                return nil
            }
            restoredAt = Date(timeIntervalSince1970: timeInterval)
        }

        return AgentCoolingLease(
            id: id,
            request: request,
            createdAt: Date(timeIntervalSince1970: createdAt),
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            targetRPMByFanID: targetRPMByFanID,
            restoredAt: restoredAt
        )
    }

    private static func encodeDecision(_ decision: AgentControlDecision) -> NSDictionary {
        var encoded: [String: Any] = [
            "allowed": decision.allowed,
            "message": decision.message,
            "targetRPMByFanID": encodeRPMMap(decision.targetRPMByFanID),
            "warnings": decision.warnings
        ]
        if let errorCode = decision.errorCode {
            encoded["errorCode"] = errorCode.rawValue
        }
        if let retryAfterSeconds = decision.retryAfterSeconds {
            encoded["retryAfterSeconds"] = retryAfterSeconds
        }
        return encoded as NSDictionary
    }

    private static func decodeDecision(_ dictionary: NSDictionary) -> AgentControlDecision? {
        guard let allowed = boolValue(dictionary["allowed"]),
              let message = dictionary["message"] as? String,
              let targetRPMByFanID = decodeRPMMap(dictionary["targetRPMByFanID"]),
              let warnings = dictionary["warnings"] as? [String] else {
            return nil
        }

        var errorCode: AgentControlErrorCode?
        if let value = dictionary["errorCode"] {
            guard let rawValue = value as? String,
                  let decodedErrorCode = AgentControlErrorCode(rawValue: rawValue) else {
                return nil
            }
            errorCode = decodedErrorCode
        }

        var retryAfterSeconds: Int?
        if let value = dictionary["retryAfterSeconds"] {
            guard let decodedRetryAfterSeconds = intValue(value) else {
                return nil
            }
            retryAfterSeconds = decodedRetryAfterSeconds
        }

        return AgentControlDecision(
            allowed: allowed,
            errorCode: errorCode,
            message: message,
            targetRPMByFanID: targetRPMByFanID,
            warnings: warnings,
            retryAfterSeconds: retryAfterSeconds
        )
    }

    private static func encodeRPMMap(_ map: [Int: Int]) -> NSDictionary {
        Dictionary(uniqueKeysWithValues: map.map { fanID, rpm in
            (String(fanID), rpm)
        }) as NSDictionary
    }

    private static func decodeRPMMap(_ value: Any?) -> [Int: Int]? {
        guard let dictionary = value as? NSDictionary else {
            return nil
        }

        var decoded: [Int: Int] = [:]
        for (key, value) in dictionary {
            guard let key = key as? String,
                  let fanID = Int(key),
                  let rpm = intValue(value) else {
                return nil
            }
            decoded[fanID] = rpm
        }
        return decoded
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
}
