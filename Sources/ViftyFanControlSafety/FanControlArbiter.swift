import Foundation
import ViftyCore

public actor FanControlArbiter {
    private let hardware: any PrivilegedFanControlHardware
    private let journalStore: FanControlJournalStore
    private let exclusiveLock: FanControlExclusiveLock
    private let now: @Sendable () -> Date
    private nonisolated let restoreSignal: FanControlRestoreSignal
    private var journalGeneration: UInt64 = 0

    public init(
        hardware: any PrivilegedFanControlHardware,
        journalStore: FanControlJournalStore,
        exclusiveLock: FanControlExclusiveLock,
        now: @escaping @Sendable () -> Date = Date.init,
        restoreSignal: FanControlRestoreSignal = FanControlRestoreSignal()
    ) {
        self.hardware = hardware
        self.journalStore = journalStore
        self.exclusiveLock = exclusiveLock
        self.now = now
        self.restoreSignal = restoreSignal
    }

    /// Must be called synchronously by an XPC adapter before enqueueing the
    /// actor-isolated restore call. Apply observes the generation between fans.
    public nonisolated func requestRestorePriority() {
        restoreSignal.requestRestore()
    }

    public func currentJournalGeneration() -> UInt64 {
        journalGeneration
    }

    public func status() -> FanControlOwnershipStatus {
        do {
            guard let record = try journalStore.load() else { return .osManaged }
            let snapshot = try? hardware.freshSnapshot()
            let confirmed = snapshot.flatMap {
                try? confirmedOSManagedFanIDs(in: $0, expectedFanIDs: record.expectedFanIDs)
            } ?? []
            return FanControlOwnershipStatus(
                owner: record.owner,
                phase: record.phase,
                transactionID: record.transactionID,
                expectedFanIDs: record.expectedFanIDs,
                confirmedOSManagedFanIDs: confirmed,
                recoveryPending: record.phase == .restoring || record.phase == .restorePending,
                errorCode: record.lastErrorCode
            )
        } catch {
            return FanControlOwnershipStatus(
                owner: .recovery,
                phase: .restorePending,
                transactionID: nil,
                expectedFanIDs: [],
                recoveryPending: true,
                errorCode: "JOURNAL_UNREADABLE"
            )
        }
    }

    public func applyManual(_ request: ManualFanControlRequest) throws -> FanControlTransactionResult {
        try apply(
            transactionID: request.transactionID,
            owner: .manual(sessionID: request.sessionID),
            expectedFanIDs: request.expectedFanIDs,
            targetRPMByFanID: request.targetRPMByFanID
        )
    }

    public func applyAgent(_ request: AgentFanControlRequest) throws -> FanControlTransactionResult {
        try apply(
            transactionID: request.transactionID,
            owner: .agent(leaseID: request.leaseID),
            expectedFanIDs: request.expectedFanIDs,
            targetRPMByFanID: request.targetRPMByFanID
        )
    }

    public func restoreAuto(
        _ request: AutoRestoreRequest,
        beforeJournalClear: @escaping @Sendable () throws -> Void = {}
    ) throws -> FanControlTransactionResult {
        let restoreRequestGeneration = restoreSignal.beginRestore()
        try requireExclusiveLock()
        let snapshot = try hardware.freshSnapshot()
        let existingRecord: FanControlJournalRecord?
        let replacesUnreadableJournal: Bool
        do {
            existingRecord = try journalStore.load()
            replacesUnreadableJournal = false
        } catch let error as FanControlJournalStoreError {
            switch error {
            case .invalidRecord, .unsupportedSchemaVersion:
                try validateUnreadableJournalRecoveryAuthority(
                    request,
                    snapshot: snapshot
                )
                existingRecord = nil
                replacesUnreadableJournal = true
            default:
                throw error
            }
        }
        let expectedFanIDs: [Int]
        let transactionID: String

        if let existingRecord {
            expectedFanIDs = Array(
                Set(existingRecord.expectedFanIDs).union(request.expectedFanIDs)
            ).sorted()
            transactionID = existingRecord.transactionID
        } else if replacesUnreadableJournal,
                  request.unreadableJournalRecoveryAuthority == .durableState {
            expectedFanIDs = request.expectedFanIDs
            transactionID = request.transactionID
        } else if !request.expectedFanIDs.isEmpty && request.allowRestoreAllTrustedFans {
            throw ViftyError.helperRejected(
                "Global Auto approval cannot be combined with a caller-selected subset when no durable journal exists."
            )
        } else if !request.expectedFanIDs.isEmpty {
            expectedFanIDs = request.expectedFanIDs
            transactionID = request.transactionID
        } else if request.allowRestoreAllTrustedFans {
            guard !snapshot.fans.isEmpty,
                  snapshot.fans.map(\.id).count == Set(snapshot.fans.map(\.id)).count,
                  snapshot.fans.allSatisfy({
                      SMCFanControlKeys.isValidFanID($0.id)
                          && $0.controlEligibility.canRestoreOSManagedMode
                  }) else {
                throw ViftyError.helperRejected(
                    "Global Auto restore requires a non-empty, complete native fan inventory with trusted mode telemetry for every discovered fan."
                )
            }
            expectedFanIDs = snapshot.fans.map(\.id).sorted()
            transactionID = request.transactionID
        } else {
            throw ViftyError.helperRejected(
                "Auto recovery has no durable expected fan set; explicit restore-all approval is required."
            )
        }

        try validateExpectedFanIDs(expectedFanIDs)
        var record = existingRecord ?? FanControlJournalRecord(
            transactionID: transactionID,
            owner: .recovery,
            phase: .prepared,
            expectedFanIDs: expectedFanIDs,
            targetRPMByFanID: [:],
            createdAt: now(),
            updatedAt: now()
        )
        record.includeExpectedFanIDs(expectedFanIDs)
        record.owner = .recovery
        record.phase = .restoring
        record.updatedAt = now()
        record.lastErrorCode = nil
        journalGeneration &+= 1
        if replacesUnreadableJournal {
            try journalStore.replaceUnreadableForAuthorizedRecovery(with: record)
        } else {
            try journalStore.save(record)
        }
        let result = try performRestore(
            record: record,
            snapshot: snapshot,
            beforeJournalClear: beforeJournalClear
        )
        restoreSignal.completeRestore(through: restoreRequestGeneration)
        return result
    }

    private func validateUnreadableJournalRecoveryAuthority(
        _ request: AutoRestoreRequest,
        snapshot: HardwareSnapshot
    ) throws {
        let trustedFanIDs = try trustedCompleteFanIDs(in: snapshot)
        switch request.unreadableJournalRecoveryAuthority {
        case .durableState:
            guard !request.expectedFanIDs.isEmpty,
                  !request.allowRestoreAllTrustedFans,
                  request.expectedFanIDs == trustedFanIDs else {
                throw ViftyError.helperRejected(
                    "Unreadable journal recovery from durable state requires the complete trusted physical fan set."
                )
            }
        case .explicitOperator:
            guard request.expectedFanIDs.isEmpty,
                  request.allowRestoreAllTrustedFans else {
                throw ViftyError.helperRejected(
                    "Explicit unreadable-journal recovery requires operator-approved restore-all with no caller-selected subset."
                )
            }
        case nil:
            throw ViftyError.helperRejected(
                "Unreadable fan-control journal requires a valid durable recovery set or explicit operator-approved restore-all."
            )
        }
    }

    private func trustedCompleteFanIDs(in snapshot: HardwareSnapshot) throws -> [Int] {
        guard !snapshot.fans.isEmpty,
              snapshot.fans.map(\.id).count == Set(snapshot.fans.map(\.id)).count,
              snapshot.fans.allSatisfy({
                  SMCFanControlKeys.isValidFanID($0.id)
                      && $0.controlEligibility.canRestoreOSManagedMode
              }) else {
            throw ViftyError.helperRejected(
                "Global Auto restore requires a non-empty, complete native fan inventory with trusted mode telemetry for every discovered fan."
            )
        }
        return snapshot.fans.map(\.id).sorted()
    }

    /// Atomically proves the current journal still belongs to the caller and,
    /// only then, enters full-set Auto restoration. A foreign or absent owner
    /// returns nil without raising restore priority or touching hardware.
    public func restoreAutoIfOwned(
        transactionID: String,
        owner: FanControlOwner,
        reason: String,
        beforeJournalClear: @escaping @Sendable () throws -> Void = {}
    ) throws -> FanControlTransactionResult? {
        try requireExclusiveLock()
        guard let record = try journalStore.load(),
              record.transactionID == transactionID,
              record.owner == owner,
              record.phase == .active,
              !record.expectedFanIDs.isEmpty else {
            return nil
        }
        return try restoreAuto(
            AutoRestoreRequest(
                transactionID: record.transactionID,
                expectedFanIDs: record.expectedFanIDs,
                reason: reason,
                allowRestoreAllTrustedFans: false
            ),
            beforeJournalClear: beforeJournalClear
        )
    }

    public func recoverOnStartup() -> FanControlTransactionResult {
        do {
            guard let record = try journalStore.load() else {
                return FanControlTransactionResult(
                    transactionID: "startup-noop",
                    owner: nil,
                    phase: nil,
                    expectedFanIDs: [],
                    confirmedFanIDs: []
                )
            }
            return try restoreAuto(
                AutoRestoreRequest(
                    transactionID: record.transactionID,
                    expectedFanIDs: record.expectedFanIDs,
                    reason: "Daemon startup recovery"
                )
            )
        } catch {
            let current = status()
            return FanControlTransactionResult(
                transactionID: current.transactionID ?? "startup-recovery-unknown",
                owner: .recovery,
                phase: .restorePending,
                expectedFanIDs: current.expectedFanIDs,
                confirmedFanIDs: current.confirmedOSManagedFanIDs,
                warnings: [error.localizedDescription]
            )
        }
    }

    private func apply(
        transactionID: String,
        owner: FanControlOwner,
        expectedFanIDs: [Int],
        targetRPMByFanID: [Int: Int]
    ) throws -> FanControlTransactionResult {
        try requireExclusiveLock()
        try requireNoPendingRestore()
        try validateExpectedFanIDs(expectedFanIDs)
        guard !transactionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ViftyError.helperRejected("Fan-control transaction ID must not be blank.")
        }
        guard !targetRPMByFanID.isEmpty,
              Set(targetRPMByFanID.keys).isSubset(of: expectedFanIDs) else {
            throw ViftyError.helperRejected(
                "Resolved fan targets must be non-empty and contained in the expected fan domain."
            )
        }

        let snapshot = try hardware.freshSnapshot()
        try requireNoPendingRestore()
        let existing = try journalStore.load()
        try requireNoPendingRestore()
        if let existing,
           existing.transactionID != transactionID || existing.owner != owner || existing.phase != .active {
            throw ViftyError.helperRejected(
                "Fan control is owned by unresolved transaction \(existing.transactionID)."
            )
        }

        let reservedFanIDs = Array(Set(existing?.expectedFanIDs ?? []).union(expectedFanIDs)).sorted()
        let fansByID = try validateApplySnapshot(
            snapshot,
            expectedFanIDs: reservedFanIDs,
            existingRecord: existing
        )
        var mergedTargets = existing?.targetRPMByFanID ?? [:]
        mergedTargets.merge(targetRPMByFanID) { _, requested in requested }
        guard Set(mergedTargets.keys) == Set(reservedFanIDs) else {
            throw ViftyError.helperRejected(
                "Every expected fan must have one resolved target before the transaction can become active."
            )
        }

        if let existing,
           existing.expectedFanIDs == reservedFanIDs,
           existing.targetRPMByFanID == mergedTargets,
           (try? confirmApplied(
               snapshot,
               expectedFanIDs: reservedFanIDs,
               targetRPMByFanID: mergedTargets
           )) != nil {
            return FanControlTransactionResult(
                transactionID: existing.transactionID,
                owner: existing.owner,
                phase: existing.phase,
                expectedFanIDs: existing.expectedFanIDs,
                confirmedFanIDs: existing.expectedFanIDs
            )
        }

        journalGeneration &+= 1
        let createdAt = existing?.createdAt ?? now()
        var record = existing ?? FanControlJournalRecord(
            transactionID: transactionID,
            owner: owner,
            phase: .prepared,
            expectedFanIDs: reservedFanIDs,
            targetRPMByFanID: mergedTargets,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        record.includeExpectedFanIDs(reservedFanIDs)
        record.targetRPMByFanID = mergedTargets
        try requireNoPendingRestore()
        if existing == nil {
            try journalStore.save(record)
        }
        record.phase = .applying
        record.updatedAt = now()
        try journalStore.save(record)

        do {
            try requireNoPendingRestore()
            for fanID in targetRPMByFanID.keys.sorted() {
                try requireNoPendingRestore()
                guard let fan = fansByID[fanID], let requestedRPM = targetRPMByFanID[fanID] else {
                    throw ViftyError.helperRejected("Fan \(fanID) disappeared from the reserved transaction.")
                }
                record.includeExpectedFanIDs([fanID])
                record.updatedAt = now()
                try journalStore.save(record)
                guard try restoreSignal.performMutationIfNoRestorePending({
                    try hardware.applyFixedRPM(
                        FanCurve.clamp(requestedRPM, fan.minimumRPM, fan.maximumRPM),
                        to: fan
                    )
                }) != nil else {
                    try requireNoPendingRestore()
                    throw ViftyError.helperRejected("Fan application was blocked before the hardware mutation began.")
                }
                record.includeAppliedFanID(fanID)
                record.updatedAt = now()
                try journalStore.save(record)
            }

            try requireNoPendingRestore()
            let confirmation = try hardware.freshSnapshot()
            let confirmedFanIDs = try confirmApplied(
                confirmation,
                expectedFanIDs: reservedFanIDs,
                targetRPMByFanID: mergedTargets
            )
            record.phase = .active
            record.updatedAt = now()
            try journalStore.save(record)
            return FanControlTransactionResult(
                transactionID: transactionID,
                owner: owner,
                phase: .active,
                expectedFanIDs: reservedFanIDs,
                confirmedFanIDs: confirmedFanIDs
            )
        } catch {
            let primaryError = error
            record.owner = .recovery
            record.phase = .restoring
            record.lastErrorCode = "APPLY_FAILED"
            record.updatedAt = now()
            do {
                try journalStore.save(record)
                let rollbackGeneration = restoreSignal.requestedGeneration
                _ = try performRestore(record: record, snapshot: try hardware.freshSnapshot())
                restoreSignal.completeRestore(through: rollbackGeneration)
            } catch {
                throw ViftyError.helperRejected(
                    "Fan apply failed (\(primaryError.localizedDescription)); full Auto recovery remains pending (\(error.localizedDescription))."
                )
            }
            throw primaryError
        }
    }

    private func performRestore(
        record initialRecord: FanControlJournalRecord,
        snapshot initialSnapshot: HardwareSnapshot,
        beforeJournalClear: @escaping @Sendable () throws -> Void = {}
    ) throws -> FanControlTransactionResult {
        var record = initialRecord
        var errors: [String] = []
        let fansByID: [Int: Fan]
        do {
            fansByID = try uniqueFansByID(
                initialSnapshot.fans,
                context: "Fresh restoration fan telemetry"
            )
        } catch {
            fansByID = [:]
            errors.append(error.localizedDescription)
        }

        for fanID in record.expectedFanIDs.sorted() {
            guard let fan = fansByID[fanID] else {
                errors.append("Expected fan \(fanID) is missing before restore.")
                continue
            }
            guard fan.controlEligibility.canRestoreOSManagedMode else {
                errors.append("Fan \(fanID) lacks trusted mode telemetry for restore.")
                continue
            }
            do {
                let receipt = try hardware.restoreOSManagedMode(for: fan)
                if !receipt.recoveryConfirmed {
                    errors.append("Fan \(fanID) helper receipt did not confirm OS ownership.")
                }
            } catch let mutationError as FanMutationError {
                if !mutationError.receipt.recoveryConfirmed {
                    errors.append("Fan \(fanID) recovery failed: \(mutationError.localizedDescription)")
                }
            } catch {
                errors.append("Fan \(fanID) recovery failed: \(error.localizedDescription)")
            }
        }

        let confirmation: HardwareSnapshot?
        do {
            confirmation = try hardware.freshSnapshot()
        } catch {
            confirmation = nil
            errors.append("Fresh restoration snapshot failed: \(error.localizedDescription)")
        }
        let confirmedFanIDs: [Int]
        if let confirmation {
            do {
                confirmedFanIDs = try confirmedOSManagedFanIDs(
                    in: confirmation,
                    expectedFanIDs: record.expectedFanIDs
                )
            } catch {
                confirmedFanIDs = []
                errors.append(error.localizedDescription)
            }
        } else {
            confirmedFanIDs = []
        }
        if Set(confirmedFanIDs) != Set(record.expectedFanIDs) {
            let missing = Set(record.expectedFanIDs).subtracting(confirmedFanIDs).sorted()
            errors.append("OS ownership is unconfirmed for expected fan IDs \(missing).")
        }

        guard errors.isEmpty else {
            record.owner = .recovery
            record.phase = .restorePending
            record.lastErrorCode = "RESTORE_UNCONFIRMED"
            record.updatedAt = now()
            try journalStore.save(record)
            throw ViftyError.helperRejected(errors.joined(separator: " "))
        }

        do {
            try beforeJournalClear()
        } catch {
            let ownershipClearError = error
            record.owner = .recovery
            record.phase = .restorePending
            record.lastErrorCode = "OWNERSHIP_CLEAR_FAILED"
            record.updatedAt = now()
            do {
                try journalStore.save(record)
            } catch {
                throw ViftyError.helperRejected(
                    "Durable ownership clear failed (\(ownershipClearError.localizedDescription)) and recovery evidence could not be re-persisted (\(error.localizedDescription))."
                )
            }
            throw ownershipClearError
        }

        do {
            try journalStore.clear()
        } catch {
            let clearError = error
            record.owner = .recovery
            record.phase = .restorePending
            record.lastErrorCode = "JOURNAL_CLEAR_FAILED"
            record.updatedAt = now()
            do {
                try journalStore.save(record)
            } catch {
                throw ViftyError.helperRejected(
                    "Journal clear failed (\(clearError.localizedDescription)) and recovery evidence could not be re-persisted (\(error.localizedDescription))."
                )
            }
            throw clearError
        }
        return FanControlTransactionResult(
            transactionID: record.transactionID,
            owner: nil,
            phase: nil,
            expectedFanIDs: record.expectedFanIDs,
            confirmedFanIDs: confirmedFanIDs
        )
    }

    private func validateExpectedFanIDs(_ fanIDs: [Int]) throws {
        guard !fanIDs.isEmpty,
              fanIDs == Array(Set(fanIDs)).sorted(),
              fanIDs.allSatisfy(SMCFanControlKeys.isValidFanID) else {
            throw ViftyError.helperRejected(
                "Expected fan IDs must be non-empty, unique, sorted, and within 0 through 9."
            )
        }
    }

    private func requireExclusiveLock() throws {
        guard exclusiveLock.isHeld else {
            throw ViftyError.helperRejected(
                "Fan-control safety lock is not held; refusing all hardware writes."
            )
        }
    }

    private func requireNoPendingRestore() throws {
        guard !restoreSignal.hasPendingRestore else {
            throw ViftyError.helperRejected("Auto restoration preempted fan application.")
        }
        guard !restoreSignal.isMaintenanceQuiesced else {
            throw ViftyError.helperRejected(
                "Fan control is quiesced for helper maintenance; new ownership is blocked."
            )
        }
    }

    private func validateApplySnapshot(
        _ snapshot: HardwareSnapshot,
        expectedFanIDs: [Int],
        existingRecord: FanControlJournalRecord?
    ) throws -> [Int: Fan] {
        guard snapshot.fanControlProtocolVersion >= FanControlProtocolVersion.current else {
            throw ViftyError.helperRejected("Fan-control protocol v2 is required for writes.")
        }
        let physicalFans = snapshot.fans
        guard !physicalFans.isEmpty else {
            throw ViftyError.helperRejected("Fresh fan telemetry contains no physical fans.")
        }
        guard physicalFans.allSatisfy({
            SMCFanControlKeys.isValidFanID($0.id)
                && $0.controlEligibility.canRestoreOSManagedMode
        }) else {
            throw ViftyError.helperRejected(
                "Fresh physical fan inventory is incomplete or lacks trusted restore-mode telemetry."
            )
        }
        let fansByID = try uniqueFansByID(
            physicalFans,
            context: "Fresh fan telemetry"
        )
        guard Set(expectedFanIDs).isSubset(of: fansByID.keys) else {
            throw ViftyError.helperRejected(
                "Fresh fan telemetry is incomplete for the expected control domain."
            )
        }
        guard expectedFanIDs.allSatisfy({ fansByID[$0]?.controlEligibility.canApplyFixedRPM == true }) else {
            throw ViftyError.helperRejected("At least one expected fan is not eligible for Fixed RPM.")
        }
        let eligibleFanIDs = Set(physicalFans.filter {
            $0.controlEligibility.canApplyFixedRPM
        }.map(\.id))
        let expectedSet = Set(expectedFanIDs)
        guard expectedSet == eligibleFanIDs else {
            throw ViftyError.helperRejected(
                "The expected fan domain must exactly match every eligible native fan."
            )
        }
        if existingRecord == nil {
            guard physicalFans.allSatisfy({
                $0.hardwareMode == .automatic || $0.hardwareMode == .system
            }) else {
                throw ViftyError.helperRejected(
                    "Initial fan control requires every physical fan to be Auto/System with no unowned Forced/Unknown fan."
                )
            }
        } else {
            let forcedFanIDs = Set(physicalFans.compactMap {
                $0.hardwareMode == .forced ? $0.id : nil
            })
            guard forcedFanIDs == expectedSet,
                  physicalFans.filter({ !expectedSet.contains($0.id) }).allSatisfy({
                      $0.hardwareMode == .automatic || $0.hardwareMode == .system
                  }) else {
                throw ViftyError.helperRejected(
                    "Active fan ownership must match the exact Forced fan domain; every outside fan must remain Auto/System."
                )
            }
        }
        return fansByID
    }

    private func confirmApplied(
        _ snapshot: HardwareSnapshot,
        expectedFanIDs: [Int],
        targetRPMByFanID: [Int: Int]
    ) throws -> [Int] {
        let fansByID = try uniqueFansByID(
            snapshot.fans,
            context: "Fixed-mode confirmation telemetry"
        )
        var confirmed: [Int] = []
        for fanID in expectedFanIDs {
            guard let expectedRPM = targetRPMByFanID[fanID] else {
                throw ViftyError.helperRejected("Resolved target is missing for expected fan \(fanID).")
            }
            guard let fan = fansByID[fanID], fan.hardwareMode == .forced else {
                throw ViftyError.helperRejected("Forced-mode confirmation failed for fan \(fanID).")
            }
            if fan.targetRPM != expectedRPM {
                throw ViftyError.helperRejected("Target readback mismatch for fan \(fanID).")
            }
            confirmed.append(fanID)
        }
        return confirmed.sorted()
    }

    private func confirmedOSManagedFanIDs(
        in snapshot: HardwareSnapshot,
        expectedFanIDs: [Int]
    ) throws -> [Int] {
        let fansByID = try uniqueFansByID(
            snapshot.fans,
            context: "OS-managed confirmation telemetry"
        )
        let expected = Set(expectedFanIDs)
        return fansByID.values.compactMap { fan in
            guard expected.contains(fan.id),
                  fan.controlEligibility.canRestoreOSManagedMode,
                  fan.hardwareMode == .automatic || fan.hardwareMode == .system else {
                return nil
            }
            return fan.id
        }.sorted()
    }

    private func uniqueFansByID(
        _ fans: [Fan],
        context: String
    ) throws -> [Int: Fan] {
        var fansByID: [Int: Fan] = [:]
        fansByID.reserveCapacity(fans.count)
        for fan in fans {
            guard fansByID[fan.id] == nil else {
                throw ViftyError.helperRejected("\(context) contains duplicate fan IDs.")
            }
            fansByID[fan.id] = fan
        }
        return fansByID
    }
}

public final class FanControlRestoreSignal: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let maintenanceCondition = NSCondition()
    private var requested: UInt64 = 0
    private var completed: UInt64 = 0
    private var maintenanceGeneration: UInt64 = 0
    private var maintenanceQuiesced = false
    private var activeMutations = 0

    public init() {}

    public var requestedGeneration: UInt64 {
        lock.withLock { requested }
    }

    public var hasPendingRestore: Bool {
        lock.withLock { requested != completed }
    }

    public var isMaintenanceQuiesced: Bool {
        maintenanceCondition.withLock { maintenanceQuiesced }
    }

    public var currentMaintenanceGeneration: UInt64 {
        maintenanceCondition.withLock { maintenanceGeneration }
    }

    @discardableResult
    public func beginMaintenanceQuiesce() -> UInt64 {
        maintenanceCondition.lock()
        defer { maintenanceCondition.unlock() }
        maintenanceGeneration &+= 1
        maintenanceQuiesced = true
        while activeMutations > 0 {
            maintenanceCondition.wait()
        }
        return maintenanceGeneration
    }

    @discardableResult
    public func endMaintenanceQuiesce(through generation: UInt64) -> Bool {
        maintenanceCondition.withLock {
            guard maintenanceQuiesced, generation == maintenanceGeneration else { return false }
            maintenanceQuiesced = false
            maintenanceCondition.broadcast()
            return true
        }
    }

    public func beginExternalMutation() throws -> FanControlMutationPermit {
        guard let permit = beginMutationIfAllowed() else {
            throw ViftyError.helperRejected(
                "Fan control is quiesced for helper maintenance; external mutation is blocked."
            )
        }
        return permit
    }

    private func beginMutationIfAllowed() -> FanControlMutationPermit? {
        maintenanceCondition.withLock {
            guard !maintenanceQuiesced else { return nil }
            activeMutations += 1
            return FanControlMutationPermit(signal: self)
        }
    }

    fileprivate func finishMutation() {
        maintenanceCondition.withLock {
            guard activeMutations > 0 else { return }
            activeMutations -= 1
            if activeMutations == 0 {
                maintenanceCondition.broadcast()
            }
        }
    }

    public func requestRestore() {
        lock.withLock { requested &+= 1 }
    }

    public func beginRestore() -> UInt64 {
        lock.withLock {
            if requested == completed { requested &+= 1 }
            return requested
        }
    }

    public func completeRestore(through generation: UInt64) {
        lock.withLock {
            guard generation > completed, generation <= requested else { return }
            completed = generation
        }
    }

    /// Linearizes the final restore-pending check with the start of one
    /// physical Fixed mutation. Maintenance quiesce first prevents new permits
    /// and then waits for an already-started mutation to finish before issuing
    /// a teardown token.
    public func performMutationIfNoRestorePending<T>(
        _ mutation: () throws -> T
    ) rethrows -> T? {
        guard let maintenancePermit = beginMutationIfAllowed() else { return nil }
        defer { maintenancePermit.release() }
        lock.lock()
        defer { lock.unlock() }
        guard requested == completed else { return nil }
        return try mutation()
    }
}

public final class FanControlMutationPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var signal: FanControlRestoreSignal?

    fileprivate init(signal: FanControlRestoreSignal) {
        self.signal = signal
    }

    deinit {
        release()
    }

    public func release() {
        let signal = lock.withLock { () -> FanControlRestoreSignal? in
            defer { self.signal = nil }
            return self.signal
        }
        signal?.finishMutation()
    }
}
