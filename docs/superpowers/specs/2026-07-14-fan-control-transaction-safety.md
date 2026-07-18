# Vifty Fan-Control Transaction Safety Specification

**Status:** Authoritative contract baseline for the in-progress whole-app remediation on `codex/vifty-whole-app-remediation`. Implementation is not release-ready until the plan's focused, full, installed-app, and separately supervised hardware gates are satisfied.

**Applies to:** manual Fixed/Curve control, bounded agent cooling, Auto restoration, startup recovery, helper repair, app termination, installation, uninstall, and legacy control-protocol compatibility.

**Source plan:** `docs/superpowers/plans/2026-07-14-vifty-whole-app-review-remediation.md`

## Recorded Baseline — 14-07-2026 01:19 CEST

| Fact | Recorded value | Evidence boundary |
| --- | --- | --- |
| Branch | `codex/vifty-whole-app-remediation` | `git branch --show-current` |
| Source commit | `21c2f9175dccb9226d6972574070bc21dbede2f0` | `git rev-parse HEAD` |
| Installed app | `1.3.2` build `7` | Installed app `Info.plist` |
| Repository-recorded public artifact SHA-256 | `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0` | `Casks/vifty.rb` at the recorded source commit |
| Bundled daemon SHA-256 | `7543c573528a57bb096b045b9a7476b1d4da4aef88b7cd8b54d4cd2ca5bf7dac` | Read-only local hash |
| Installed daemon SHA-256 | `7543c573528a57bb096b045b9a7476b1d4da4aef88b7cd8b54d4cd2ca5bf7dac` | Read-only local hash; matches the installed app bundle |
| Manual-control marker | Present | Read-only file-existence check |
| Hardware ownership evidence | Fans `0` and `1` reported Forced; no agent lease; `manualControlActive: true`; `safeToRequestCooling: false` | Installed `viftyctl diagnose --json`, a read-only diagnostic |
| Free space | `57Gi` on `/System/Volumes/Data` | `df -h /System/Volumes/Data`; above the `30Gi` stop threshold |

### Baseline non-claims

- The public artifact was not downloaded or re-verified in this baseline step; its SHA is the value recorded in repository release metadata.
- Matching daemon hashes prove byte parity only. They do not prove helper startup, Auto restoration, or fan-control compatibility.
- No fan command, Auto restoration, cooling lease, helper install/repair, app launch, or supervised hardware smoke was performed.
- The existing Forced/manual state belongs to the user and was deliberately preserved.
- Exact-build Fixed, Curve, Auto, and agent-smoke compatibility remain pending, separate claims.

## Terms

- **Expected fan set:** the complete, monotonic set of fan IDs whose physical state may have been affected by a control session. It is independent of the smaller set of commands that happen to need a write during one tick.
- **OS-managed:** fresh telemetry reports fan mode `.automatic` or `.system`. A System-managed result is safe ownership evidence but is not literal mode-`0` Auto compatibility evidence.
- **Confirmed restoration:** every ID in the expected fan set is present in one fresh trusted snapshot and is OS-managed, with guarded force-test state disabled when the key exists.
- **Control transaction:** a logically atomic ownership operation. SMC writes remain physically sequential; durability, exclusion, rollback, and confirmation provide the atomic safety boundary.
- **Recovery pending:** Vifty cannot prove the complete expected set is OS-managed. New control and destructive helper teardown remain blocked.
- **Trusted telemetry:** native daemon-local telemetry whose fan identity and required control keys passed provenance and validity checks. Caller-supplied bounds and display fallbacks are never trusted.

## Non-Negotiable Invariants

### INV-01 — One privileged mutation authority

While the daemon is live, every privileged fan write passes through one daemon-owned arbiter. Offline Auto-only maintenance may use the same journal and transaction layer only while holding the cross-process exclusive lock. The app, `viftyctl`, local fallback, repair scripts, `ViftyHelper`, agent control, and legacy XPC cannot create parallel write authorities.

### INV-02 — Write-ahead expected-fan durability

A private, durable journal containing the complete expected fan set exists and is synchronized before the first physical mutation. A persistence failure before that point produces zero SMC writes.

### INV-03 — Expected fan IDs never shrink

Expected fan IDs may expand, but never shrink, until confirmed restoration. Command optimization, partial snapshots, helper errors, or process restarts cannot remove an ID from the recovery obligation.

### INV-04 — Rollback includes the failing fan

The fan whose helper operation throws is included in outer rollback even if the helper did not return a success receipt. Helper-local cleanup is defense in depth, not proof that the fan remained unchanged.

### INV-05 — Recovery evidence clears last

Manual markers, agent leases, and the transaction journal are not cleared until the same restoration transaction confirms the complete expected set. Durable clear ordering is lease first, journal second, and the user-home legacy marker last.

### INV-06 — Unknown telemetry cannot authorize or prove

Empty, partial, legacy, corrupt, missing, caller-forged, or synthesized telemetry cannot authorize Fixed RPM and cannot prove restoration. A corrupt journal cannot trigger automatic fan writes unless its expected set is reconstructed from another valid durable v2 record.

### INV-07 — Ownership is exclusive and Auto has priority

Manual, agent, and recovery ownership are mutually exclusive. A restore request preempts apply at a bounded fan boundary, prevents further apply writes, and blocks all new ownership until recovery resolves.

### INV-08 — Protocol mismatch is fail-closed

A new client facing a protocol older than v2 keeps read-only telemetry but cannot control fans. Repair/install remains disabled until the Auto-aware lifecycle is available; no client silently falls back to legacy per-fan writes.

### INV-09 — Automated work remains hardware-read-only

Diagnostics, tests, builds, fixture UI, review, repair preflight, and release verification do not invoke real fan commands, Auto restoration, cooling leases, helper mutation, or AppleSMC writes. Hardware evidence is a later, explicitly human-supervised gate.

### INV-10 — Existing safety authorities remain intact

`FanCurve.clamp()` remains the RPM clamp authority; the SMC write-key allowlist is not broadened; control persistence remains private and root-owned; release TeamID enforcement remains required; and the default maximum agent lease remains 30 minutes.

## Eligibility Is Operation-Specific

Telemetry exposes two separate capabilities:

| Capability | Minimum proof | Missing target-key behavior |
| --- | --- | --- |
| Apply Fixed RPM | Valid fan ID, native bounds, valid range, writable mode key, writable target key, trusted provenance | Blocked |
| Restore OS-managed mode | Valid fan ID, writable/readable mode key, trusted provenance, and mode readback; optional `Ftst` must be cleared and confirmed when present | Mode-only recovery may proceed; target reset is best-effort hygiene after OS ownership is confirmed |

The daemon rereads all authorization telemetry locally. Client-supplied minimum/maximum RPM values are display data only.

## Durable State Model

| State | Durable/in-memory meaning | Permitted next operations |
| --- | --- | --- |
| `idleOSManaged` | No recovery journal; daemon has fresh evidence of OS ownership or has not yet accepted a write | Read-only operations; begin a new transaction after fresh validation |
| `prepared` | Journal is synchronized with owner, transaction ID, and complete expected fan set; no write is assumed | Apply, or restore the expected set |
| `applying` | One or more expected fans may have been mutated | Continue only for the reserved owner, or preempt into restore |
| `activeManual` | Manual transaction and expected set are durable and confirmed | Manual reassert/update for the same session, or restore |
| `activeAgent` | Agent journal and durable lease agree and are confirmed | Monitor, expiry, explicit restore, or safety restore |
| `restoring` | Auto/System restoration is in progress for the complete expected set | Restoration only |
| `restorePending` | Restoration or persistence cleanup is unconfirmed | Read-only status and bounded retry; no new control or teardown |
| `unknownRecovery` | Journal is corrupt/newer than understood and scope cannot be reconstructed | Read-only status; explicit operator recovery only |
| `maintenanceQuiesced` | New ownership is rejected and a single-use maintenance token is bound to a confirmed safe generation | Bounded repair/uninstall action, or return to idle |

## Required Transition Ordering

### Manual apply

1. Read fresh trusted telemetry.
2. Resolve the full expected fan set separately from the changed-command batch.
3. Reserve manual ownership and a transaction generation.
4. Persist and synchronize `prepared` with the full expected set.
5. Enter `applying`; execute transactional helper operations in stable fan-ID order.
6. Stop at the next fan boundary if the restore signal generation changed.
7. Read one fresh snapshot and confirm every expected fan is Forced at its resolved target.
8. Persist `activeManual`.
9. Mirror the confirmed state to the user-home marker. Marker failure does not erase daemon ownership.

### Agent prepare

1. Perform the same telemetry and policy validation and allocate the lease/transaction ID.
2. Persist and synchronize the agent `prepared` journal before SMC mutation.
3. Apply and confirm the complete expected set through the arbiter.
4. Save the active lease durably.
5. Persist `activeAgent` and schedule its monitor.
6. If lease persistence fails, enter restoration for the complete expected set; never expose the prepare as successful.

### Restore Auto/System ownership

1. Signal restore priority before queueing work behind the arbiter.
2. Persist and synchronize `restoring` without shrinking the expected set.
3. Attempt Auto-only cleanup for every expected fan, including any failing apply fan.
4. Continue independent cleanup attempts even when one fan or cleanup step fails.
5. Read one fresh trusted snapshot after all attempts.
6. Confirm every expected ID is present and `.automatic` or `.system`; confirm `Ftst=0` when available.
7. Clear the durable agent lease, if present.
8. Clear the journal.
9. Clear the legacy user-home marker.
10. Publish `idleOSManaged`. Any failure before step 10 retains or recreates recovery-pending evidence and blocks control.

### Maintenance

1. Quiesce new ownership through the live arbiter.
2. Restore and confirm the complete expected set.
3. Acquire/retain the cross-process exclusive lock.
4. Issue a short-lived, single-use token bound to boot/session identity, journal generation, expected IDs, and helper identity.
5. Invalidate the token on any ownership or generation change.
6. Only then may repair/uninstall boot out, replace, or remove privileged components.

## Helper Transaction Contract

Before the first write for one fan, the helper resolves and validates mode, target, optional `Ftst`, data types, sizes, and encoded bytes. Fixed RPM then writes mode and target and reads both back. After any partial failure, it independently attempts OS-managed mode, target hygiene, and `Ftst=0`, then reads safety state back.

A helper receipt records requested and observed mode, observed target, `Ftst` cleanup, warnings, and whether local recovery was confirmed. The daemon still treats the fan as part of the expected set and performs full outer restoration after any thrown helper operation.

### Implementation sequencing note

Task 2 keeps the transactional helper implementation in `ViftyCore` for its coherent focused gate. Moving it into the internal `ViftyFanControlSafety` target is deferred to the atomic Task 3/4 daemon cutover: the current `RealMacHardwareService` still constructs the helper, so moving it earlier would create a package dependency cycle or leave a privileged path uncompilable. This sequencing change does not widen access; automated work remains hardware-read-only, and the final architecture still requires privileged mutation behind the daemon safety target.

## Concurrency And Process Exclusion

- The daemon arbiter serializes logical ownership and privileged hardware transactions.
- A thread-safe restore-generation signal is set before an Auto request waits for the arbiter; apply checks it between fan mutations.
- The daemon holds the cross-process safety lock for its lifetime. Offline maintenance acquires the same lock only after launchd is quiesced and before constructing a write-capable helper.
- A check that the daemon is absent is not sufficient; lock acquisition is the exclusion proof.
- New app startup intent remains pending while ownership is unknown, recovery is active, or a legacy marker has not been reconciled. Fixed/Curve startup cannot race recovery.

## Crash And Restart Reconciliation

| Crash point | Required restart behavior |
| --- | --- |
| CRASH-01 — Before journal synchronization | No mutation was allowed; remain/read as idle and validate fresh before accepting control |
| CRASH-02 — After `prepared`, before the first write | Treat every expected ID as potentially affected and run verified restoration |
| CRASH-03 — During a fan write or before the helper receipt | Include the currently failing fan and all expected IDs in restoration |
| CRASH-04 — After some writes, before post-write confirmation | Restore the complete expected set; never infer state from `appliedFanIDs` alone |
| CRASH-05 — After hardware apply confirmation, before lease save/journal active | Journal remains authoritative; restore unless durable agent/manual ownership can be reconciled exactly |
| CRASH-06 — During active manual or agent ownership | Recover from the durable expected set; an expired lease remains visible until restore completes |
| CRASH-07 — During restoration | Keep `restoring`/`restorePending`; retry the complete expected set |
| CRASH-08 — After hardware restoration confirmation, before lease clear | Reconfirm if necessary, clear the lease, then continue cleanup; do not start new control |
| CRASH-09 — After lease clear, before journal clear | Treat the journal as recovery evidence, freshly reconfirm OS ownership, then clear it |
| CRASH-10 — After journal clear, before legacy marker clear | Marker remains a conservative blocker until daemon status and fresh telemetry reconfirm OS ownership |
| CRASH-11 — Corrupt or newer-schema journal | Enter `unknownRecovery`; do not overwrite it or automatically write fans without a reconstructable durable expected set |
| CRASH-12 — After maintenance token issue | Restart/generation change invalidates the token; privileged teardown requires a new quiesce and confirmation |

## Persistence And Downgrade Rules

- The journal uses an explicit tagged, versioned JSON representation; synthesized associated-value `Codable` output is not the disk contract.
- Unknown future schema versions are preserved and fail closed.
- The root store rejects unsafe ownership, non-regular files, symlink traversal, and unsafe replacement paths; it uses same-directory atomic replacement plus file and directory synchronization.
- A v2 lease without a journal synthesizes recovery from the lease target IDs. A journal without a lease remains recovery evidence.
- A protocol-v1 daemon cannot be bootstrapped while a v2 journal or lease exists. Downgrade requires confirmed OS ownership and durable v2-state clearance first.
- App and helper are upgraded or downgraded as a compatible pair; the new client never controls through an old daemon.

## Readiness Contract

Readiness is derived from daemon ownership plus fresh trusted telemetry. `safeToRequestCooling` is false when any of the following is true:

- owner is manual, agent, recovery, mixed, or unknown;
- journal/lease/marker reconciliation is pending;
- expected IDs are missing from the fresh snapshot;
- an idle/macOS owner conflicts with a Forced or Unknown fan mode;
- telemetry is not eligible for the requested operation;
- daemon protocol/runtime parity is unavailable;
- existing hardware, sensor, thermal, policy, or helper gates fail.

The local marker is legacy caution evidence, not the primary ownership authority. A successful RPC without confirmed daemon OS ownership cannot clear it.

## Automated Proof Boundary

Task implementation uses fake SMC, fake persistence, fake XPC, fake process execution, and deterministic clocks. Automated gates may build the app bundle but must not launch it. They may not run `ViftyHelper setFixed`, `ViftyHelper auto`, `viftyctl restore-auto`, `viftyctl prepare/run`, helper repair/install, `sudo`, `launchctl`, or raw AppleSMC writes.

Exact signed-candidate hardware proof is a later sequence of separately supervised Fixed-to-Auto, Curve-to-Auto, and agent-smoke evidence. Passing source tests or artifact verification does not satisfy those claims.

## Scope Inventory

`WholeAppReviewFindingInventoryTests` is the executable scope ledger. It requires every row in the implementation plan's Finding Coverage Matrix to have exactly one inventory record, at least one owning task, and at least one behavioral or contract test-suite owner. Adding, removing, renaming, or reassigning a finding therefore requires an explicit inventory update.
