import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
func agentLease(
    expiresAt: Date = Date(timeIntervalSince1970: 1600),
    targetRPMByFanID: [Int: Int] = [0: 3600]
) -> AgentCoolingLease {
    AgentCoolingLease(
        id: "lease-1",
        request: AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 75,
            reason: "Build",
            idempotencyKey: "key"
        ),
        createdAt: Date(timeIntervalSince1970: 1000),
        expiresAt: expiresAt,
        targetRPMByFanID: targetRPMByFanID
    )
}

@MainActor
func agentHardwareSnapshot(hardwareMode: FanHardwareMode? = nil) -> HardwareSnapshot {
    HardwareSnapshot(
        fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: hardwareMode)],
        temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
        modelIdentifier: "MacBookPro18,3",
        isAppleSilicon: true,
        isMacBookPro: true
    )
}

@MainActor
func temporaryMarkerPath() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vifty-app-model-tests")
        .appendingPathComponent(UUID().uuidString)
}

@MainActor
func temporaryPreferencesPath() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("vifty-app-preferences-tests")
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("app-preferences.json")
}

@MainActor
func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

@MainActor
func waitForCodexUsageSnapshot(
    _ model: AppModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    await model.waitForCodexUsageRefresh()
    XCTAssertNotNil(model.codexUsageSnapshot, file: file, line: line)
}

@MainActor
func waitForCodexUsageReadCount(
    _ expected: Int,
    recorder: CodexUsageReadRecorder,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    await recorder.waitForReadCount(expected)
    XCTAssertEqual(recorder.readCount, expected, file: file, line: line)
}

final class AppModelTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        self.value = now
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

final class AppModelPingSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool]

    init(values: [Bool]) {
        self.values = values
    }

    func next() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return false }
        return values.removeFirst()
    }
}

final class AppModelPowerSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [PowerSnapshot]

    init(values: [PowerSnapshot]) {
        self.values = values
    }

    func next() -> PowerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard values.count > 1 else { return values.first ?? PowerSnapshot() }
        return values.removeFirst()
    }
}

final class AppModelReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

final class CodexUsageReadGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isEntered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func blockUntilOpen() {
        condition.lock()
        isEntered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        condition.unlock()
        waiters.forEach { $0.resume() }

        condition.lock()
        while !isOpen {
            condition.wait()
        }
        condition.unlock()
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            condition.lock()
            if isEntered {
                condition.unlock()
                continuation.resume()
            } else {
                entryWaiters.append(continuation)
                condition.unlock()
            }
        }
    }

    func open() {
        condition.lock()
        isOpen = true
        condition.broadcast()
        condition.unlock()
    }
}

final class CodexUsageReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var nowValue: Date
    private var reads = 0
    private var readWaiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private let gate: CodexUsageReadGate?

    init(now: Date, gate: CodexUsageReadGate? = nil) {
        nowValue = now
        self.gate = gate
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    func read() -> CodexUsageSnapshot? {
        gate?.blockUntilOpen()
        lock.lock()
        reads += 1
        let readyWaiters = readWaiters.filter { reads >= $0.expected }
        readWaiters.removeAll { reads >= $0.expected }
        let snapshot = CodexUsageSnapshot(
            usedPercent: 25,
            resetDate: nil,
            updatedAt: nowValue,
            planType: nil,
            creditsSummary: nil,
            sourceFileName: "session.jsonl"
        )
        lock.unlock()
        readyWaiters.forEach { $0.continuation.resume() }
        return snapshot
    }

    func waitForReadCount(_ expected: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if reads >= expected {
                lock.unlock()
                continuation.resume()
            } else {
                readWaiters.append((expected, continuation))
                lock.unlock()
            }
        }
    }

    func currentTime() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return nowValue
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        nowValue = nowValue.addingTimeInterval(interval)
        lock.unlock()
    }
}

@MainActor
final class AppModelLaunchAtLoginRecorder: LaunchAtLoginManaging {
    private(set) var requestedValues: [Bool] = []
    private(set) var openSettingsCount = 0
    var status: LaunchAtLoginStatus
    var statusAfterEnable: LaunchAtLoginStatus = .enabled
    var statusAfterDisable: LaunchAtLoginStatus = .disabled
    var setError: Error?

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        if let setError {
            throw setError
        }
        status = enabled ? statusAfterEnable : statusAfterDisable
    }

    func openLoginItemsSettings() {
        openSettingsCount += 1
    }
}

actor AppModelAsyncGate {
    private var isOpen = false
    private var hasEntered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        hasEntered = true
        let entered = entryWaiters
        entryWaiters.removeAll()
        entered.forEach { $0.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

actor AppModelManualPollingSleeper: AppPollingSleeping {
    private var requestedDurations: [Duration] = []
    private var durationWaiters: [CheckedContinuation<Duration, Never>] = []
    private var sleepWaiters: [CheckedContinuation<Void, Error>] = []

    func sleep(for duration: Duration) async throws {
        if let waiter = durationWaiters.first {
            durationWaiters.removeFirst()
            waiter.resume(returning: duration)
        } else {
            requestedDurations.append(duration)
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepWaiters.append(continuation)
            }
        } onCancel: {
            Task { await self.cancelAll() }
        }
    }

    func nextRequestedDuration() async -> Duration {
        if !requestedDurations.isEmpty {
            return requestedDurations.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            durationWaiters.append(continuation)
        }
    }

    func cancelAll() {
        let pending = sleepWaiters
        sleepWaiters.removeAll()
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }

    func resumeNext() {
        guard !sleepWaiters.isEmpty else { return }
        sleepWaiters.removeFirst().resume()
    }
}

actor AppModelFakeHardware: HardwareService {
    enum Event: Equatable {
        case snapshot
        case restoreAuto(fanID: Int)
    }

    var snapshotValue: HardwareSnapshot
    var appliedCommands: [FanCommand] = []
    var restoredFanIDs: [Int] = []
    private var ownershipStatus: FanControlOwnershipStatus = .osManaged
    private var snapshotFailures: [Error] = []
    private var applyFailures: [Error] = []
    private var restoreFailures: [Error] = []
    private var ownershipStatusFailuresByRead: [Int: Error] = [:]
    private var ownershipStatusReads = 0
    private var snapshotGate: AppModelAsyncGate?
    private var snapshotReads = 0
    private var restoreAttempts = 0
    private var snapshotReadWaiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var shouldPauseFirstApply = false
    private var applyIsPaused = false
    private var pausedApplyWaiters: [CheckedContinuation<Void, Never>] = []
    private var applyResumeContinuation: CheckedContinuation<Void, Never>?
    private var restoreGeneration: UInt64 = 0
    private var events: [Event] = []

    init(snapshot: HardwareSnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot() async throws -> HardwareSnapshot {
        events.append(.snapshot)
        snapshotReads += 1
        let readyWaiters = snapshotReadWaiters.filter { snapshotReads >= $0.expected }
        snapshotReadWaiters.removeAll { snapshotReads >= $0.expected }
        readyWaiters.forEach { $0.continuation.resume() }
        if !snapshotFailures.isEmpty {
            throw snapshotFailures.removeFirst()
        }
        if let snapshotGate {
            await snapshotGate.wait()
        }
        return snapshotValue
    }

    func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus {
        ownershipStatusReads += 1
        if let error = ownershipStatusFailuresByRead.removeValue(forKey: ownershipStatusReads) {
            throw error
        }
        return ownershipStatus
    }

    func applyManualFanControl(
        _ request: ManualFanControlRequest
    ) async throws -> FanControlTransactionResult {
        let startingRestoreGeneration = restoreGeneration
        let fansByID = Dictionary(uniqueKeysWithValues: snapshotValue.fans.map { ($0.id, $0) })
        for fanID in request.targetRPMByFanID.keys.sorted() {
            guard let fan = fansByID[fanID], let rpm = request.targetRPMByFanID[fanID] else {
                throw ViftyError.helperRejected("Missing fake fan \(fanID).")
            }
            guard restoreGeneration == startingRestoreGeneration else {
                throw ViftyError.helperRejected("Auto restoration preempted fan application.")
            }
            try await apply(FanCommand(fanID: fanID, mode: .fixedRPM(rpm)), fan: fan)
            guard restoreGeneration == startingRestoreGeneration else {
                throw ViftyError.helperRejected("Auto restoration preempted fan application.")
            }
        }
        ownershipStatus = FanControlOwnershipStatus(
            owner: .manual(sessionID: request.sessionID),
            phase: .active,
            transactionID: request.transactionID,
            expectedFanIDs: request.expectedFanIDs,
            recoveryPending: false
        )
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: .manual(sessionID: request.sessionID),
            phase: .active,
            expectedFanIDs: request.expectedFanIDs,
            confirmedFanIDs: request.expectedFanIDs
        )
    }

    func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult {
        restoreGeneration &+= 1
        let expectedFanIDs = request.expectedFanIDs.isEmpty
            ? snapshotValue.fans.map(\.id).sorted()
            : request.expectedFanIDs
        let fansByID = Dictionary(uniqueKeysWithValues: snapshotValue.fans.map { ($0.id, $0) })
        for fanID in expectedFanIDs {
            guard let fan = fansByID[fanID] else {
                throw ViftyError.helperRejected("Missing fake fan \(fanID).")
            }
            try await restoreAuto(fan: fan)
        }
        try beforeOwnershipClear()
        ownershipStatus = .osManaged
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: nil,
            phase: nil,
            expectedFanIDs: expectedFanIDs,
            confirmedFanIDs: expectedFanIDs
        )
    }

    func setSnapshot(_ snapshot: HardwareSnapshot) {
        snapshotValue = snapshot
    }

    func setFanControlOwnershipStatus(_ status: FanControlOwnershipStatus) {
        ownershipStatus = status
    }

    func failOwnershipStatus(onRead read: Int, with error: Error) {
        ownershipStatusFailuresByRead[read] = error
    }

    func ownershipStatusReadCount() -> Int {
        ownershipStatusReads
    }

    func setSnapshotGate(_ gate: AppModelAsyncGate?) {
        snapshotGate = gate
    }

    func snapshotReadCount() -> Int {
        snapshotReads
    }

    func waitForSnapshotReadCount(_ expected: Int) async {
        guard snapshotReads < expected else { return }
        await withCheckedContinuation { continuation in
            snapshotReadWaiters.append((expected, continuation))
        }
    }

    func restoreAttemptCount() -> Int {
        restoreAttempts
    }

    func recordedEvents() -> [Event] {
        events
    }

    func failNextSnapshot(_ error: Error) {
        snapshotFailures.append(error)
    }

    func failNextApply(_ error: Error) {
        applyFailures.append(error)
    }

    func failNextRestore(_ error: Error) {
        restoreFailures.append(error)
    }

    func pauseFirstApply() {
        shouldPauseFirstApply = true
    }

    func waitForPausedApply() async {
        guard !applyIsPaused else { return }
        await withCheckedContinuation { continuation in
            pausedApplyWaiters.append(continuation)
        }
    }

    func resumePausedApply() {
        applyResumeContinuation?.resume()
        applyResumeContinuation = nil
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        if !applyFailures.isEmpty {
            throw applyFailures.removeFirst()
        }
        appliedCommands.append(command)
        if shouldPauseFirstApply {
            shouldPauseFirstApply = false
            applyIsPaused = true
            let waiters = pausedApplyWaiters
            pausedApplyWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { continuation in
                applyResumeContinuation = continuation
            }
            applyIsPaused = false
        }
    }

    func restoreAuto(fan: Fan) async throws {
        events.append(.restoreAuto(fanID: fan.id))
        restoreAttempts += 1
        if !restoreFailures.isEmpty {
            throw restoreFailures.removeFirst()
        }
        restoredFanIDs.append(fan.id)
    }
}

actor AppModelPreflightGate {
    private var firstCallStarted = false
    private var firstCallReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func ping() async -> Bool {
        guard !firstCallStarted else { return true }
        firstCallStarted = true
        let waitingForStart = startWaiters
        startWaiters.removeAll()
        waitingForStart.forEach { $0.resume() }
        guard !firstCallReleased else { return true }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
        return true
    }

    func waitUntilFirstCallStarts() async {
        guard !firstCallStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstCall() {
        firstCallReleased = true
        let waitingForRelease = releaseWaiters
        releaseWaiters.removeAll()
        waitingForRelease.forEach { $0.resume() }
    }
}

actor AppModelFailingHardware: HardwareService {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func snapshot() async throws -> HardwareSnapshot {
        throw error
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        throw error
    }

    func restoreAuto(fan: Fan) async throws {
        throw error
    }
}

actor AgentRestoreRecorder {
    var reasons: [String] = []
    private var currentStatus: AgentControlStatus

    init(activeLease: AgentCoolingLease? = nil) {
        self.currentStatus = AgentControlStatus(enabled: true, activeLease: activeLease, lastDecision: nil, lastErrorCode: nil)
    }

    func status() -> AgentControlStatus? {
        currentStatus
    }

    func restore(reason: String) -> AgentControlStatus? {
        reasons.append(reason)
        currentStatus = AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil)
        return currentStatus
    }
}

actor AgentStatusSequence {
    private var results: [Result<AgentControlStatus?, Error>]

    init(results: [Result<AgentControlStatus?, Error>]) {
        self.results = results
    }

    func next() throws -> AgentControlStatus? {
        guard !results.isEmpty else { return nil }
        return try results.removeFirst().get()
    }
}

@MainActor
final class AppModelNotificationRecorder: LocalNotificationDelivering {
    private(set) var delivered: [LocalNotification] = []
    private var deliveryResults: [Bool]
    private var authorization: LocalNotificationAuthorization
    private let authorizationRequestResult: LocalNotificationAuthorization
    private(set) var authorizationRequestCount = 0
    private var authorizationRequestWaiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var testDeliveryCount = 0
    private(set) var settingsOpenCount = 0

    init(
        deliveryResults: [Bool] = [],
        authorization: LocalNotificationAuthorization = .unavailable,
        authorizationRequestResult: LocalNotificationAuthorization? = nil
    ) {
        self.deliveryResults = deliveryResults
        self.authorization = authorization
        self.authorizationRequestResult = authorizationRequestResult ?? authorization
    }

    func deliver(_ notification: LocalNotification) async -> Bool {
        delivered.append(notification)
        guard !deliveryResults.isEmpty else { return true }
        return deliveryResults.removeFirst()
    }

    func authorizationStatus() async -> LocalNotificationAuthorization {
        authorization
    }

    func setAuthorization(_ authorization: LocalNotificationAuthorization) {
        self.authorization = authorization
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        authorizationRequestCount += 1
        let readyWaiters = authorizationRequestWaiters.filter {
            authorizationRequestCount >= $0.expected
        }
        authorizationRequestWaiters.removeAll {
            authorizationRequestCount >= $0.expected
        }
        authorization = authorizationRequestResult
        readyWaiters.forEach { $0.continuation.resume() }
        return authorization
    }

    func waitForAuthorizationRequestCount(_ expected: Int) async {
        guard authorizationRequestCount < expected else { return }
        await withCheckedContinuation { continuation in
            authorizationRequestWaiters.append((expected, continuation))
        }
    }

    func deliverTestNotification() async -> Bool {
        guard authorization == .authorized else { return false }
        testDeliveryCount += 1
        return true
    }

    func openNotificationSettings() async -> Bool {
        settingsOpenCount += 1
        return true
    }
}
