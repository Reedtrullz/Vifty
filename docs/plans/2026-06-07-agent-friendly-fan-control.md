# Vifty Agent-Friendly Fan Control Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add a safe local agent-control surface so AI/coding agents can prepare Vifty for predictable high-thermal work, observe status as structured JSON, and reliably restore macOS Auto fan control.

**Architecture:** Build a daemon-enforced workload lease system in `ViftyCore`/`ViftyDaemon`, then expose it through a bundled `viftyctl` CLI. Agents request bounded cooling intent (`prepare --workload … --duration …`) rather than raw arbitrary SMC writes; Vifty validates policy, applies capped fan targets through the existing daemon/helper path, records audit evidence, and auto-restores when the lease expires or the workload wrapper exits. MCP and Shortcuts are explicitly deferred until the CLI/lease contract is stable.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, Foundation Codable/JSON, NSXPCConnection, LaunchDaemon/XPC, SwiftUI, IOKit/SMC, Bash install scripts, GitHub Actions macOS CI.

---

## Architecture audit before implementation

Read these first:

- `AGENTS.md` — target layout, architecture rules, testing rules, daemon-first write policy.
- `README.md` — current safety/privacy claims and helper CLI docs.
- `Package.swift` — confirms `ViftyCoreTests` already depends on `ViftyCore` and executable target `Vifty`; do not add `@testable import ViftyCtl` tests unless `Package.swift` is updated accordingly.
- `Sources/ViftyCore/Models.swift` — `Fan`, `HardwareSnapshot`, `FanMode`, `FanCommand`, `ControlState`, `ViftyError`.
- `Sources/ViftyCore/HardwareService.swift` — current fan-control heartbeat and Auto restore invariants.
- `Sources/ViftyCore/RealMacHardwareService.swift` — daemon-first hardware writes and fail-closed unprivileged fallback.
- `Sources/ViftyCore/ViftyDaemonClient.swift` and `Sources/ViftyCore/ViftyDaemonProtocol.swift` — current XPC client/protocol/coding boundary.
- `Sources/ViftyDaemon/main.swift` and `Sources/ViftyDaemon/XPCConnectionIdentityExtractor.swift` — daemon listener and code-sign identity gate.
- `Sources/Vifty/AppModel.swift`, `Sources/Vifty/ContentView.swift`, `Sources/Vifty/MenuBarView.swift` — UI polling and visible state.
- `scripts/install-vifty.sh`, `Makefile`, `.github/workflows/ci.yml` — bundle/install/CI gates.

Runtime heartbeat dependency chain:

```text
Agent/Hermes/Codex shell
  -> /Applications/Vifty.app/Contents/MacOS/viftyctl
  -> ViftyDaemonClient
  -> NSXPCConnection(machServiceName: tech.reidar.vifty.daemon)
  -> ViftyDaemon/DaemonService
  -> AgentControlService (new, daemon-owned)
  -> RealMacHardwareService(preferDaemon: false)
  -> LocalFanHelperClient/SMCClient
```

Existing app heartbeat remains:

```text
ViftyApp/MenuBarView/ContentView
  -> AppModel.start()/pollOnce()/applyModeSelection()/restoreAuto()
  -> FanControlCoordinator.tick()/setMode()/forceAuto()
  -> RealMacHardwareService.snapshot()/apply()/restoreAuto()
  -> ViftyDaemonClient XPC or local SMC fallback
  -> ViftyDaemon/DaemonService
  -> LocalFanHelperClient/SMCClient
```

Risk notes:

- This plan touches the silent safety path for fan writes. A green UI state is not enough; tests must assert fake hardware `apply`/`restoreAuto` calls.
- XPC remains an ObjC/NSDictionary boundary. New optional fields must be inserted conditionally, and old/missing payloads must decode without crashing.
- `viftyctl` will be a separate executable process. It must have a stable code-signing identifier (`tech.reidar.vifty.ctl`) in local builds; the daemon must not accept arbitrary platform binaries or all ad-hoc callers.
- The daemon/core layer must own agent leases and expiry. App-only timers are insufficient because the UI app may not be running when an agent starts work.
- `Package.swift` currently lists `"Vifty"` in `ViftyCoreTests`, so `AppModelTests` can import `Vifty`. This plan avoids test imports from `ViftyCtl`; if a future patch adds `@testable import ViftyCtl`, it must first add `"ViftyCtl"` to the test target dependencies.

Deferred/non-goals for this implementation:

- MCP server and App Intents/Shortcuts wrappers.
- Remote/LAN HTTP API.
- Raw SMC key writes or arbitrary agent-selected fixed-low RPM.
- Developer ID/notarization production signing. This plan keeps the local ad-hoc build path but makes the CLI identifier explicit and verifiable.

Baseline verified before writing this plan:

```bash
cd /Users/reidar/Projectos/Vifty && swift test
```

Expected/current result: `Executed 73 tests, with 0 failures`.

---

## Task 1: Add agent-control request/status models

**Objective:** Define Codable/Sendable model types for agent workload requests, policy errors, leases, and public status without touching hardware.

**Files:**
- Create: `Sources/ViftyCore/AgentControlModels.swift`
- Test: `Tests/ViftyCoreTests/AgentControlModelsTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/AgentControlModelsTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class AgentControlModelsTests: XCTestCase {
    func testRequestDefaultsAndCodableRoundTrip() throws {
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 45 * 60,
            maxRPMPercent: 75,
            reason: "Swift release build",
            idempotencyKey: "agent-build-001"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(AgentControlRequest.self, from: data)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.workload.displayName, "Build")
    }

    func testLeaseComputesActiveStateFromExpiration() {
        let created = Date(timeIntervalSince1970: 1_000)
        let lease = AgentCoolingLease(
            id: "lease-1",
            request: AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "Tests", idempotencyKey: "key-1"),
            createdAt: created,
            expiresAt: created.addingTimeInterval(600),
            targetRPMByFanID: [0: 3700, 1: 3900],
            restoredAt: nil
        )

        XCTAssertTrue(lease.isActive(at: created.addingTimeInterval(599)))
        XCTAssertFalse(lease.isActive(at: created.addingTimeInterval(600)))
    }

    func testAgentControlStatusIsCodable() throws {
        let status = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: AgentControlDecision.allowed(targetRPMByFanID: [0: 3600], warnings: ["Using capped RPM policy"]),
            lastErrorCode: nil
        )

        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(AgentControlStatus.self, from: data)

        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.lastDecision?.allowed, true)
        XCTAssertEqual(decoded.lastDecision?.targetRPMByFanID[0], 3600)
    }
}
```

**Step 2: Run test to verify failure**

Run:

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlModelsTests 2>&1
```

Expected: FAIL — `AgentControlRequest`, `AgentCoolingLease`, and related model types do not exist.

**Step 3: Write minimal implementation**

Create `Sources/ViftyCore/AgentControlModels.swift`:

```swift
import Foundation

public enum AgentControlWorkload: String, Codable, CaseIterable, Equatable, Sendable {
    case build
    case test
    case render
    case localModel
    case custom

    public var displayName: String {
        switch self {
        case .build: "Build"
        case .test: "Test"
        case .render: "Render"
        case .localModel: "Local Model"
        case .custom: "Custom"
        }
    }
}

public enum AgentControlErrorCode: String, Codable, Equatable, Sendable {
    case disabled = "AGENT_CONTROL_DISABLED"
    case unsupportedHardware = "UNSUPPORTED_HARDWARE"
    case helperUnreachable = "HELPER_UNREACHABLE"
    case temperatureSensorUnavailable = "TEMP_SENSOR_UNAVAILABLE"
    case noControllableFans = "NO_CONTROLLABLE_FANS"
    case policyDenied = "POLICY_DENIED"
    case durationTooLong = "DURATION_TOO_LONG"
    case rpmOutOfRange = "RPM_OUT_OF_RANGE"
    case thermalCritical = "THERMAL_CRITICAL"
    case leaseNotFound = "LEASE_NOT_FOUND"
    case restoreFailed = "RESTORE_FAILED"
    case invalidArguments = "INVALID_ARGUMENTS"
}

public struct AgentControlRequest: Codable, Equatable, Sendable {
    public var workload: AgentControlWorkload
    public var durationSeconds: Int
    public var maxRPMPercent: Int
    public var reason: String
    public var idempotencyKey: String

    public init(
        workload: AgentControlWorkload,
        durationSeconds: Int,
        maxRPMPercent: Int,
        reason: String,
        idempotencyKey: String
    ) {
        self.workload = workload
        self.durationSeconds = durationSeconds
        self.maxRPMPercent = maxRPMPercent
        self.reason = reason
        self.idempotencyKey = idempotencyKey
    }
}

public struct AgentControlDecision: Codable, Equatable, Sendable {
    public var allowed: Bool
    public var errorCode: AgentControlErrorCode?
    public var message: String
    public var targetRPMByFanID: [Int: Int]
    public var warnings: [String]

    public static func allowed(targetRPMByFanID: [Int: Int], warnings: [String] = []) -> AgentControlDecision {
        AgentControlDecision(allowed: true, errorCode: nil, message: "Allowed", targetRPMByFanID: targetRPMByFanID, warnings: warnings)
    }

    public static func denied(_ code: AgentControlErrorCode, message: String) -> AgentControlDecision {
        AgentControlDecision(allowed: false, errorCode: code, message: message, targetRPMByFanID: [:], warnings: [])
    }
}

public struct AgentCoolingLease: Codable, Equatable, Sendable {
    public var id: String
    public var request: AgentControlRequest
    public var createdAt: Date
    public var expiresAt: Date
    public var targetRPMByFanID: [Int: Int]
    public var restoredAt: Date?

    public init(
        id: String,
        request: AgentControlRequest,
        createdAt: Date,
        expiresAt: Date,
        targetRPMByFanID: [Int: Int],
        restoredAt: Date? = nil
    ) {
        self.id = id
        self.request = request
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.targetRPMByFanID = targetRPMByFanID
        self.restoredAt = restoredAt
    }

    public func isActive(at date: Date) -> Bool {
        restoredAt == nil && date < expiresAt
    }
}

public struct AgentControlStatus: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var activeLease: AgentCoolingLease?
    public var lastDecision: AgentControlDecision?
    public var lastErrorCode: AgentControlErrorCode?

    public init(
        enabled: Bool,
        activeLease: AgentCoolingLease?,
        lastDecision: AgentControlDecision?,
        lastErrorCode: AgentControlErrorCode?
    ) {
        self.enabled = enabled
        self.activeLease = activeLease
        self.lastDecision = lastDecision
        self.lastErrorCode = lastErrorCode
    }
}
```

**Step 4: Run test to verify pass**

Run:

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlModelsTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/AgentControlModels.swift Tests/ViftyCoreTests/AgentControlModelsTests.swift
git commit -m "feat: add agent control models"
```

---

## Task 2: Add conservative agent-control policy evaluation

**Objective:** Convert a workload request plus a hardware snapshot into safe per-fan target RPMs or a structured denial.

**Files:**
- Create: `Sources/ViftyCore/AgentControlPolicy.swift`
- Test: `Tests/ViftyCoreTests/AgentControlPolicyTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/AgentControlPolicyTests.swift`:

```swift
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

    func testDeniesTooLongDurationAndTooHighRPMPercent() {
        let policy = AgentControlPolicy(enabled: true, maximumAllowedRPMPercent: 80, maxDurationSeconds: 3600)
        let long = AgentControlRequest(workload: .build, durationSeconds: 7201, maxRPMPercent: 70, reason: "Too long", idempotencyKey: "a")
        let tooHigh = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 95, reason: "Too high", idempotencyKey: "b")

        XCTAssertEqual(policy.evaluate(long, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal).errorCode, .durationTooLong)
        XCTAssertEqual(policy.evaluate(tooHigh, snapshot: Self.supportedSnapshot(), thermalPressure: .nominal).errorCode, .rpmOutOfRange)
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
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlPolicyTests 2>&1
```

Expected: FAIL — `AgentControlPolicy` does not exist.

**Step 3: Write minimal implementation**

Create `Sources/ViftyCore/AgentControlPolicy.swift`:

```swift
import Foundation

public struct AgentControlPolicy: Equatable, Sendable {
    public var enabled: Bool
    public var minimumAgentRPMPercent: Int
    public var maximumAllowedRPMPercent: Int
    public var maxDurationSeconds: Int

    public init(
        enabled: Bool = false,
        minimumAgentRPMPercent: Int = 35,
        maximumAllowedRPMPercent: Int = 80,
        maxDurationSeconds: Int = 60 * 60
    ) {
        self.enabled = enabled
        self.minimumAgentRPMPercent = minimumAgentRPMPercent
        self.maximumAllowedRPMPercent = maximumAllowedRPMPercent
        self.maxDurationSeconds = maxDurationSeconds
    }

    public func evaluate(
        _ request: AgentControlRequest,
        snapshot: HardwareSnapshot,
        thermalPressure: ThermalPressure
    ) -> AgentControlDecision {
        guard enabled else {
            return .denied(.disabled, message: "Agent fan control is disabled in Vifty settings.")
        }
        guard snapshot.isAppleSilicon, snapshot.isMacBookPro else {
            return .denied(.unsupportedHardware, message: "Agent fan control is only supported on Apple Silicon MacBook Pro hardware.")
        }
        guard !snapshot.temperatureSensors.isEmpty else {
            return .denied(.temperatureSensorUnavailable, message: "At least one temperature sensor is required before agent fan control can run.")
        }
        guard thermalPressure != .critical else {
            return .denied(.thermalCritical, message: "Thermal pressure is critical; the workload should pause or reduce CPU/GPU work instead.")
        }
        guard request.durationSeconds > 0, request.durationSeconds <= maxDurationSeconds else {
            return .denied(.durationTooLong, message: "Duration must be between 1 second and \(maxDurationSeconds) seconds.")
        }
        guard request.maxRPMPercent >= minimumAgentRPMPercent,
              request.maxRPMPercent <= maximumAllowedRPMPercent else {
            return .denied(.rpmOutOfRange, message: "RPM percent must be between \(minimumAgentRPMPercent) and \(maximumAllowedRPMPercent).")
        }

        let controllableFans = snapshot.fans.filter(\.controllable)
        guard !controllableFans.isEmpty else {
            return .denied(.noControllableFans, message: "No controllable fans were reported by the helper.")
        }

        let targets = Dictionary(uniqueKeysWithValues: controllableFans.map { fan in
            let span = fan.maximumRPM - fan.minimumRPM
            let rpm = fan.minimumRPM + Int((Double(span) * Double(request.maxRPMPercent) / 100.0).rounded())
            return (fan.id, FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM))
        })

        var warnings: [String] = []
        if thermalPressure == .serious {
            warnings.append("Thermal pressure is serious; consider reducing the workload if it rises further.")
        }
        return .allowed(targetRPMByFanID: targets, warnings: warnings)
    }
}
```

**Step 4: Run test to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlPolicyTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/AgentControlPolicy.swift Tests/ViftyCoreTests/AgentControlPolicyTests.swift
git commit -m "feat: add agent control policy"
```

---

## Task 3: Add XPC dictionary coding for agent-control payloads

**Objective:** Round-trip agent-control request/status/lease payloads across the existing NSDictionary XPC boundary.

**Files:**
- Modify: `Sources/ViftyCore/ViftyDaemonProtocol.swift`
- Test: `Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class XPCAgentControlCodingTests: XCTestCase {
    func testRequestRoundTripsThroughNSDictionary() {
        let request = AgentControlRequest(workload: .build, durationSeconds: 1200, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key-1")

        let encoded = XPCAgentControlCoding.encode(request)
        let decoded = XPCAgentControlCoding.decodeRequest(encoded)

        XCTAssertEqual(decoded, request)
    }

    func testStatusRoundTripsThroughNSDictionary() {
        let created = Date(timeIntervalSince1970: 1_000)
        let status = AgentControlStatus(
            enabled: true,
            activeLease: AgentCoolingLease(
                id: "lease-1",
                request: AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "Tests", idempotencyKey: "key-2"),
                createdAt: created,
                expiresAt: created.addingTimeInterval(600),
                targetRPMByFanID: [0: 3600]
            ),
            lastDecision: .allowed(targetRPMByFanID: [0: 3600]),
            lastErrorCode: nil
        )

        let encoded = XPCAgentControlCoding.encode(status)
        let decoded = XPCAgentControlCoding.decodeStatus(encoded)

        XCTAssertEqual(decoded, status)
    }

    func testOlderStatusWithoutLeaseStillDecodes() {
        let dictionary: NSDictionary = [
            "enabled": true
        ]

        let decoded = XPCAgentControlCoding.decodeStatus(dictionary)

        XCTAssertEqual(decoded?.enabled, true)
        XCTAssertNil(decoded?.activeLease)
        XCTAssertNil(decoded?.lastDecision)
    }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter XPCAgentControlCodingTests 2>&1
```

Expected: FAIL — `XPCAgentControlCoding` does not exist.

**Step 3: Write minimal implementation**

Append this enum to `Sources/ViftyCore/ViftyDaemonProtocol.swift` after `XPCSnapshotCoding`:

```swift
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
              let durationSeconds = dictionary["durationSeconds"] as? Int,
              let maxRPMPercent = dictionary["maxRPMPercent"] as? Int,
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
        var encoded: [String: Any] = ["enabled": status.enabled]
        if let activeLease = status.activeLease { encoded["activeLease"] = encode(activeLease) }
        if let lastDecision = status.lastDecision { encoded["lastDecision"] = encode(lastDecision) }
        if let lastErrorCode = status.lastErrorCode { encoded["lastErrorCode"] = lastErrorCode.rawValue }
        return encoded as NSDictionary
    }

    public static func decodeStatus(_ dictionary: NSDictionary) -> AgentControlStatus? {
        guard let enabled = dictionary["enabled"] as? Bool else { return nil }
        let lease = (dictionary["activeLease"] as? NSDictionary).flatMap(decodeLease)
        let decision = (dictionary["lastDecision"] as? NSDictionary).flatMap(decodeDecision)
        let errorCode = (dictionary["lastErrorCode"] as? String).flatMap(AgentControlErrorCode.init(rawValue:))
        return AgentControlStatus(enabled: enabled, activeLease: lease, lastDecision: decision, lastErrorCode: errorCode)
    }

    private static func encode(_ lease: AgentCoolingLease) -> NSDictionary {
        var encoded: [String: Any] = [
            "id": lease.id,
            "request": encode(lease.request),
            "createdAt": lease.createdAt.timeIntervalSince1970,
            "expiresAt": lease.expiresAt.timeIntervalSince1970,
            "targetRPMByFanID": lease.targetRPMByFanID.reduce(into: [String: Int]()) { $0[String($1.key)] = $1.value }
        ]
        if let restoredAt = lease.restoredAt { encoded["restoredAt"] = restoredAt.timeIntervalSince1970 }
        return encoded as NSDictionary
    }

    private static func decodeLease(_ dictionary: NSDictionary) -> AgentCoolingLease? {
        guard let id = dictionary["id"] as? String,
              let requestDictionary = dictionary["request"] as? NSDictionary,
              let request = decodeRequest(requestDictionary),
              let createdAt = dictionary["createdAt"] as? Double,
              let expiresAt = dictionary["expiresAt"] as? Double,
              let targetStrings = dictionary["targetRPMByFanID"] as? [String: Int] else {
            return nil
        }
        let targets = targetStrings.reduce(into: [Int: Int]()) { result, pair in
            if let key = Int(pair.key) { result[key] = pair.value }
        }
        let restoredAt = (dictionary["restoredAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        return AgentCoolingLease(
            id: id,
            request: request,
            createdAt: Date(timeIntervalSince1970: createdAt),
            expiresAt: Date(timeIntervalSince1970: expiresAt),
            targetRPMByFanID: targets,
            restoredAt: restoredAt
        )
    }

    private static func encode(_ decision: AgentControlDecision) -> NSDictionary {
        var encoded: [String: Any] = [
            "allowed": decision.allowed,
            "message": decision.message,
            "targetRPMByFanID": decision.targetRPMByFanID.reduce(into: [String: Int]()) { $0[String($1.key)] = $1.value },
            "warnings": decision.warnings
        ]
        if let errorCode = decision.errorCode { encoded["errorCode"] = errorCode.rawValue }
        return encoded as NSDictionary
    }

    private static func decodeDecision(_ dictionary: NSDictionary) -> AgentControlDecision? {
        guard let allowed = dictionary["allowed"] as? Bool,
              let message = dictionary["message"] as? String,
              let targetStrings = dictionary["targetRPMByFanID"] as? [String: Int],
              let warnings = dictionary["warnings"] as? [String] else {
            return nil
        }
        let targets = targetStrings.reduce(into: [Int: Int]()) { result, pair in
            if let key = Int(pair.key) { result[key] = pair.value }
        }
        let errorCode = (dictionary["errorCode"] as? String).flatMap(AgentControlErrorCode.init(rawValue:))
        return AgentControlDecision(allowed: allowed, errorCode: errorCode, message: message, targetRPMByFanID: targets, warnings: warnings)
    }
}
```

**Step 4: Run test to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter XPCAgentControlCodingTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/ViftyDaemonProtocol.swift Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift
git commit -m "feat: add agent control xpc coding"
```

---

## Task 4: Add JSON lease store and audit log writer

**Objective:** Persist daemon-owned agent lease/audit metadata in an injected path so tests use temporary files and production can use `/Library/Application Support/Vifty/AgentControl/`.

**Files:**
- Create: `Sources/ViftyCore/AgentControlStore.swift`
- Test: `Tests/ViftyCoreTests/AgentControlStoreTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/AgentControlStoreTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class AgentControlStoreTests: XCTestCase {
    func testSaveAndLoadActiveLease() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let lease = AgentCoolingLease(
            id: "lease-1",
            request: AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key"),
            createdAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 1_600),
            targetRPMByFanID: [0: 3600]
        )

        try store.saveActiveLease(lease)

        XCTAssertEqual(try store.loadActiveLease(), lease)
    }

    func testAppendAuditEventWritesJSONLine() throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)

        try store.appendAuditEvent(AgentControlAuditEvent(timestamp: Date(timeIntervalSince1970: 1_000), action: "prepare", leaseID: "lease-1", message: "applied"))

        let contents = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"))
        XCTAssertTrue(contents.contains("\"action\":\"prepare\""))
        XCTAssertTrue(contents.hasSuffix("\n"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vifty-agent-store-\(UUID().uuidString)", isDirectory: true)
    }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlStoreTests 2>&1
```

Expected: FAIL — `AgentControlStore` does not exist.

**Step 3: Write minimal implementation**

Create `Sources/ViftyCore/AgentControlStore.swift`:

```swift
import Foundation

public struct AgentControlAuditEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var action: String
    public var leaseID: String?
    public var message: String

    public init(timestamp: Date, action: String, leaseID: String?, message: String) {
        self.timestamp = timestamp
        self.action = action
        self.leaseID = leaseID
        self.message = message
    }
}

public struct AgentControlStore: Sendable {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL = URL(fileURLWithPath: "/Library/Application Support/Vifty/AgentControl", isDirectory: true)) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func saveActiveLease(_ lease: AgentCoolingLease?) throws {
        try createDirectoryIfNeeded()
        let url = directory.appendingPathComponent("active-lease.json")
        if let lease {
            try encoder.encode(lease).write(to: url, options: .atomic)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func loadActiveLease() throws -> AgentCoolingLease? {
        let url = directory.appendingPathComponent("active-lease.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(AgentCoolingLease.self, from: Data(contentsOf: url))
    }

    public func appendAuditEvent(_ event: AgentControlAuditEvent) throws {
        try createDirectoryIfNeeded()
        let url = directory.appendingPathComponent("audit.jsonl")
        let data = try encoder.encode(event) + Data("\n".utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    private func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
```

**Step 4: Run test to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlStoreTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/AgentControlStore.swift Tests/ViftyCoreTests/AgentControlStoreTests.swift
git commit -m "feat: persist agent control leases"
```

---

## Task 5: Add transactional AgentControlService prepare/restore core

**Objective:** Create a testable service that validates policy, applies fixed RPM targets through `HardwareService`, stores a lease, restores Auto through the real restore path, and rolls back partial fan writes on failure.

**Files:**
- Create: `Sources/ViftyCore/AgentControlService.swift`
- Test: `Tests/ViftyCoreTests/AgentControlServiceTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/AgentControlServiceTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class AgentControlServiceTests: XCTestCase {
    func testPrepareAppliesTargetsStoresLeaseAndReportsStatus() async throws {
        let directory = temporaryDirectory()
        let hardware = AgentControlFakeHardware(snapshot: Self.supportedSnapshot())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: directory),
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key-1")

        let status = try await service.prepare(request)

        XCTAssertEqual(status.activeLease?.id, "lease-1")
        XCTAssertEqual(status.activeLease?.expiresAt, Date(timeIntervalSince1970: 1_600))
        XCTAssertEqual(await hardware.appliedCommands, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
        XCTAssertEqual(try AgentControlStore(directory: directory).loadActiveLease()?.id, "lease-1")
    }

    func testRestoreAutoRestoresFansAndClearsLease() async throws {
        let directory = temporaryDirectory()
        let hardware = AgentControlFakeHardware(snapshot: Self.supportedSnapshot())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: directory),
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key-1")
        _ = try await service.prepare(request)

        let status = try await service.restoreAuto(reason: "done")

        XCTAssertNil(status.activeLease)
        XCTAssertEqual(await hardware.restoredFanIDs, [0])
        XCTAssertNil(try AgentControlStore(directory: directory).loadActiveLease())
    }

    func testPrepareRestoresAlreadyAppliedFansWhenLaterApplyFails() async throws {
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
        let directory = temporaryDirectory()
        let hardware = AgentControlFakeHardware(snapshot: snapshot)
        await hardware.failApplyForFanID(1)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: directory),
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key-1")

        do {
            _ = try await service.prepare(request)
            XCTFail("Expected second fan apply to fail")
        } catch {
            XCTAssertEqual(await hardware.restoredFanIDs, [0], "Prepare must roll back fans that were already forced")
            XCTAssertNil(try AgentControlStore(directory: directory).loadActiveLease())
        }
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

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vifty-agent-service-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor AgentControlFakeHardware: HardwareService {
    var snapshotValue: HardwareSnapshot
    var appliedCommands: [FanCommand] = []
    var restoredFanIDs: [Int] = []
    private var failingApplyFanID: Int?

    init(snapshot: HardwareSnapshot) { self.snapshotValue = snapshot }
    func failApplyForFanID(_ fanID: Int) { failingApplyFanID = fanID }
    func snapshot() async throws -> HardwareSnapshot { snapshotValue }
    func apply(_ command: FanCommand, fan: Fan) async throws {
        if fan.id == failingApplyFanID { throw ViftyError.helperRejected("simulated apply failure") }
        appliedCommands.append(command)
    }
    func restoreAuto(fan: Fan) async throws { restoredFanIDs.append(fan.id) }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlServiceTests 2>&1
```

Expected: FAIL — `AgentControlService` does not exist.

**Step 3: Write minimal transactional implementation**

Create `Sources/ViftyCore/AgentControlService.swift`:

```swift
import Foundation

public actor AgentControlService {
    private let hardware: HardwareService
    private let policy: AgentControlPolicy
    private let store: AgentControlStore
    private let thermalReader: @Sendable () -> ThermalPressure
    private let now: @Sendable () -> Date
    private let leaseID: @Sendable () -> String
    private var activeLease: AgentCoolingLease?
    private var lastDecision: AgentControlDecision?
    private var lastErrorCode: AgentControlErrorCode?

    public init(
        hardware: HardwareService,
        policy: AgentControlPolicy,
        store: AgentControlStore = AgentControlStore(),
        thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
        now: @escaping @Sendable () -> Date = { Date() },
        leaseID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.hardware = hardware
        self.policy = policy
        self.store = store
        self.thermalReader = thermalReader
        self.now = now
        self.leaseID = leaseID
        self.activeLease = try? store.loadActiveLease()
    }

    public func status() -> AgentControlStatus {
        let current = now()
        let lease = activeLease?.isActive(at: current) == true ? activeLease : nil
        return AgentControlStatus(enabled: policy.enabled, activeLease: lease, lastDecision: lastDecision, lastErrorCode: lastErrorCode)
    }

    public func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        let snapshot = try await hardware.snapshot()
        let decision = policy.evaluate(request, snapshot: snapshot, thermalPressure: thermalReader())
        lastDecision = decision
        lastErrorCode = decision.errorCode
        guard decision.allowed else {
            try? store.appendAuditEvent(AgentControlAuditEvent(timestamp: now(), action: "prepare-denied", leaseID: nil, message: decision.message))
            return status()
        }

        var appliedFans: [Fan] = []
        do {
            for fan in snapshot.fans where fan.controllable {
                guard let target = decision.targetRPMByFanID[fan.id] else { continue }
                try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(target)), fan: fan)
                appliedFans.append(fan)
            }

            let createdAt = now()
            let lease = AgentCoolingLease(
                id: leaseID(),
                request: request,
                createdAt: createdAt,
                expiresAt: createdAt.addingTimeInterval(TimeInterval(request.durationSeconds)),
                targetRPMByFanID: decision.targetRPMByFanID
            )
            activeLease = lease
            try store.saveActiveLease(lease)
            try? store.appendAuditEvent(AgentControlAuditEvent(timestamp: createdAt, action: "prepare", leaseID: lease.id, message: request.reason))
            return status()
        } catch {
            for fan in appliedFans {
                try? await hardware.restoreAuto(fan: fan)
            }
            activeLease = nil
            try? store.saveActiveLease(nil)
            try? store.appendAuditEvent(AgentControlAuditEvent(timestamp: now(), action: "prepare-rollback", leaseID: nil, message: error.localizedDescription))
            throw error
        }
    }

    public func restoreAuto(reason: String) async throws -> AgentControlStatus {
        let snapshot = try await hardware.snapshot()
        for fan in snapshot.fans where fan.controllable {
            try await hardware.restoreAuto(fan: fan)
        }
        if let activeLease {
            try? store.appendAuditEvent(AgentControlAuditEvent(timestamp: now(), action: "restore-auto", leaseID: activeLease.id, message: reason))
        }
        activeLease = nil
        try store.saveActiveLease(nil)
        lastErrorCode = nil
        return status()
    }
}
```

**Step 4: Run test to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlServiceTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/AgentControlService.swift Tests/ViftyCoreTests/AgentControlServiceTests.swift
git commit -m "feat: add transactional agent control service"
```

## Task 6: Add daemon-independent lease monitoring, expiry, and idempotency

**Objective:** Make active leases self-restoring without requiring UI/CLI status polling, and make duplicate idempotency keys safe to retry.

**Files:**
- Modify: `Sources/ViftyCore/AgentControlService.swift`
- Test: `Tests/ViftyCoreTests/AgentControlServiceTests.swift`

**Step 1: Add failing tests**

Append to `AgentControlServiceTests`:

```swift
func testDuplicateIdempotencyKeyReturnsExistingLeaseWithoutReapplying() async throws {
    let hardware = AgentControlFakeHardware(snapshot: Self.supportedSnapshot())
    let service = AgentControlService(
        hardware: hardware,
        policy: AgentControlPolicy(enabled: true),
        store: AgentControlStore(directory: temporaryDirectory()),
        thermalReader: { .nominal },
        now: { Date(timeIntervalSince1970: 1_000) },
        leaseID: { "lease-1" }
    )
    let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "same-key")

    let first = try await service.prepare(request)
    let second = try await service.prepare(request)

    XCTAssertEqual(first.activeLease?.id, second.activeLease?.id)
    XCTAssertEqual(await hardware.appliedCommands.count, 1)
}

func testMonitorTickRestoresExpiredLeaseWithoutStatusPoll() async throws {
    let clock = AgentControlTestClock(now: Date(timeIntervalSince1970: 1_000))
    let scheduler = AgentControlManualScheduler()
    let hardware = AgentControlFakeHardware(snapshot: Self.supportedSnapshot())
    let service = AgentControlService(
        hardware: hardware,
        policy: AgentControlPolicy(enabled: true),
        store: AgentControlStore(directory: temporaryDirectory()),
        thermalReader: { .nominal },
        now: { clock.now },
        leaseID: { "lease-1" },
        expiryScheduler: scheduler.schedule(after:operation:)
    )
    _ = try await service.prepare(AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key"))

    clock.now = Date(timeIntervalSince1970: 1_061)
    await scheduler.fireLastScheduledOperation()

    XCTAssertEqual(await hardware.restoredFanIDs, [0], "Lease expiry must restore Auto even if nobody polls status")
    let status = await service.status()
    XCTAssertNil(status.activeLease)
}

func testMonitorTickRestoresWhenSensorsDisappearDuringLease() async throws {
    let scheduler = AgentControlManualScheduler()
    let hardware = AgentControlFakeHardware(snapshot: Self.supportedSnapshot())
    let service = AgentControlService(
        hardware: hardware,
        policy: AgentControlPolicy(enabled: true),
        store: AgentControlStore(directory: temporaryDirectory()),
        thermalReader: { .nominal },
        now: { Date(timeIntervalSince1970: 1_000) },
        leaseID: { "lease-1" },
        expiryScheduler: scheduler.schedule(after:operation:)
    )
    _ = try await service.prepare(AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key"))
    await hardware.setSnapshot(HardwareSnapshot(fans: Self.supportedSnapshot().fans, temperatureSensors: [], modelIdentifier: "MacBookPro18,1", isAppleSilicon: true, isMacBookPro: true))

    await scheduler.fireLastScheduledOperation()

    XCTAssertEqual(await hardware.restoredFanIDs, [0])
}
```

Add helpers:

```swift
private final class AgentControlTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(now: Date) { self.value = now }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

private final class AgentControlManualScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var operation: (@Sendable () async -> Void)?

    func schedule(after delay: TimeInterval, operation: @escaping @Sendable () async -> Void) -> AgentControlScheduledExpiry {
        lock.lock()
        self.operation = operation
        lock.unlock()
        return AgentControlScheduledExpiry { }
    }

    func fireLastScheduledOperation() async {
        lock.lock()
        let operation = self.operation
        lock.unlock()
        await operation?()
    }
}
```

Also extend `AgentControlFakeHardware`:

```swift
func setSnapshot(_ snapshot: HardwareSnapshot) {
    snapshotValue = snapshot
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlServiceTests 2>&1
```

Expected: FAIL — scheduler types and monitor behavior do not exist.

**Step 3: Add scheduler and monitor implementation**

At the top of `AgentControlService.swift`, add:

```swift
public struct AgentControlScheduledExpiry: Sendable {
    private let cancelHandler: @Sendable () -> Void

    public init(_ cancelHandler: @escaping @Sendable () -> Void) {
        self.cancelHandler = cancelHandler
    }

    public func cancel() {
        cancelHandler()
    }
}

public typealias AgentControlExpiryScheduler = @Sendable (_ delay: TimeInterval, _ operation: @escaping @Sendable () async -> Void) -> AgentControlScheduledExpiry

public enum AgentControlDefaultScheduler {
    public static func schedule(after delay: TimeInterval, operation: @escaping @Sendable () async -> Void) -> AgentControlScheduledExpiry {
        let task = Task {
            let clampedDelay = max(0, delay)
            try? await Task.sleep(nanoseconds: UInt64(clampedDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await operation()
        }
        return AgentControlScheduledExpiry { task.cancel() }
    }
}
```

Add properties to `AgentControlService`:

```swift
private let expiryScheduler: AgentControlExpiryScheduler
private var scheduledExpiry: AgentControlScheduledExpiry?
private let monitorIntervalSeconds: TimeInterval = 5
```

Update initializer with default:

```swift
expiryScheduler: @escaping AgentControlExpiryScheduler = AgentControlDefaultScheduler.schedule(after:operation:)
```

Assign `self.expiryScheduler = expiryScheduler`. If `store.loadActiveLease()` returns an active lease, call `scheduleMonitor(for:)` before the initializer returns.

Add monitor helpers:

```swift
private func scheduleMonitor(for lease: AgentCoolingLease) {
    scheduledExpiry?.cancel()
    let delay = min(max(0, lease.expiresAt.timeIntervalSince(now())), monitorIntervalSeconds)
    let leaseID = lease.id
    scheduledExpiry = expiryScheduler(delay) { [weak self] in
        await self?.monitorLease(id: leaseID)
    }
}

private func monitorLease(id: String) async {
    guard let activeLease, activeLease.id == id else { return }
    do {
        if !activeLease.isActive(at: now()) {
            _ = try await restoreAuto(reason: "Agent cooling lease expired")
            return
        }
        let snapshot = try await hardware.snapshot()
        if snapshot.temperatureSensors.isEmpty || thermalReader() == .critical {
            _ = try await restoreAuto(reason: "Agent cooling safety monitor restored Auto")
            return
        }
        scheduleMonitor(for: activeLease)
    } catch {
        _ = try? await restoreAuto(reason: "Agent cooling monitor failed: \(error.localizedDescription)")
    }
}
```

In `prepare(_:)`, before snapshot, add the duplicate idempotency guard:

```swift
if let activeLease,
   activeLease.request.idempotencyKey == request.idempotencyKey,
   activeLease.isActive(at: now()) {
    return status()
}
```

After a lease is saved, call:

```swift
scheduleMonitor(for: lease)
```

In `restoreAuto(reason:)`, before clearing state, add:

```swift
scheduledExpiry?.cancel()
scheduledExpiry = nil
```

Add a non-reapplying lease clear helper for user Auto paths:

```swift
public func clearActiveLease(reason: String) throws -> AgentControlStatus {
    scheduledExpiry?.cancel()
    scheduledExpiry = nil
    if let activeLease {
        try? store.appendAuditEvent(AgentControlAuditEvent(timestamp: now(), action: "clear-lease", leaseID: activeLease.id, message: reason))
    }
    activeLease = nil
    try store.saveActiveLease(nil)
    return status()
}
```

**Step 4: Run test to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlServiceTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/AgentControlService.swift Tests/ViftyCoreTests/AgentControlServiceTests.swift
git commit -m "feat: monitor agent cooling leases"
```

## Task 7: Allow app and viftyctl identities without accepting arbitrary clients

**Objective:** Change XPC client validation from one allowed signing identifier to a small explicit allowlist for `tech.reidar.vifty` and `tech.reidar.vifty.ctl`.

**Files:**
- Modify: `Sources/ViftyCore/XPCClientValidator.swift`
- Modify: `Sources/ViftyDaemon/main.swift`
- Test: `Tests/ViftyCoreTests/XPCClientValidatorTests.swift`

**Step 1: Write failing test**

Append to `XPCClientValidatorTests`:

```swift
func testAllowsOnlyExplicitClientAllowlist() {
    let validator = XPCClientValidator(allowedClients: [
        XPCAllowedClient(signingIdentifier: "tech.reidar.vifty", teamIdentifier: nil),
        XPCAllowedClient(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: nil)
    ])

    XCTAssertTrue(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty", teamIdentifier: nil)))
    XCTAssertTrue(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: nil)))
    XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: "tech.reidar.vifty.anything", teamIdentifier: nil)))
    XCTAssertFalse(validator.isAllowed(XPCClientIdentity(signingIdentifier: nil, teamIdentifier: nil)))
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter XPCClientValidatorTests 2>&1
```

Expected: FAIL — `XPCAllowedClient` and allowlist initializer do not exist.

**Step 3: Implement validator allowlist**

Modify `Sources/ViftyCore/XPCClientValidator.swift`:

```swift
public struct XPCAllowedClient: Equatable, Sendable {
    public let signingIdentifier: String
    public let teamIdentifier: String?

    public init(signingIdentifier: String, teamIdentifier: String?) {
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
    }
}

public struct XPCClientValidator: Sendable {
    public let allowedClients: [XPCAllowedClient]

    public init(allowedClients: [XPCAllowedClient]) {
        self.allowedClients = allowedClients
    }

    public init(allowedSigningIdentifier: String, allowedTeamIdentifier: String?) {
        self.allowedClients = [XPCAllowedClient(signingIdentifier: allowedSigningIdentifier, teamIdentifier: allowedTeamIdentifier)]
    }

    public func isAllowed(_ identity: XPCClientIdentity?) -> Bool {
        guard let identity, let signingIdentifier = identity.signingIdentifier else { return false }
        return allowedClients.contains { allowed in
            guard allowed.signingIdentifier == signingIdentifier else { return false }
            if let allowedTeamIdentifier = allowed.teamIdentifier {
                return identity.teamIdentifier == allowedTeamIdentifier
            }
            return true
        }
    }
}
```

In `Sources/ViftyDaemon/main.swift`, replace the validator initializer with:

```swift
private let validator = XPCClientValidator(allowedClients: [
    XPCAllowedClient(signingIdentifier: "tech.reidar.vifty", teamIdentifier: nil),
    XPCAllowedClient(signingIdentifier: "tech.reidar.vifty.ctl", teamIdentifier: nil)
])
```

**Step 4: Run tests and import/build check**

Run:

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter XPCClientValidatorTests 2>&1
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: tests PASS and build PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/XPCClientValidator.swift Sources/ViftyDaemon/main.swift Tests/ViftyCoreTests/XPCClientValidatorTests.swift
git commit -m "feat: allow signed viftyctl xpc client"
```

---

## Task 8: Extend daemon protocol/client for agent status, prepare, and restore

**Objective:** Add Swift-6-safe XPC methods to query status, create a workload lease, and restore Auto through daemon-owned agent control.

**Files:**
- Modify: `Sources/ViftyCore/ViftyDaemonProtocol.swift`
- Modify: `Sources/ViftyCore/ViftyDaemonClient.swift`
- Test: `Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift` (already covers payload shapes)

**Step 1: Add protocol signatures**

In `@objc public protocol ViftyDaemonProtocol`, add `@Sendable` reply closures so daemon implementations can bridge through `Task` under Swift 6:

```swift
func agentControlStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
func prepareAgentControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
func restoreAgentControl(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void)
```

**Step 2: Make the client proxy callback sendable**

In `ViftyDaemonClient.withProxy`, change the operation signature to:

```swift
private func withProxy<T: Sendable>(
    _ operation: @escaping (
        ViftyDaemonProtocol,
        @escaping @Sendable (Result<T, Error>) -> Void
    ) -> Void
) async throws -> T {
```

**Step 3: Add client methods**

In `ViftyDaemonClient`, add:

```swift
public func agentControlStatus() async throws -> AgentControlStatus {
    try await withProxy { proxy, finish in
        proxy.agentControlStatus { dictionary, error in
            if let error {
                finish(.failure(ViftyError.helperRejected(error)))
                return
            }
            guard let dictionary,
                  let status = XPCAgentControlCoding.decodeStatus(dictionary) else {
                finish(.failure(ViftyError.helperRejected("Daemon returned an invalid agent-control status.")))
                return
            }
            finish(.success(status))
        }
    }
}

public func prepareAgentControl(_ request: AgentControlRequest) async throws -> AgentControlStatus {
    try await withProxy { proxy, finish in
        proxy.prepareAgentControl(XPCAgentControlCoding.encode(request)) { dictionary, error in
            if let error {
                finish(.failure(ViftyError.helperRejected(error)))
                return
            }
            guard let dictionary,
                  let status = XPCAgentControlCoding.decodeStatus(dictionary) else {
                finish(.failure(ViftyError.helperRejected("Daemon returned an invalid agent-control prepare response.")))
                return
            }
            finish(.success(status))
        }
    }
}

public func restoreAgentControl(reason: String) async throws -> AgentControlStatus {
    try await withProxy { proxy, finish in
        proxy.restoreAgentControl(reason) { dictionary, error in
            if let error {
                finish(.failure(ViftyError.helperRejected(error)))
                return
            }
            guard let dictionary,
                  let status = XPCAgentControlCoding.decodeStatus(dictionary) else {
                finish(.failure(ViftyError.helperRejected("Daemon returned an invalid agent-control restore response.")))
                return
            }
            finish(.success(status))
        }
    }
}
```

**Step 4: Run build to verify compile failure points are only daemon implementation**

Run:

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: FAIL — `DaemonService` does not yet implement the new protocol requirements.

**Step 5: Temporarily implement daemon stubs to make the boundary compile**

In `Sources/ViftyDaemon/main.swift`, add stub methods to `DaemonService` for this task only:

```swift
func agentControlStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
    reply(XPCAgentControlCoding.encode(AgentControlStatus(enabled: false, activeLease: nil, lastDecision: nil, lastErrorCode: nil)), nil)
}

func prepareAgentControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
    reply(nil, "Agent control is not wired yet.")
}

func restoreAgentControl(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
    reply(XPCAgentControlCoding.encode(AgentControlStatus(enabled: false, activeLease: nil, lastDecision: nil, lastErrorCode: nil)), nil)
}
```

**Step 6: Run build to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 7: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/ViftyDaemonProtocol.swift Sources/ViftyCore/ViftyDaemonClient.swift Sources/ViftyDaemon/main.swift
git commit -m "feat: add agent control xpc methods"
```

## Task 9: Wire AgentControlService into the daemon

**Objective:** Replace daemon agent-control stubs with the real service while keeping Swift 6 async callback bridging compile-safe and ensuring legacy user Auto clears daemon-owned leases.

**Files:**
- Modify: `Sources/ViftyDaemon/main.swift`
- Test: existing `AgentControlServiceTests` and build gate

**Step 1: Add service property**

In `DaemonService`, add:

```swift
private let agentControl = AgentControlService(
    hardware: RealMacHardwareService(preferDaemon: false),
    policy: AgentControlPolicy(enabled: true)
)
```

**Step 2: Make existing per-fan restore clear active agent lease**

In the existing `restoreAuto(_:minimumRPM:maximumRPM:reply:)`, after `LocalFanHelperClient().restoreAuto(fan: fan)` succeeds and before `reply(true, nil)`, add a Swift-6-safe actor bridge:

```swift
let agentControl = self.agentControl
Task {
    _ = try? await agentControl.clearActiveLease(reason: "User/app restored Auto through daemon restoreAuto")
}
```

Do not call `agentControl.clearActiveLease(...)` synchronously; `AgentControlService` is an actor and the call must cross the actor boundary with `await`. This asynchronous clear is a belt-and-suspenders path; Task 15 also makes AppModel call `restoreAgentControl(reason:)` explicitly when the user selects Auto.

**Step 3: Replace stubs with Swift-6-safe async bridge methods**

Use local captures so `Task` does not capture all of `self` unnecessarily:

```swift
func agentControlStatus(reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
    let agentControl = self.agentControl
    Task {
        let status = await agentControl.status()
        reply(XPCAgentControlCoding.encode(status), nil)
    }
}

func prepareAgentControl(_ request: NSDictionary, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
    guard let decoded = XPCAgentControlCoding.decodeRequest(request) else {
        reply(nil, AgentControlErrorCode.invalidArguments.rawValue)
        return
    }
    let agentControl = self.agentControl
    Task {
        do {
            let status = try await agentControl.prepare(decoded)
            reply(XPCAgentControlCoding.encode(status), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }
}

func restoreAgentControl(_ reason: String, reply: @escaping @Sendable (NSDictionary?, String?) -> Void) {
    let agentControl = self.agentControl
    Task {
        do {
            let status = try await agentControl.restoreAuto(reason: reason)
            reply(XPCAgentControlCoding.encode(status), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }
}
```

Do not call `expireIfNeeded()` here; autonomous expiry is handled by the service scheduler from Task 6.

**Step 4: Run build and targeted tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AgentControlServiceTests 2>&1
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 5: Manual daemon build heartbeat check**

Because this touches the daemon runtime path, run:

```bash
cd /Users/reidar/Projectos/Vifty && swift build -c release --product ViftyDaemon 2>&1
```

Expected: release daemon build PASS.

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyDaemon/main.swift
git commit -m "feat: wire daemon agent control service"
```

## Task 10: Add ViftyCtl executable target and bundle signing

**Objective:** Create a new CLI executable target, copy it into the app bundle as `viftyctl`, and sign it with stable identifier `tech.reidar.vifty.ctl` so the daemon allowlist can recognize it.

**Files:**
- Modify: `Package.swift`
- Modify: `Makefile`
- Modify: `.github/workflows/ci.yml`
- Create: `Sources/ViftyCtl/main.swift`

**Step 1: Modify Package.swift**

Add product:

```swift
.executable(name: "ViftyCtl", targets: ["ViftyCtl"])
```

Add target after `ViftyHelper`:

```swift
.executableTarget(
    name: "ViftyCtl",
    dependencies: ["ViftyCore"]
),
```

**Step 2: Create minimal CLI entrypoint**

Create `Sources/ViftyCtl/main.swift`:

```swift
import Foundation
import ViftyCore

print("viftyctl: use 'status --json', 'capabilities --json', 'prepare', 'restore-auto', or 'run'.")
```

**Step 3: Update Makefile app bundle and signing order**

In `Makefile`, after copying `ViftyHelper`, add:

```make
	cp ".build/$(CONFIGURATION)/ViftyCtl" "$(MACOS)/viftyctl"
```

Replace the current final signing line:

```make
	codesign --force --deep --sign - "$(APP_DIR)"
```

with explicit nested signing followed by non-deep app signing:

```make
	codesign --force --sign - "$(MACOS)/ViftyHelper"
	codesign --force --sign - "$(MACOS)/ViftyDaemon"
	codesign --force --sign - --identifier tech.reidar.vifty.ctl "$(MACOS)/viftyctl"
	codesign --force --sign - "$(APP_DIR)"
```

Important: do **not** keep `--deep` in the signing command. `--deep` can re-sign nested executables and overwrite the explicit `tech.reidar.vifty.ctl` identifier. Keep `codesign --verify --deep --strict` as verification only.

**Step 4: Update CI bundle verification**

In `.github/workflows/ci.yml`, add after the helper/daemon executable checks:

```bash
test -x .build/Vifty.app/Contents/MacOS/viftyctl
codesign -dvvv .build/Vifty.app/Contents/MacOS/viftyctl 2>&1 | grep 'Identifier=tech.reidar.vifty.ctl'
```

Also add an install-script comparison:

```bash
cmp .build/Vifty.app/Contents/MacOS/viftyctl "${VIFTY_INSTALL_DIR}/Vifty.app/Contents/MacOS/viftyctl"
```

**Step 5: Run build to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift build --product ViftyCtl 2>&1
cd /Users/reidar/Projectos/Vifty && make app CONFIGURATION=release 2>&1
codesign --verify --deep --strict /Users/reidar/Projectos/Vifty/.build/Vifty.app
codesign -dvvv /Users/reidar/Projectos/Vifty/.build/Vifty.app/Contents/MacOS/viftyctl 2>&1 | grep 'Identifier=tech.reidar.vifty.ctl'
```

Expected: build PASS, app build PASS, signature verification PASS, grep prints `Identifier=tech.reidar.vifty.ctl`.

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Package.swift Makefile .github/workflows/ci.yml Sources/ViftyCtl/main.swift
git commit -m "feat: add bundled viftyctl executable"
```

## Task 11: Add CLI argument parsing helpers in ViftyCore

**Objective:** Parse `viftyctl` commands in pure testable code instead of testing an executable target directly.

**Files:**
- Create: `Sources/ViftyCore/ViftyCtlArguments.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlArgumentsTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/ViftyCtlArgumentsTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class ViftyCtlArgumentsTests: XCTestCase {
    func testParsesStatusJSON() throws {
        XCTAssertEqual(try ViftyCtlArguments.parse(["status", "--json"]), .status(json: true))
    }

    func testParsesPrepareRequest() throws {
        let command = try ViftyCtlArguments.parse([
            "prepare",
            "--workload", "build",
            "--duration", "45m",
            "--max-rpm-percent", "75",
            "--reason", "Release build",
            "--idempotency-key", "key-1",
            "--json"
        ])

        guard case .prepare(let request, let json) = command else { return XCTFail("Expected prepare") }
        XCTAssertTrue(json)
        XCTAssertEqual(request.workload, .build)
        XCTAssertEqual(request.durationSeconds, 2700)
        XCTAssertEqual(request.maxRPMPercent, 75)
        XCTAssertEqual(request.reason, "Release build")
        XCTAssertEqual(request.idempotencyKey, "key-1")
    }

    func testParsesRunCommandAndChildArguments() throws {
        let command = try ViftyCtlArguments.parse([
            "run",
            "--workload", "test",
            "--duration", "10m",
            "--max-rpm-percent", "70",
            "--reason", "swift test",
            "--",
            "swift", "test"
        ])

        guard case .run(let request, let childArguments) = command else { return XCTFail("Expected run") }
        XCTAssertEqual(request.workload, .test)
        XCTAssertEqual(request.durationSeconds, 600)
        XCTAssertEqual(request.maxRPMPercent, 70)
        XCTAssertEqual(request.reason, "swift test")
        XCTAssertEqual(childArguments, ["swift", "test"])
    }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ViftyCtlArgumentsTests 2>&1
```

Expected: FAIL — parser does not exist.

**Step 3: Write minimal parser**

Create `Sources/ViftyCore/ViftyCtlArguments.swift` with a small deterministic parser. Use exact enum shape:

```swift
import Foundation

public enum ViftyCtlCommand: Equatable, Sendable {
    case status(json: Bool)
    case capabilities(json: Bool)
    case prepare(AgentControlRequest, json: Bool)
    case restoreAuto(reason: String, idempotencyKey: String?, json: Bool)
    case run(AgentControlRequest, childArguments: [String])
}

public enum ViftyCtlArguments {
    public static func parse(_ arguments: [String]) throws -> ViftyCtlCommand {
        guard let command = arguments.first else { throw ViftyCtlParseError.missingCommand }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "status": return .status(json: rest.contains("--json"))
        case "capabilities": return .capabilities(json: rest.contains("--json"))
        case "prepare": return .prepare(try parseRequest(rest), json: rest.contains("--json"))
        case "restore-auto": return .restoreAuto(reason: value(after: "--reason", in: rest) ?? "manual restore", idempotencyKey: value(after: "--idempotency-key", in: rest), json: rest.contains("--json"))
        case "run":
            guard let separator = rest.firstIndex(of: "--") else { throw ViftyCtlParseError.missingChildCommand }
            let request = try parseRequest(Array(rest[..<separator]))
            let child = Array(rest[rest.index(after: separator)...])
            guard !child.isEmpty else { throw ViftyCtlParseError.missingChildCommand }
            return .run(request, childArguments: child)
        default: throw ViftyCtlParseError.unknownCommand(command)
        }
    }

    private static func parseRequest(_ arguments: [String]) throws -> AgentControlRequest {
        guard let workloadRaw = value(after: "--workload", in: arguments),
              let workload = AgentControlWorkload(rawValue: workloadRaw) else { throw ViftyCtlParseError.invalidWorkload }
        guard let durationRaw = value(after: "--duration", in: arguments),
              let duration = parseDuration(durationRaw) else { throw ViftyCtlParseError.invalidDuration }
        guard let percentRaw = value(after: "--max-rpm-percent", in: arguments),
              let percent = Int(percentRaw) else { throw ViftyCtlParseError.invalidRPMPercent }
        let reason = value(after: "--reason", in: arguments) ?? "Agent workload"
        let key = value(after: "--idempotency-key", in: arguments) ?? UUID().uuidString
        return AgentControlRequest(workload: workload, durationSeconds: duration, maxRPMPercent: percent, reason: reason, idempotencyKey: key)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    private static func parseDuration(_ raw: String) -> Int? {
        if raw.hasSuffix("m"), let minutes = Int(raw.dropLast()) { return minutes * 60 }
        if raw.hasSuffix("h"), let hours = Int(raw.dropLast()) { return hours * 60 * 60 }
        return Int(raw)
    }
}

public enum ViftyCtlParseError: Error, Equatable, Sendable {
    case missingCommand
    case unknownCommand(String)
    case invalidWorkload
    case invalidDuration
    case invalidRPMPercent
    case missingChildCommand
}
```

**Step 4: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ViftyCtlArgumentsTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/ViftyCtlArguments.swift Tests/ViftyCoreTests/ViftyCtlArgumentsTests.swift
git commit -m "feat: parse viftyctl arguments"
```

---

## Task 12: Add testable ViftyCtlRunner for read-only commands

**Objective:** Put CLI behavior behind a pure testable runner so `Sources/ViftyCtl/main.swift` remains a thin adapter and read-only commands are proven not to mutate fan state.

**Files:**
- Create: `Sources/ViftyCore/ViftyCtlRunner.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class ViftyCtlRunnerTests: XCTestCase {
    func testStatusReturnsJSONAndDoesNotMutate() async throws {
        let client = FakeAgentControlClient(status: AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil))
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner(exitCode: 0))

        let result = try await runner.run(.status(json: true))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("\"enabled\" : true") || result.stdout.contains("\"enabled\":true"))
        XCTAssertEqual(await client.prepareRequests.count, 0)
        XCTAssertEqual(await client.restoreReasons.count, 0)
    }

    func testCapabilitiesReturnsSupportedCommands() async throws {
        let runner = ViftyCtlRunner(client: FakeAgentControlClient(), processRunner: FakeProcessRunner(exitCode: 0))

        let result = try await runner.run(.capabilities(json: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("status"))
        XCTAssertTrue(result.stdout.contains("prepare"))
    }
}

private actor FakeAgentControlClient: ViftyCtlAgentControlClient {
    var statusValue: AgentControlStatus
    var prepareRequests: [AgentControlRequest] = []
    var restoreReasons: [String] = []

    init(status: AgentControlStatus = AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil)) {
        self.statusValue = status
    }

    func status() async throws -> AgentControlStatus { statusValue }
    func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus { prepareRequests.append(request); return statusValue }
    func restore(reason: String) async throws -> AgentControlStatus { restoreReasons.append(reason); return statusValue }
}

private struct FakeProcessRunner: ViftyCtlProcessRunning {
    var exitCode: Int32
    func run(_ arguments: [String]) throws -> Int32 { exitCode }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ViftyCtlRunnerTests 2>&1
```

Expected: FAIL — `ViftyCtlRunner` and protocols do not exist.

**Step 3: Implement read-only runner**

Create `Sources/ViftyCore/ViftyCtlRunner.swift`:

```swift
import Foundation

public struct ViftyCtlResult: Equatable, Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public protocol ViftyCtlAgentControlClient: Sendable {
    func status() async throws -> AgentControlStatus
    func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus
    func restore(reason: String) async throws -> AgentControlStatus
}

public protocol ViftyCtlProcessRunning: Sendable {
    func run(_ arguments: [String]) throws -> Int32
}

public struct ViftyCtlDaemonClient: ViftyCtlAgentControlClient {
    private let client: ViftyDaemonClient

    public init(client: ViftyDaemonClient = ViftyDaemonClient()) {
        self.client = client
    }

    public func status() async throws -> AgentControlStatus { try await client.agentControlStatus() }
    public func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus { try await client.prepareAgentControl(request) }
    public func restore(reason: String) async throws -> AgentControlStatus { try await client.restoreAgentControl(reason: reason) }
}

public struct ViftyCtlRunner: Sendable {
    private let client: ViftyCtlAgentControlClient
    private let processRunner: ViftyCtlProcessRunning
    private let encoder: JSONEncoder

    public init(client: ViftyCtlAgentControlClient, processRunner: ViftyCtlProcessRunning) {
        self.client = client
        self.processRunner = processRunner
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func run(_ command: ViftyCtlCommand) async throws -> ViftyCtlResult {
        switch command {
        case .status(let json):
            return try encode(await client.status(), json: json)
        case .capabilities(let json):
            let capabilities = ["status", "capabilities", "prepare", "restore-auto", "run"]
            if json {
                return ViftyCtlResult(stdout: String(data: try encoder.encode(capabilities), encoding: .utf8)! + "\n")
            }
            return ViftyCtlResult(stdout: capabilities.joined(separator: "\n") + "\n")
        case .prepare, .restoreAuto, .run:
            return ViftyCtlResult(stderr: "Command not implemented yet\n", exitCode: 64)
        }
    }

    private func encode<T: Encodable>(_ value: T, json: Bool) throws -> ViftyCtlResult {
        if json {
            return ViftyCtlResult(stdout: String(data: try encoder.encode(value), encoding: .utf8)! + "\n")
        }
        return ViftyCtlResult(stdout: String(describing: value) + "\n")
    }
}
```

**Step 4: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ViftyCtlRunnerTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/ViftyCtlRunner.swift Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift
git commit -m "feat: add viftyctl runner"
```

## Task 13: Implement `viftyctl status`, `capabilities`, `prepare`, and `restore-auto`

**Objective:** Wire the CLI main entrypoint to the testable runner and prove prepare/restore call only the daemon agent-control client, never direct SMC/helper code.

**Files:**
- Modify: `Sources/ViftyCore/ViftyCtlRunner.swift`
- Modify: `Sources/ViftyCtl/main.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift`

**Step 1: Add failing runner tests for prepare/restore**

Append to `ViftyCtlRunnerTests`:

```swift
func testPrepareCallsAgentControlClient() async throws {
    let client = FakeAgentControlClient()
    let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner(exitCode: 0))
    let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

    let result = try await runner.run(.prepare(request, json: true))

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(await client.prepareRequests, [request])
    XCTAssertEqual(await client.restoreReasons, [])
}

func testRestoreAutoCallsAgentControlRestore() async throws {
    let client = FakeAgentControlClient()
    let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner(exitCode: 0))

    let result = try await runner.run(.restoreAuto(reason: "done", idempotencyKey: nil, json: true))

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(await client.restoreReasons, ["done"])
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ViftyCtlRunnerTests 2>&1
```

Expected: FAIL — runner returns “not implemented” for prepare/restore.

**Step 3: Implement runner prepare/restore**

In `ViftyCtlRunner.run(_:)`, replace the prepare/restore cases:

```swift
case .prepare(let request, let json):
    return try encode(await client.prepare(request), json: json)
case .restoreAuto(let reason, _, let json):
    return try encode(await client.restore(reason: reason), json: json)
case .run:
    return ViftyCtlResult(stderr: "Command not implemented yet\n", exitCode: 64)
```

**Step 4: Replace CLI main with thin adapter**

Replace `Sources/ViftyCtl/main.swift` with:

```swift
import Foundation
import ViftyCore

@main
struct ViftyCtlMain {
    static func main() async {
        do {
            let command = try ViftyCtlArguments.parse(Array(CommandLine.arguments.dropFirst()))
            let runner = ViftyCtlRunner(client: ViftyCtlDaemonClient(), processRunner: ViftyCtlProcessRunner())
            let result = try await runner.run(command)
            if !result.stdout.isEmpty { FileHandle.standardOutput.write(Data(result.stdout.utf8)) }
            if !result.stderr.isEmpty { FileHandle.standardError.write(Data(result.stderr.utf8)) }
            exit(result.exitCode)
        } catch {
            FileHandle.standardError.write(Data("viftyctl failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
```

Add a placeholder process runner at the bottom of `Sources/ViftyCtl/main.swift`; Task 14 will fill in PATH behavior:

```swift
struct ViftyCtlProcessRunner: ViftyCtlProcessRunning {
    func run(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
```

**Step 5: Run tests and build CLI**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ViftyCtlRunnerTests 2>&1
cd /Users/reidar/Projectos/Vifty && swift build --product ViftyCtl 2>&1
```

Expected: PASS.

**Step 6: Build app and smoke capabilities**

```bash
cd /Users/reidar/Projectos/Vifty && make app CONFIGURATION=release 2>&1
/Users/reidar/Projectos/Vifty/.build/Vifty.app/Contents/MacOS/viftyctl capabilities --json
```

Expected: app build PASS; capabilities prints JSON array containing `"status"` and `"prepare"`.

**Step 7: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/ViftyCtlRunner.swift Sources/ViftyCtl/main.swift Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift
git commit -m "feat: implement viftyctl agent commands"
```

## Task 14: Implement `viftyctl run` guarded workload wrapper

**Objective:** Add a transactional wrapper that prepares a lease, runs a child command, restores Auto on normal child success/failure, preserves the child exit code, and relies on daemon lease monitoring as the crash/interrupt fallback.

**Files:**
- Modify: `Sources/ViftyCore/ViftyCtlRunner.swift`
- Modify: `Sources/ViftyCtl/main.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift`

**Step 1: Add failing runner tests**

Append to `ViftyCtlRunnerTests`:

```swift
func testRunPreparesRunsChildRestoresAndReturnsChildExitCode() async throws {
    let client = FakeAgentControlClient()
    let process = FakeProcessRunner(exitCode: 7)
    let runner = ViftyCtlRunner(client: client, processRunner: process)
    let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")

    let result = try await runner.run(.run(request, childArguments: ["swift", "test"]))

    XCTAssertEqual(result.exitCode, 7)
    XCTAssertEqual(await client.prepareRequests, [request])
    XCTAssertEqual(await client.restoreReasons, ["viftyctl run child exited with 7"])
}

func testRunRestoresIfChildLaunchThrows() async throws {
    let client = FakeAgentControlClient()
    let process = FakeProcessRunner(exitCode: 0, error: ViftyError.helperRejected("launch failed"))
    let runner = ViftyCtlRunner(client: client, processRunner: process)
    let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")

    do {
        _ = try await runner.run(.run(request, childArguments: ["missing-command"]))
        XCTFail("Expected child launch error")
    } catch {
        XCTAssertEqual(await client.prepareRequests, [request])
        XCTAssertEqual(await client.restoreReasons, ["viftyctl run failed to launch child: \(error.localizedDescription)"])
    }
}
```

Update `FakeProcessRunner` to accept an optional error:

```swift
private struct FakeProcessRunner: ViftyCtlProcessRunning {
    var exitCode: Int32
    var error: Error?

    init(exitCode: Int32, error: Error? = nil) {
        self.exitCode = exitCode
        self.error = error
    }

    func run(_ arguments: [String]) throws -> Int32 {
        if let error { throw error }
        return exitCode
    }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ViftyCtlRunnerTests 2>&1
```

Expected: FAIL — `.run` is not implemented.

**Step 3: Implement runner run behavior**

In `ViftyCtlRunner.run(_:)`, replace the run case:

```swift
case .run(let request, let childArguments):
    _ = try await client.prepare(request)
    do {
        let exitCode = try processRunner.run(childArguments)
        _ = try? await client.restore(reason: "viftyctl run child exited with \(exitCode)")
        return ViftyCtlResult(exitCode: exitCode)
    } catch {
        _ = try? await client.restore(reason: "viftyctl run failed to launch child: \(error.localizedDescription)")
        throw error
    }
```

**Step 4: Fix real process runner PATH behavior**

Replace `ViftyCtlProcessRunner.run(_:)` in `Sources/ViftyCtl/main.swift` with:

```swift
struct ViftyCtlProcessRunner: ViftyCtlProcessRunning {
    func run(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        if arguments[0].contains("/") {
            process.executableURL = URL(fileURLWithPath: arguments[0])
            process.arguments = Array(arguments.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = arguments
        }
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
```

Do not claim immediate SIGINT/SIGTERM restore from the wrapper unless a later task implements signal handling. The safety fallback for wrapper crashes/interrupts is the daemon-owned lease monitor from Task 6.

**Step 5: Run tests and build CLI**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ViftyCtlRunnerTests 2>&1
cd /Users/reidar/Projectos/Vifty && swift build --product ViftyCtl 2>&1
```

Expected: PASS.

**Step 6: Manual smoke for PATH resolution without fan writes**

Because real `run` prepares a fan lease, do not smoke it live unless the user approves a fan-write test. PATH resolution itself is covered by the process runner code review. If doing manual live smoke with helper approval:

```bash
/Applications/Vifty.app/Contents/MacOS/viftyctl run --workload test --duration 1m --max-rpm-percent 60 --reason smoke -- true
```

Expected with installed helper: exit code `0`, audit log records prepare + restore. Expected without helper: nonzero with clear helper error; do not claim live fan-write verification.

**Step 7: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/ViftyCtlRunner.swift Sources/ViftyCtl/main.swift Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift
git commit -m "feat: add viftyctl run wrapper"
```

## Task 15: Surface active agent lease in AppModel and menu/window UI

**Objective:** Make agent-controlled cooling visible in the menu bar and main window, and make every user Auto action clear the daemon-owned agent lease.

**Files:**
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: `Sources/Vifty/MenuBarView.swift`
- Modify: `Sources/Vifty/ContentView.swift`
- Test: `Tests/ViftyCoreTests/AppModelTests.swift`

**Step 1: Write failing AppModel status test**

Append to `AppModelTests`:

```swift
func testPollOnceRefreshesAgentControlStatus() async {
    let lease = AgentCoolingLease(
        id: "lease-1",
        request: AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key"),
        createdAt: Date(timeIntervalSince1970: 1_000),
        expiresAt: Date(timeIntervalSince1970: 1_600),
        targetRPMByFanID: [0: 3600]
    )
    let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
        fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
        temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 64, source: .smc)],
        modelIdentifier: "MacBookPro18,3",
        isAppleSilicon: true,
        isMacBookPro: true
    ))
    let model = AppModel(
        coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
        powerReader: { PowerSnapshot(percent: 50) },
        thermalReader: { .nominal },
        daemonPing: { true },
        agentStatusReader: { AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil) },
        agentRestore: { _ in AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil) }
    )

    await model.pollOnce()

    XCTAssertEqual(model.agentControlStatus?.activeLease?.id, "lease-1")
    XCTAssertTrue(model.menuTitle.contains("Agent cooling"))
}
```

**Step 2: Write failing user-Auto lease-clearing test**

Append to `AppModelTests`:

```swift
func testRestoreAutoClearsDaemonOwnedAgentLease() async {
    let lease = AgentCoolingLease(
        id: "lease-1",
        request: AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key"),
        createdAt: Date(timeIntervalSince1970: 1_000),
        expiresAt: Date(timeIntervalSince1970: 1_600),
        targetRPMByFanID: [0: 3600]
    )
    let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
        fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
        temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU", celsius: 64, source: .smc)],
        modelIdentifier: "MacBookPro18,3",
        isAppleSilicon: true,
        isMacBookPro: true
    ))
    let recorder = AgentRestoreRecorder()
    let model = AppModel(
        coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
        powerReader: { PowerSnapshot(percent: 50) },
        thermalReader: { .nominal },
        daemonPing: { true },
        agentStatusReader: { AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil) },
        agentRestore: recorder.restore(reason:)
    )
    await model.pollOnce()

    await model.restoreAutoNow()

    XCTAssertEqual(await recorder.reasons, ["User selected Auto in Vifty"])
    XCTAssertNil(model.agentControlStatus?.activeLease)
}
```

Add helper:

```swift
private actor AgentRestoreRecorder {
    var reasons: [String] = []

    func restore(reason: String) -> AgentControlStatus? {
        reasons.append(reason)
        return AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil)
    }
}
```

**Step 3: Run tests to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testPollOnceRefreshesAgentControlStatus 2>&1
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testRestoreAutoClearsDaemonOwnedAgentLease 2>&1
```

Expected: FAIL — `agentControlStatus`, `agentStatusReader`, and `agentRestore` do not exist.

**Step 4: Implement AppModel state and restore hook**

In `AppModel`, add:

```swift
@Published var agentControlStatus: AgentControlStatus?
private let agentStatusReader: @Sendable () async -> AgentControlStatus?
private let agentRestore: @Sendable (String) async -> AgentControlStatus?
```

Update initializer signature with defaults:

```swift
agentStatusReader: @escaping @Sendable () async -> AgentControlStatus? = {
    try? await ViftyDaemonClient().agentControlStatus()
},
agentRestore: @escaping @Sendable (String) async -> AgentControlStatus? = { reason in
    try? await ViftyDaemonClient().restoreAgentControl(reason: reason)
}
```

Assign both in `init`. In `pollOnce()`, after `daemonReachable = await daemonPing()`, add:

```swift
agentControlStatus = await agentStatusReader()
```

In `menuTitle`, append:

```swift
if agentControlStatus?.activeLease != nil {
    parts.append("Agent cooling")
}
```

In `restoreAutoNow()`, after `await coordinator.setMode(.auto)` and before `await pollOnce()`, add:

```swift
if agentControlStatus?.activeLease != nil {
    agentControlStatus = await agentRestore("User selected Auto in Vifty")
}
```

**Step 5: Update UI**

In `MenuBarView`, near the timed manual block, add:

```swift
if let lease = model.agentControlStatus?.activeLease {
    Label("Agent cooling until \(lease.expiresAt.formatted(date: .omitted, time: .shortened))", systemImage: "cpu")
        .font(.caption)
        .foregroundStyle(.blue)
}
```

In `ContentView.fanControlPane`, after helper health panel, add a compact panel:

```swift
if let lease = model.agentControlStatus?.activeLease {
    HStack(spacing: 8) {
        Image(systemName: "cpu")
            .foregroundStyle(.blue)
        VStack(alignment: .leading, spacing: 2) {
            Text("Agent cooling active")
                .font(.caption.weight(.semibold))
            Text("\(lease.request.workload.displayName) · Auto restore at \(lease.expiresAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Auto") { model.restoreAuto() }
            .controlSize(.small)
    }
    .padding(10)
    .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
}
```

**Step 6: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests 2>&1
```

Expected: PASS.

**Step 7: Build to catch SwiftUI compile issues**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 8: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/AppModel.swift Sources/Vifty/MenuBarView.swift Sources/Vifty/ContentView.swift Tests/ViftyCoreTests/AppModelTests.swift
git commit -m "feat: show active agent cooling lease"
```

## Task 16: Update README and AGENTS for agent control

**Objective:** Document implemented agent-control behavior, safety boundaries, and exact CLI usage without overclaiming MCP/Shortcuts or signal-safe wrapper behavior.

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

**Step 1: Update README highlights**

Add a highlight bullet:

```markdown
- **Agent-friendly cooling leases** — local agents can use bundled `viftyctl` JSON commands to request bounded temporary cooling for builds/tests, with visible state and automatic restore.
```

Add a new section after `## ViftyHelper CLI` using this exact text:

````markdown
## viftyctl agent CLI

`viftyctl` is bundled at:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl
```

It is designed for local AI/coding agents and shell automation. It exposes structured JSON and bounded workload leases rather than arbitrary raw SMC writes:

```sh
viftyctl status --json
viftyctl capabilities --json
viftyctl prepare --workload build --duration 45m --max-rpm-percent 75 --reason "Swift release build" --idempotency-key "$(uuidgen)" --json
viftyctl restore-auto --reason "workload complete" --json
viftyctl run --workload test --duration 20m --max-rpm-percent 70 --reason "swift test" -- swift test
```

Safety rules:

- Agent control is local-only through the signed CLI and privileged daemon.
- Every prepare request requires a bounded duration and reason.
- RPM targets are computed from each fan's min/max range and clamped by policy.
- User Auto restore wins over an active agent lease.
- `viftyctl run` restores Auto on normal child launch/exit; if the wrapper is killed or crashes, the daemon-owned lease monitor is the safety fallback.
- Sensor loss, unsupported hardware, helper uncertainty, or critical thermal pressure refuses or restores control.
````

**Step 2: Update AGENTS architecture rules**

Add key files:

```markdown
- `Sources/ViftyCore/AgentControlModels.swift` — Codable agent-control requests, leases, decisions, and status.
- `Sources/ViftyCore/AgentControlPolicy.swift` — conservative policy for bounded workload leases.
- `Sources/ViftyCore/AgentControlService.swift` — daemon-owned service that applies agent cooling targets and restores Auto.
- `Sources/ViftyCore/ViftyCtlArguments.swift` — pure parser for the bundled agent CLI.
- `Sources/ViftyCore/ViftyCtlRunner.swift` — testable command runner used by `viftyctl`.
- `Sources/ViftyCtl/main.swift` — thin `viftyctl` command entrypoint.
```

Add architecture rule:

```markdown
12. **Agent control is lease-based** — agents request bounded workload cooling through `viftyctl`; never expose raw SMC writes or arbitrary fixed-low RPM to agent tools. The daemon/core service owns lease monitoring, expiry, and restore; UI state is visibility and user override.
```

**Step 3: Run docs grep verification**

```bash
cd /Users/reidar/Projectos/Vifty
grep -n "viftyctl\|Agent control is lease-based\|Agent-friendly cooling leases\|daemon-owned lease monitor" README.md AGENTS.md
```

Expected: grep prints the new README and AGENTS entries.

**Step 4: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add README.md AGENTS.md
git commit -m "docs: document agent control cli"
```

## Task 17: Final local release gate and safety audit

**Objective:** Prove the full implementation passes tests, builds a release app bundle, preserves code-signing identifiers, and does not overclaim live privileged fan-write verification.

**Files:**
- No source edits unless the audit finds a bug.

**Step 1: Run full XCTest suite**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: PASS, at least 73 existing tests plus new agent-control tests.

**Step 2: Build release app**

```bash
cd /Users/reidar/Projectos/Vifty && make app CONFIGURATION=release 2>&1
```

Expected: PASS; `.build/Vifty.app` exists.

**Step 3: Verify app bundle content/signing**

```bash
cd /Users/reidar/Projectos/Vifty
codesign --verify --deep --strict .build/Vifty.app
test -x .build/Vifty.app/Contents/MacOS/Vifty
test -x .build/Vifty.app/Contents/MacOS/ViftyHelper
test -x .build/Vifty.app/Contents/MacOS/ViftyDaemon
test -x .build/Vifty.app/Contents/MacOS/viftyctl
codesign -dvvv .build/Vifty.app/Contents/MacOS/viftyctl 2>&1 | grep 'Identifier=tech.reidar.vifty.ctl'
```

Expected: all checks pass and grep prints `Identifier=tech.reidar.vifty.ctl`.

**Step 4: Verify temp install path**

```bash
cd /Users/reidar/Projectos/Vifty
rm -rf .build/ci-install
VIFTY_INSTALL_DIR="$PWD/.build/ci-install" make install
codesign --verify --deep --strict .build/ci-install/Vifty.app
cmp .build/Vifty.app/Contents/MacOS/Vifty .build/ci-install/Vifty.app/Contents/MacOS/Vifty
cmp .build/Vifty.app/Contents/MacOS/viftyctl .build/ci-install/Vifty.app/Contents/MacOS/viftyctl
```

Expected: PASS.

**Step 5: Manual safety audit checklist**

Read these files after implementation and verify by inspection:

- `Sources/ViftyCore/AgentControlPolicy.swift` — no raw low RPM path, duration/RPM bounds enforced.
- `Sources/ViftyCore/AgentControlService.swift` — prepare uses `hardware.apply`, restore uses `hardware.restoreAuto`, expiry clears stored lease.
- `Sources/ViftyCore/ViftyDaemonProtocol.swift` — optional XPC fields are conditionally inserted.
- `Sources/ViftyDaemon/main.swift` — daemon accepts only explicit app/CLI signing identifiers.
- `Sources/ViftyCtl/main.swift` — `run` restores Auto after normal child exit and resolves bare commands through `/usr/bin/env`; daemon lease monitoring is the interrupt/crash fallback.
- `README.md` — no MCP/Shortcuts/developer-ID claims unless implemented.

If the audit finds a blocker, add a RED test for that blocker, patch, rerun targeted tests + full gate before committing.

**Step 6: Commit any audit fixes or an empty closeout note only if needed**

If no source changes are needed, do not create a fake commit. If audit fixes are needed:

```bash
cd /Users/reidar/Projectos/Vifty
git add <changed-files>
git commit -m "fix: harden agent control safety"
```

---

## Task 18: Push and exact-SHA CI verification

**Objective:** Push the implementation and verify GitHub Actions for the exact pushed SHA before claiming CI success.

**Files:**
- No source edits.

**Step 1: Verify clean local tree and capture SHA**

```bash
cd /Users/reidar/Projectos/Vifty
git status --short --branch
SHA=$(git rev-parse HEAD)
printf '%s\n' "$SHA"
```

Expected: branch clean and `SHA` printed.

**Step 2: Push**

```bash
cd /Users/reidar/Projectos/Vifty
git push origin main
```

Expected: push succeeds.

**Step 3: Verify origin/main equals local SHA**

```bash
cd /Users/reidar/Projectos/Vifty
git fetch origin main --quiet
test "$(git rev-parse origin/main)" = "$(git rev-parse HEAD)"
```

Expected: exit code `0`.

**Step 4: Wait for exact CI run**

```bash
cd /Users/reidar/Projectos/Vifty
SHA=$(git rev-parse HEAD)
RUN_ID=$(gh run list --commit "$SHA" --json databaseId,workflowName,status,conclusion,headSha --limit 10 --jq '.[] | select(.workflowName == "CI" and .headSha == "'"$SHA"'") | .databaseId' | head -1)
test -n "$RUN_ID"
gh run watch "$RUN_ID" --exit-status
gh run view "$RUN_ID" --json databaseId,workflowName,status,conclusion,headSha,url,jobs
```

Expected: `status=completed`, `conclusion=success`, `headSha` equals the pushed SHA. Do not claim CI success before this completes.

**Step 5: Optional installed-app update**

Only if the user explicitly wants the live `/Applications/Vifty.app` updated:

```bash
cd /Users/reidar/Projectos/Vifty
OPEN_AFTER_INSTALL=1 make install
codesign --verify --deep --strict /Applications/Vifty.app
cmp .build/Vifty.app/Contents/MacOS/Vifty /Applications/Vifty.app/Contents/MacOS/Vifty
cmp .build/Vifty.app/Contents/MacOS/viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl
/Applications/Vifty.app/Contents/MacOS/viftyctl capabilities --json
```

Expected: install/signature/cmp pass and capabilities prints JSON. Do not force-quit a running Vifty app unless the user explicitly requests it.

---

## Plan review history

- Initial author review — checked against `AGENTS.md`, `README.md`, `Package.swift`, XPC daemon/client files, AppModel/UI files, Makefile/install script, CI workflow, `macos-iokit-telemetry` Vifty agent-control reference, and Swift desktop/SPM plan-review references.
- Independent Swift/macOS/XPC review — found blockers in passive lease expiry, Swift 6 `@Sendable` XPC callback bridging, `codesign --deep` overwriting the `viftyctl` identifier, bare `swift test` child-command PATH resolution, and UI Auto not clearing daemon-owned agent leases. Patched Tasks 6, 8, 9, 10, 14, and 15.
- Independent safety/writing-plans review — found blockers in passive lease expiry, non-transactional partial fan apply rollback, UI Auto not clearing daemon leases, inconsistent `run` parser test, missing PATH resolution, overclaiming signal-safe `run` restore, and insufficient TDD around CLI/XPC behavior. Patched Tasks 5, 6, 11, 12, 13, 14, 15, and 16.
- Focused re-review — found one remaining Swift 6 actor-isolation blocker where Task 9 synchronously called actor-isolated `clearActiveLease`. Patched Task 9 to bridge with `Task { try? await ... }` and avoid capturing non-Sendable `self`.
- Final focused re-review verdict: **APPROVED**. No remaining Swift 6 actor-isolation / `@Sendable` blockers in the patched Task 9 snippets.

## Implementation handoff

After this plan is reviewed and patched, execute with `subagent-driven-development`:

1. Dispatch one fresh subagent per task or small sequential task group.
2. Require spec-compliance review after each task.
3. Require code-quality/safety review after spec passes.
4. Parent session runs final local release gate and exact-SHA CI verification.
5. Do not claim live install, helper approval, or real fan-write smoke unless those exact external checks are performed.
