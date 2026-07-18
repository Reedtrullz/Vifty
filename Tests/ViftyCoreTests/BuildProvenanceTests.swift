import Foundation
import XCTest
import ViftyBuildProvenance

final class BuildProvenanceTests: XCTestCase {
    func testExactCanonicalSectionRoundTrips() throws {
        let expected = TestBuildProvenance.identity(role: "debug-fixture-app")
        let data = try TestBuildProvenance.thinMachO(provenance: expected)

        let actual = try ViftyBuildProvenanceReader.read(
            data: data,
            expectedRole: "debug-fixture-app",
            expectedConfiguration: "debug"
        )

        XCTAssertEqual(actual, expected)
    }

    func testMissingDuplicateMalformedAndRoleMismatchedSectionsFailClosed() throws {
        XCTAssertThrowsError(
            try ViftyBuildProvenanceReader.read(
                data: TestBuildProvenance.thinMachO(payloads: []),
                expectedRole: "debug-fixture-app"
            )
        )
        XCTAssertThrowsError(
            try ViftyBuildProvenanceReader.read(
                data: TestBuildProvenance.thinMachO(
                    provenance: TestBuildProvenance.identity(role: "debug-fixture-app"),
                    duplicateSection: true
                ),
                expectedRole: "debug-fixture-app"
            )
        )
        XCTAssertThrowsError(
            try ViftyBuildProvenanceReader.read(
                data: TestBuildProvenance.thinMachO(payloads: [Data("{not-json".utf8)])
            )
        )
        XCTAssertThrowsError(
            try ViftyBuildProvenanceReader.read(
                data: TestBuildProvenance.thinMachO(
                    provenance: TestBuildProvenance.identity(role: "release-exclusion")
                ),
                expectedRole: "debug-fixture-app",
                expectedConfiguration: "debug"
            )
        )
    }
}
