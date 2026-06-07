import Foundation

public enum ViftyDaemonConstants {
    public static let machServiceName = "tech.reidar.vifty.daemon"
    public static let plistName = "tech.reidar.vifty.daemon.plist"
}

@objc public protocol ViftyDaemonProtocol {
    func ping(reply: @escaping (Bool) -> Void)
    func snapshot(reply: @escaping (NSDictionary?, String?) -> Void)
    func setFixedRPM(
        _ fanID: Int,
        rpm: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping (Bool, String?) -> Void
    )
    func restoreAuto(
        _ fanID: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        reply: @escaping (Bool, String?) -> Void
    )
}

public enum XPCSnapshotCoding {
    public static func encode(_ snapshot: HardwareSnapshot) -> NSDictionary {
        [
            "modelIdentifier": snapshot.modelIdentifier,
            "isAppleSilicon": snapshot.isAppleSilicon,
            "isMacBookPro": snapshot.isMacBookPro,
            "fans": snapshot.fans.map { fan in
                var encodedFan: [String: Any] = [
                    "id": fan.id,
                    "name": fan.name,
                    "currentRPM": fan.currentRPM,
                    "minimumRPM": fan.minimumRPM,
                    "maximumRPM": fan.maximumRPM,
                    "controllable": fan.controllable
                ]
                if let hardwareMode = fan.hardwareMode {
                    encodedFan["hardwareMode"] = hardwareMode.rawValue
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

        let fans = (dictionary["fans"] as? [NSDictionary] ?? []).compactMap { item -> Fan? in
            guard let id = item["id"] as? Int,
                  let name = item["name"] as? String,
                  let currentRPM = item["currentRPM"] as? Int,
                  let minimumRPM = item["minimumRPM"] as? Int,
                  let maximumRPM = item["maximumRPM"] as? Int,
                  let controllable = item["controllable"] as? Bool else {
                return nil
            }
            let hardwareModeRaw = item["hardwareMode"] as? Int
            let targetRPM = item["targetRPM"] as? Int
            return Fan(
                id: id,
                name: name,
                currentRPM: currentRPM,
                minimumRPM: minimumRPM,
                maximumRPM: maximumRPM,
                controllable: controllable,
                hardwareMode: FanHardwareMode(rawValue: hardwareModeRaw),
                targetRPM: targetRPM
            )
        }

        let sensors = (dictionary["temperatureSensors"] as? [NSDictionary] ?? []).compactMap { item -> TemperatureSensor? in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String,
                  let celsius = item["celsius"] as? Double,
                  let sourceRaw = item["source"] as? String,
                  let source = SensorSource(rawValue: sourceRaw) else {
                return nil
            }
            return TemperatureSensor(id: id, name: name, celsius: celsius, source: source)
        }

        return HardwareSnapshot(
            fans: fans,
            temperatureSensors: sensors,
            modelIdentifier: modelIdentifier,
            isAppleSilicon: isAppleSilicon,
            isMacBookPro: isMacBookPro
        )
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

        return AgentControlStatus(
            enabled: enabled,
            activeLease: activeLease,
            lastDecision: lastDecision,
            lastErrorCode: lastErrorCode
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

        return AgentControlDecision(
            allowed: allowed,
            errorCode: errorCode,
            message: message,
            targetRPMByFanID: targetRPMByFanID,
            warnings: warnings
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
