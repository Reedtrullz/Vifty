import Foundation
import XCTest
@testable import ViftyCore

final class ViftyCtlJSONExampleTests: XCTestCase {
    func testCapabilitiesExampleDecodesAgainstCurrentModel() throws {
        let capabilities = try decode(ViftyCtlCapabilities.self, from: "capabilities.json")

        XCTAssertEqual(capabilities.schemaVersion, 1)
        XCTAssertTrue(capabilities.commands.contains("diagnose"))
        XCTAssertTrue(capabilities.commands.contains("audit"))
        XCTAssertTrue(capabilities.commands.contains("run"))
        XCTAssertTrue(capabilities.workloads.contains("localModel"))
        XCTAssertEqual(capabilities.policySource, .daemonStatus)
        XCTAssertTrue(capabilities.daemonStatusAvailable)
        XCTAssertNil(capabilities.agentControlStatusError)
        XCTAssertEqual(capabilities.policy.prepareCooldownSeconds, 30)
        XCTAssertTrue(capabilities.supportsForceRetry)
        XCTAssertEqual(capabilities.runLifecycle.childCommandPreflightBeforeCooling, true)
        XCTAssertEqual(capabilities.runLifecycle.signalsForwardedToChild, ["INT", "TERM", "HUP"])
        XCTAssertEqual(capabilities.runLifecycle.autoRestoreAfterChildExit, true)
        XCTAssertEqual(capabilities.runLifecycle.structuredPreChildFailures, true)
        XCTAssertEqual(capabilities.runLifecycle.cleanupStateReportedOnLaunchFailure, true)
        XCTAssertEqual(capabilities.exitCodes.blockedReadiness, 75)
        XCTAssertEqual(capabilities.schemas.capabilities, "docs/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(capabilities.schemas.audit, "docs/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(capabilities.schemas.diagnose, "docs/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(capabilities.schemas.status, "docs/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(capabilities.schemas.commandError, "docs/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(capabilities.schemaResources.capabilities, "Contents/Resources/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(capabilities.schemaResources.audit, "Contents/Resources/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(capabilities.schemaResources.diagnose, "Contents/Resources/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(capabilities.schemaResources.status, "Contents/Resources/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(capabilities.schemaResources.commandError, "Contents/Resources/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.capabilities, "https://vifty.local/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.audit, "https://vifty.local/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.diagnose, "https://vifty.local/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.status, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.commandError, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
    }

    func testLegacyCapabilitiesPayloadDecodesWithConservativeDefaults() throws {
        var payload = try readJSON(fixtureURL("capabilities.json"))
        payload.removeValue(forKey: "supportsForceRetry")
        payload.removeValue(forKey: "runLifecycle")
        let data = try JSONSerialization.data(withJSONObject: payload)

        let capabilities = try JSONDecoder().decode(ViftyCtlCapabilities.self, from: data)

        XCTAssertFalse(capabilities.supportsForceRetry)
        XCTAssertEqual(capabilities.runLifecycle, ViftyCtlRunLifecycleCapabilities())
    }

    func testDiagnoseReadyExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlReadinessReport.self, from: "diagnose-ready.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.state, .ready)
        XCTAssertEqual(report.recommendedAgentAction, .requestCooling)
        XCTAssertEqual(report.safeToRequestCooling, true)
        XCTAssertEqual(report.modelIdentifier, "MacBookPro18,3")
        XCTAssertEqual(report.thermalPressure, .nominal)
        XCTAssertEqual(report.controllableFanCount, 2)
        XCTAssertEqual(report.fans.map(\.id), [0, 1])
        XCTAssertTrue(report.checks.contains { $0.id == "supportedHardware" && $0.passed })
        XCTAssertNil(report.daemonSnapshotError)
        XCTAssertNil(report.agentControlStatusError)
    }

    func testStatusActiveLeaseExampleDecodesAgainstCurrentModel() throws {
        let status = try decode(AgentControlStatus.self, from: "status-active-lease.json")

        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.activeLease?.id, "lease-example-test")
        XCTAssertEqual(status.activeLease?.request.workload, .test)
        XCTAssertEqual(status.activeLease?.targetRPMByFanID[0], 3600)
        XCTAssertEqual(status.lastDecision?.allowed, true)
        XCTAssertEqual(status.lastDecision?.targetRPMByFanID[1], 3700)
        XCTAssertNil(status.lastErrorCode)
    }

    func testCommandErrorExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlCommandErrorReport.self, from: "command-error.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.command, "prepare")
        XCTAssertEqual(report.errorCode, .prepareRateLimited)
        XCTAssertFalse(report.safeToProceed)
        XCTAssertFalse(report.coolingLeasePrepared)
        XCTAssertFalse(report.autoRestoreAttempted)
        XCTAssertNil(report.autoRestoreSucceeded)
        XCTAssertTrue(report.message.contains("Wait 20s"))
    }

    func testCommandErrorLegacyPayloadDecodesWithLifecycleDefaults() throws {
        let data = Data("""
        {
          "command": "prepare",
          "errorCode": "HELPER_UNREACHABLE",
          "generatedAt": 700000000,
          "message": "daemon unavailable",
          "safeToProceed": false,
          "schemaVersion": 1
        }
        """.utf8)

        let report = try JSONDecoder().decode(ViftyCtlCommandErrorReport.self, from: data)

        XCTAssertEqual(report.command, "prepare")
        XCTAssertEqual(report.errorCode, .helperUnreachable)
        XCTAssertFalse(report.safeToProceed)
        XCTAssertFalse(report.coolingLeasePrepared)
        XCTAssertFalse(report.autoRestoreAttempted)
        XCTAssertNil(report.autoRestoreSucceeded)
    }

    func testRunCleanupCommandErrorExamplesDecodeAgainstCurrentModel() throws {
        let restored = try decode(ViftyCtlCommandErrorReport.self, from: "command-error-run-cleanup-restored.json")
        XCTAssertEqual(restored.command, "run")
        XCTAssertEqual(restored.errorCode, .helperUnreachable)
        XCTAssertFalse(restored.safeToProceed)
        XCTAssertTrue(restored.coolingLeasePrepared)
        XCTAssertTrue(restored.autoRestoreAttempted)
        XCTAssertEqual(restored.autoRestoreSucceeded, true)

        let failed = try decode(ViftyCtlCommandErrorReport.self, from: "command-error-run-cleanup-failed.json")
        XCTAssertEqual(failed.command, "run")
        XCTAssertEqual(failed.errorCode, .restoreFailed)
        XCTAssertFalse(failed.safeToProceed)
        XCTAssertTrue(failed.coolingLeasePrepared)
        XCTAssertTrue(failed.autoRestoreAttempted)
        XCTAssertEqual(failed.autoRestoreSucceeded, false)
    }

    func testAuditExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlAuditReport.self, from: "audit.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertTrue(report.readOnly)
        XCTAssertFalse(report.coolingCommandsRun)
        XCTAssertEqual(report.limit, 20)
        XCTAssertEqual(report.eventCount, 2)
        XCTAssertEqual(report.events.map(\.action), ["prepare", "restore-auto"])
        XCTAssertEqual(report.events.first?.leaseID, "lease-example-test")
    }

    func testDiagnoseSchemaDocumentsRequiredSafetyContract() throws {
        let schema = try readJSON(schemaURL("viftyctl-diagnose.schema.json"))
        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "state",
            "recommendedAgentAction",
            "safeToRequestCooling",
            "isAppleSilicon",
            "isMacBookPro",
            "thermalPressure",
            "fanCount",
            "controllableFanCount",
            "temperatureSensorCount",
            "fans",
            "temperatureSensors",
            "agentControl",
            "checks"
        ] {
            XCTAssertTrue(required.contains(field), "schema should require \(field)")
        }

        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual(enumValues(named: "state", in: properties), ["ready", "degraded", "blocked"])
        XCTAssertEqual(enumValues(named: "recommendedAgentAction", in: properties), [
            "requestCooling",
            "requestCoolingWithCaution",
            "restoreAutoBeforeRequestingCooling",
            "doNotRequestCooling"
        ])
        XCTAssertEqual(enumValues(named: "thermalPressure", in: properties), [
            "nominal",
            "fair",
            "serious",
            "critical",
            "unknown"
        ])

        let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let readinessCheck = try XCTUnwrap(definitions["readinessCheck"] as? [String: Any])
        let checkProperties = try XCTUnwrap(readinessCheck["properties"] as? [String: Any])
        XCTAssertEqual(enumValues(named: "severity", in: checkProperties), ["info", "warning", "error"])
        XCTAssertEqual(enumValues(named: "id", in: checkProperties), [
            "daemonSnapshotAvailable",
            "agentControlStatusAvailable",
            "supportedHardware",
            "agentControlEnabled",
            "temperatureSensorsPresent",
            "controllableFansPresent",
            "fanIDsValid",
            "fanIDsUnique",
            "fanRangesValid",
            "thermalPressureSafe",
            "activeLeaseClear",
            "fanModeTelemetry"
        ])

        let example = try readJSON(fixtureURL("diagnose-ready.json"))
        for field in required {
            XCTAssertNotNil(example[field], "diagnose-ready.json should include required schema field \(field)")
        }
        let fans = try XCTUnwrap(example["fans"] as? [[String: Any]])
        let fanRequired = try requiredFields(for: "fanReport", in: definitions)
        for field in fanRequired {
            XCTAssertNotNil(fans.first?[field], "diagnose-ready.json fan should include \(field)")
        }
        let checks = try XCTUnwrap(example["checks"] as? [[String: Any]])
        let checkRequired = try XCTUnwrap(readinessCheck["required"] as? [String])
        for field in checkRequired {
            XCTAssertNotNil(checks.first?[field], "diagnose-ready.json check should include \(field)")
        }
    }

    func testAgentSchemasDocumentCanonicalPayloads() throws {
        let examplesReadme = try String(contentsOf: fixtureURL("README.md"), encoding: .utf8)
        let schemaExamples = [
            ("viftyctl-audit.schema.json", "audit.json"),
            ("viftyctl-capabilities.schema.json", "capabilities.json"),
            ("viftyctl-command-error.schema.json", "command-error.json"),
            ("viftyctl-command-error.schema.json", "command-error-run-cleanup-restored.json"),
            ("viftyctl-command-error.schema.json", "command-error-run-cleanup-failed.json"),
            ("viftyctl-diagnose.schema.json", "diagnose-ready.json"),
            ("viftyctl-status.schema.json", "status-active-lease.json")
        ]

        for (schemaFilename, exampleFilename) in schemaExamples {
            XCTAssertTrue(examplesReadme.contains(schemaFilename))
            let schema = try readJSON(schemaURL(schemaFilename))
            XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")

            let required = try XCTUnwrap(schema["required"] as? [String])
            let example = try readJSON(fixtureURL(exampleFilename))
            for field in required {
                XCTAssertNotNil(
                    example[field],
                    "\(exampleFilename) should include required schema field \(field)"
                )
            }
        }

        let capabilitiesSchema = try readJSON(schemaURL("viftyctl-capabilities.schema.json"))
        let capabilitiesExample = try readJSON(fixtureURL("capabilities.json"))
        let capabilitiesProperties = try XCTUnwrap(capabilitiesSchema["properties"] as? [String: Any])
        let commandItems = try XCTUnwrap((capabilitiesProperties["commands"] as? [String: Any])?["items"] as? [String: Any])
        XCTAssertEqual(commandItems["enum"] as? [String], ["status", "capabilities", "diagnose", "audit", "prepare", "restore-auto", "run"])
        XCTAssertEqual(enumValues(named: "policySource", in: capabilitiesProperties), ["daemonStatus", "fallbackUnavailable"])
        let capabilitiesDefinitions = try XCTUnwrap(capabilitiesSchema["$defs"] as? [String: Any])
        XCTAssertEqual(definitionEnumValues(named: "workload", in: capabilitiesDefinitions), ["build", "test", "render", "localModel", "custom"])
        try assertRequiredFields(
            definition: "policy",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["policy"] as? [String: Any],
            context: "capabilities policy"
        )
        try assertRequiredFields(
            definition: "exitCodes",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["exitCodes"] as? [String: Any],
            context: "capabilities exitCodes"
        )
        try assertRequiredFields(
            definition: "runLifecycle",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["runLifecycle"] as? [String: Any],
            context: "capabilities runLifecycle"
        )
        try assertRequiredFields(
            definition: "schemaPathReferences",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["schemas"] as? [String: Any],
            context: "capabilities schemas"
        )
        try assertRequiredFields(
            definition: "schemaResourceReferences",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["schemaResources"] as? [String: Any],
            context: "capabilities schemaResources"
        )
        try assertRequiredFields(
            definition: "schemaIDReferences",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["schemaIDs"] as? [String: Any],
            context: "capabilities schemaIDs"
        )

        let statusSchema = try readJSON(schemaURL("viftyctl-status.schema.json"))
        let statusDefinitions = try XCTUnwrap(statusSchema["$defs"] as? [String: Any])
        XCTAssertEqual(definitionEnumValues(named: "workload", in: statusDefinitions), ["build", "test", "render", "localModel", "custom"])
        XCTAssertEqual(definitionEnumValues(named: "errorCode", in: statusDefinitions), agentErrorCodeStrings)
        let statusExample = try readJSON(fixtureURL("status-active-lease.json"))
        let activeLease = try XCTUnwrap(statusExample["activeLease"] as? [String: Any])
        try assertRequiredFields(definition: "lease", in: statusDefinitions, arePresentIn: activeLease, context: "active lease")
        try assertRequiredFields(definition: "request", in: statusDefinitions, arePresentIn: activeLease["request"] as? [String: Any], context: "lease request")
        try assertRequiredFields(definition: "decision", in: statusDefinitions, arePresentIn: statusExample["lastDecision"] as? [String: Any], context: "last decision")
        try assertRequiredFields(definition: "policy", in: statusDefinitions, arePresentIn: statusExample["policy"] as? [String: Any], context: "status policy")

        let commandErrorSchema = try readJSON(schemaURL("viftyctl-command-error.schema.json"))
        let commandErrorProperties = try XCTUnwrap(commandErrorSchema["properties"] as? [String: Any])
        let safeToProceed = try XCTUnwrap(commandErrorProperties["safeToProceed"] as? [String: Any])
        XCTAssertEqual(safeToProceed["const"] as? Bool, false)
        XCTAssertNotNil(commandErrorProperties["coolingLeasePrepared"] as? [String: Any])
        XCTAssertNotNil(commandErrorProperties["autoRestoreAttempted"] as? [String: Any])
        XCTAssertNotNil(commandErrorProperties["autoRestoreSucceeded"] as? [String: Any])
        XCTAssertEqual(oneOfEnumValues(named: "errorCode", in: commandErrorProperties), agentErrorCodeStrings)
        let commandErrorExample = try readJSON(fixtureURL("command-error.json"))
        XCTAssertEqual(commandErrorExample["safeToProceed"] as? Bool, false)
        XCTAssertEqual(commandErrorExample["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(commandErrorExample["autoRestoreAttempted"] as? Bool, false)
        XCTAssertTrue(commandErrorExample["autoRestoreSucceeded"] is NSNull)

        let auditSchema = try readJSON(schemaURL("viftyctl-audit.schema.json"))
        let auditProperties = try XCTUnwrap(auditSchema["properties"] as? [String: Any])
        XCTAssertEqual((auditProperties["readOnly"] as? [String: Any])?["const"] as? Bool, true)
        XCTAssertEqual((auditProperties["coolingCommandsRun"] as? [String: Any])?["const"] as? Bool, false)
        let auditDefinitions = try XCTUnwrap(auditSchema["$defs"] as? [String: Any])
        let auditExample = try readJSON(fixtureURL("audit.json"))
        let auditEvents = try XCTUnwrap(auditExample["events"] as? [[String: Any]])
        try assertRequiredFields(
            definition: "auditEvent",
            in: auditDefinitions,
            arePresentIn: auditEvents.first,
            context: "audit event"
        )
    }

    func testCapabilitiesSchemaReferencesPointToExistingSchemas() throws {
        let capabilities = try decode(ViftyCtlCapabilities.self, from: "capabilities.json")

        let references = [
            (capabilities.schemas.capabilities, capabilities.schemaIDs.capabilities),
            (capabilities.schemas.audit, capabilities.schemaIDs.audit),
            (capabilities.schemas.diagnose, capabilities.schemaIDs.diagnose),
            (capabilities.schemas.status, capabilities.schemaIDs.status),
            (capabilities.schemas.commandError, capabilities.schemaIDs.commandError)
        ]
        for (schemaPath, schemaID) in references {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(schemaPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing schema at \(schemaPath)")
            let schema = try readJSON(url)
            XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
            XCTAssertEqual(schema["$id"] as? String, schemaID)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from filename: String) throws -> T {
        let data = try Data(contentsOf: fixtureURL(filename))
        return try JSONDecoder().decode(type, from: data)
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func enumValues(named propertyName: String, in properties: [String: Any]) -> [String] {
        guard
            let property = properties[propertyName] as? [String: Any],
            let values = property["enum"] as? [String]
        else {
            return []
        }
        return values
    }

    private func definitionEnumValues(named definitionName: String, in definitions: [String: Any]) -> [String] {
        guard
            let definition = definitions[definitionName] as? [String: Any],
            let values = definition["enum"] as? [String]
        else {
            return []
        }
        return values
    }

    private func oneOfEnumValues(named propertyName: String, in properties: [String: Any]) -> [String] {
        guard
            let property = properties[propertyName] as? [String: Any],
            let oneOf = property["oneOf"] as? [[String: Any]]
        else {
            return []
        }
        return oneOf.compactMap { $0["enum"] as? [String] }.flatMap { $0 }
    }

    private func requiredFields(for definitionName: String, in definitions: [String: Any]) throws -> [String] {
        let definition = try XCTUnwrap(definitions[definitionName] as? [String: Any])
        return try XCTUnwrap(definition["required"] as? [String])
    }

    private func assertRequiredFields(
        definition: String,
        in definitions: [String: Any],
        arePresentIn object: [String: Any]?,
        context: String
    ) throws {
        let object = try XCTUnwrap(object)
        for field in try requiredFields(for: definition, in: definitions) {
            XCTAssertNotNil(object[field], "\(context) should include required schema field \(field)")
        }
    }

    private var agentErrorCodeStrings: [String] {
        [
            "AGENT_CONTROL_DISABLED",
            "UNSUPPORTED_HARDWARE",
            "HELPER_UNREACHABLE",
            "TEMP_SENSOR_UNAVAILABLE",
            "NO_CONTROLLABLE_FANS",
            "POLICY_DENIED",
            "DURATION_TOO_LONG",
            "RPM_OUT_OF_RANGE",
            "THERMAL_CRITICAL",
            "LEASE_NOT_FOUND",
            "RESTORE_FAILED",
            "INVALID_ARGUMENTS",
            "PREPARE_RATE_LIMITED",
            "RESTORE_REQUESTED"
        ]
    }

    private func fixtureURL(_ filename: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/examples/viftyctl")
            .appendingPathComponent(filename)
    }

    private func schemaURL(_ filename: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas")
            .appendingPathComponent(filename)
    }
}
