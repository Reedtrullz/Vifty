import XCTest
@testable import ViftyCore

final class AgentControlPolicyTests: XCTestCase {
    func testAllowsBuildRequestAndComputesPerFanTargetsFromPercent() {
        let policy = AgentControlPolicy(enabled: true, maximumAllowedRPMPercent: 80, maxDurationSeconds: 3600)
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4500, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 5500, controllable: true)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 61, source: .synthetic)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 1800, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        let decision = policy.evaluate(request, snapshot: snapshot, thermalPressure: .nominal)

        XCTAssertTrue(decision.allowed)
        XCTAssertEqual(decision.targetRPMByFanID[0], 3750)
        XCTAssertEqual(decision.targetRPMByFanID[1], 4500)
    }

    func testDeniesUnsupportedHardware() {
        let policy = AgentControlPolicy(enabled: true)
        let snapshot = HardwareSnapshot(fans: [], temperatureSensors: [], modelIdentifier: "Macmini10,1", isAppleSilicon: true, isMacBookPro: false)
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "Build", idempotencyKey: "key")

        let decision = policy.evaluate(request, snapshot: snapshot, thermalPressure: .nominal)

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.errorCode, .unsupportedHardware)
    }

    func testDeniesCriticalThermalPressureRatherThanFightingSystemThermals() {
        let policy = AgentControlPolicy(enabled: true)
        let decision = policy.evaluate(Self.request(), snapshot: Self.supportedSnapshot(), thermalPressure: .critical)

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.errorCode, .thermalCritical)
    }

    func testDeniesInvalidReasonAndIdempotencyKeyMetadata() {
        let policy = AgentControlPolicy(enabled: true)
        let blankReason = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 70,
            reason: "   ",
            idempotencyKey: "key"
        )
        let blankKey = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 70,
            reason: "Build",
            idempotencyKey: "   "
        )
        let oversizedReason = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 70,
            reason: String(repeating: "r", count: AgentControlRequest.maximumReasonLength + 1),
            idempotencyKey: "key"
        )
        let oversizedKey = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 70,
            reason: "Build",
            idempotencyKey: String(repeating: "k", count: AgentControlRequest.maximumIdempotencyKeyLength + 1)
        )

        let reasonDecision = policy.evaluate(blankReason, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal)
        let keyDecision = policy.evaluate(blankKey, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal)
        let oversizedReasonDecision = policy.evaluate(oversizedReason, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal)
        let oversizedKeyDecision = policy.evaluate(oversizedKey, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal)

        XCTAssertFalse(reasonDecision.allowed)
        XCTAssertEqual(reasonDecision.errorCode, .invalidArguments)
        XCTAssertEqual(reasonDecision.message, "Agent cooling reason must not be blank.")
        XCTAssertFalse(keyDecision.allowed)
        XCTAssertEqual(keyDecision.errorCode, .invalidArguments)
        XCTAssertEqual(keyDecision.message, "Agent cooling idempotency key must not be blank.")
        XCTAssertFalse(oversizedReasonDecision.allowed)
        XCTAssertEqual(oversizedReasonDecision.errorCode, .invalidArguments)
        XCTAssertEqual(oversizedReasonDecision.message, "Agent cooling reason must be 512 characters or fewer.")
        XCTAssertFalse(oversizedKeyDecision.allowed)
        XCTAssertEqual(oversizedKeyDecision.errorCode, .invalidArguments)
        XCTAssertEqual(oversizedKeyDecision.message, "Agent cooling idempotency key must be 256 characters or fewer.")
    }

    func testCriticalThermalPressureTakesPrecedenceOverMissingSensorsAndMalformedFans() {
        let policy = AgentControlPolicy(enabled: true)
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 5000, maximumRPM: 1000, controllable: true),
                Fan(id: 0, name: "Duplicate", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4500, controllable: true)
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let decision = policy.evaluate(Self.request(), snapshot: snapshot, thermalPressure: .critical)

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.errorCode, .thermalCritical)
    }

    func testDeniesDuplicateControllableFanIDsInsteadOfTrapping() {
        let policy = AgentControlPolicy(enabled: true)
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4500, controllable: true),
                Fan(id: 0, name: "Duplicate", currentRPM: 1600, minimumRPM: 1500, maximumRPM: 5500, controllable: true)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 61, source: .synthetic)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let decision = policy.evaluate(Self.request(), snapshot: snapshot, thermalPressure: .nominal)

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.errorCode, .policyDenied)
    }

    func testDeniesInvalidControllableFanIDs() {
        let policy = AgentControlPolicy(enabled: true)
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 10, name: "Invalid", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4500, controllable: true)
            ],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 61, source: .synthetic)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let decision = policy.evaluate(Self.request(), snapshot: snapshot, thermalPressure: .nominal)

        XCTAssertFalse(decision.allowed)
        XCTAssertEqual(decision.errorCode, .policyDenied)
        XCTAssertTrue(decision.message.contains("invalid fan ID 10"))
    }

    func testDeniesInvalidControllableFanRPMRanges() {
        let policy = AgentControlPolicy(enabled: true)
        let minGreaterThanMax = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 5000, maximumRPM: 1000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 61, source: .synthetic)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let nonPositiveMaximum = HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 0, minimumRPM: 0, maximumRPM: 0, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 61, source: .synthetic)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let invertedDecision = policy.evaluate(Self.request(), snapshot: minGreaterThanMax, thermalPressure: .nominal)
        let nonPositiveDecision = policy.evaluate(Self.request(), snapshot: nonPositiveMaximum, thermalPressure: .nominal)

        XCTAssertFalse(invertedDecision.allowed)
        XCTAssertEqual(invertedDecision.errorCode, .policyDenied)
        XCTAssertFalse(nonPositiveDecision.allowed)
        XCTAssertEqual(nonPositiveDecision.errorCode, .policyDenied)
    }

    func testDeniesTooLongDurationAndTooHighRPMPercent() {
        let policy = AgentControlPolicy(enabled: true, maximumAllowedRPMPercent: 80, maxDurationSeconds: 3600)
        let long = AgentControlRequest(workload: .build, durationSeconds: 7201, maxRPMPercent: 70, reason: "Too long", idempotencyKey: "a")
        let tooHigh = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 95, reason: "Too high", idempotencyKey: "b")

        XCTAssertEqual(policy.evaluate(long, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal).errorCode, .durationTooLong)
        XCTAssertEqual(policy.evaluate(tooHigh, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal).errorCode, .rpmOutOfRange)
    }

    func testPolicyCooldownDefaultAndCustom() {
        let defaultPolicy = AgentControlPolicy(enabled: true)
        XCTAssertEqual(defaultPolicy.prepareCooldownSeconds, 30)

        let customPolicy = AgentControlPolicy(enabled: true, prepareCooldownSeconds: 10)
        XCTAssertEqual(customPolicy.prepareCooldownSeconds, 10)
    }

    func testDefaultMaxDurationIsThirtyMinutes() {
        let policy = AgentControlPolicy(enabled: true)
        let accepted = AgentControlRequest(workload: .build, durationSeconds: 1_800, maxRPMPercent: 70, reason: "Build", idempotencyKey: "accepted")
        let rejected = AgentControlRequest(workload: .build, durationSeconds: 1_801, maxRPMPercent: 70, reason: "Too long", idempotencyKey: "rejected")

        XCTAssertEqual(policy.maxDurationSeconds, 1_800)
        XCTAssertTrue(policy.evaluate(accepted, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal).allowed)
        XCTAssertEqual(policy.evaluate(rejected, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal).errorCode, .durationTooLong)
    }

    private static func request() -> AgentControlRequest {
        AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "Build", idempotencyKey: "key")
    }

    private static func supportedSnapshot() -> HardwareSnapshot {
        HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4500, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 61, source: .synthetic)],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
    }
}
