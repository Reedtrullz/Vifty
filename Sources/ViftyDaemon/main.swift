import Darwin
import Dispatch
import Foundation
import ViftyCore
import ViftyDaemonSupport

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: DaemonService
    private let identityExtractor = XPCConnectionIdentityExtractor()
    private let validator = XPCClientValidator(
        allowedClients: XPCTrustConfiguration.allowedClients(from: ProcessInfo.processInfo.environment)
    )

    init(service: DaemonService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard validator.isAllowed(identityExtractor.identity(for: connection)) else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: ViftyDaemonProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

signal(SIGTERM, SIG_IGN)
let terminationGate = DaemonTerminationSignalGate()
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
terminationSource.setEventHandler {
    terminationGate.requestTermination()
}
terminationSource.resume()

do {
    let service = try await DaemonService.bootstrap()
    terminationGate.installHandler {
        Task {
            do {
                let report = try await service.prepareVoluntaryTermination()
                guard report.safeToStop,
                      report.quiesced,
                      report.restoreSucceeded,
                      report.completeExpectedSetConfirmed else {
                    FileHandle.standardError.write(Data(
                        "ViftyDaemon SIGTERM remains quiesced: Auto/System ownership was not fully confirmed.\n".utf8
                    ))
                    return
                }
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data(
                    "ViftyDaemon SIGTERM remains quiesced: \(error.localizedDescription)\n".utf8
                ))
            }
        }
    }
    let delegate = ListenerDelegate(service: service)
    let listener = NSXPCListener(machServiceName: ViftyDaemonConstants.machServiceName)
    listener.delegate = delegate
    listener.resume()
    withExtendedLifetime((delegate, terminationSource, terminationGate)) {
        RunLoop.main.run()
    }
} catch {
    FileHandle.standardError.write(Data("ViftyDaemon startup failed: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
