import XCTest
@testable import ViftyCore

final class RealMacHardwareServiceTests: XCTestCase {
    func testLocalSnapshotReturnsEmptyFansWhenSMCFails() {
        let service = RealMacHardwareService(
            preferDaemon: false,
            smcFactory: { throw ViftyError.smcUnavailable }
        )
        let snapshot = try! service.localSnapshot()

        XCTAssertTrue(snapshot.fans.isEmpty, "Fans should be empty when SMC is unavailable")
        XCTAssertFalse(snapshot.modelIdentifier.isEmpty, "Model identifier should always be populated")
    }

    func testLocalSnapshotReturnsMetadataOnUnsupportedHardware() {
        let service = RealMacHardwareService(
            preferDaemon: false,
            smcFactory: { throw ViftyError.smcUnavailable }
        )
        let snapshot = try! service.localSnapshot()

        if !SystemInfo.isMacBookPro {
            XCTAssertTrue(snapshot.fans.isEmpty)
            XCTAssertTrue(snapshot.temperatureSensors.isEmpty)
        }
    }
}
