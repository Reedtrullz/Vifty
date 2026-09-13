# Vifty recovery root-cause review — 2026-09-12

## Result

The repository is not at a “run the installer again” point. The current source tree has a plausible repair for the SMC write failure and passes the full local gate, but the machine is still blocked by an old locked install, stale macOS service-registration state, and the absence of a runtime proof that the current source controls the fans.

The failed recovery attempt exposed one concrete orchestration bug:

- `/Users/reidar/Applications/Vifty Recovery 14/Vifty.app` was supplied as the lifecycle `--app` so its signed helper/service-management tools could be used.
- The root-owned replacement ledger is bound to `/Applications/Vifty.app`.
- `release_prior_replacement_lock_after_quiesce` intentionally requires the ledger’s `replacementAppPath` to equal `APP_PATH` before unlocking anything.
- Therefore the helper was removed successfully, but the `/Applications/Vifty.app` tree was correctly left untouched and still has `schg` flags.

That is a path-binding mistake in the recovery invocation, not evidence that the immutable replacement guard should be weakened.
## Verified state

| Area | Evidence | Meaning |
| --- | --- | --- |
| Source | Branch `codex/lean-polish`, HEAD `e79bcab20ad7c9eda302fe4594bfa547b15f929a`, 29 dirty paths, 592 additions, 638 deletions | The worktree is user-owned WIP and must not be reset, cleaned, stashed, or overwritten. |
| Source gate | Hermetic `make verify-full` passed under `umask 022`; 2,037 XCTest cases passed; `git diff --check` passed | Structural and regression confidence is good. This is not live hardware evidence. |
| SMC writer | `LocalFanHelperClient` now confirms mode readback, retries a guarded `Ftst` unlock when the write is ignored, confirms exact target and `Ftst=0`, and restores Auto on failure | The intended Fixed/Curve repair is present in the dirty tree. The physical cause remains unconfirmed. |
| Installed app | `/Applications/Vifty.app` is an ad-hoc v1.4.5 build 13 with `schg` on the bundle and binaries | It is not the current repaired runtime and cannot be replaced by the public installer’s fail-closed rules. |
| Helper service | The helper/daemon registration is absent after the safe uninstall path; `launchctl` reports no active Vifty service | Fan writes cannot work through the daemon at present. |
| Recovery app | `~/Applications/Vifty Recovery 14/Vifty.app` is Developer ID signed, build 14, TeamID `X88J3853S2`, and contains the pinned recovery helper | It is a valid control/recovery source, not the `/Applications` replacement target. |
| Replacement evidence | Root-owned replacement ledger and transaction directory remain preserved and protected | The failed attempt did not destroy recovery evidence or silently unlock the old tree. |
| BTM/LaunchServices | Duplicate/stale records exist; the Recovery 14 record is enabled and a previous launch attempt ended with `OS_REASON_CODESIGNING`, `LWCR update`, and exit 78 | macOS registration state is an independent blocker. Do not repair it with `sfltool resetbtm`. |
| Public archive | `.build/vifty-recovery/Vifty-v1.4.5.zip` has the expected pinned SHA and passed public release verification | It predates the dirty-tree SMC hardening and cannot prove the current Fixed/Curve repair. |
| Diagnostics | `viftyctl diagnose` exits 75 with blocked state, no daemon control path, and a stale manual marker | This is a safe block. It is not proof that the fans are manually controlled. |
| Credentials | 1Password CLI sign-in was already verified without reading a secret | No further 1Password action is needed for this recovery. macOS administrator authorization still requires the user to be present. |

The machine has approximately 40 GiB free on `/System/Volumes/Data`, so the disk guard is currently green for a bounded build. No long build or privileged retry should be started while the owner is AFK.

## Causal separation

There are three independent failures, and they must not be collapsed into one diagnosis:

1. The old `/Applications` bundle was left behind by a prior local/ad-hoc replacement and protected by `schg` flags.
2. The recovery execution selected a signed source app as the lifecycle target, so the existing `/Applications` replacement ledger did not match and was deliberately not unlocked.
3. Even after the install path is repaired, Fixed/Curve acceptance still requires the current dirty source to be built, registered with a matching daemon, and tested against live SMC readback.

The stale BTM/LWCR state can prevent step 3 even after steps 1 and 2 succeed. It is an environmental registration state, not a reason to change fan-control code.

## Decisions

- Add one narrowly scoped lifecycle distinction: keep `--app` as the canonical target bundle, and add an explicit signed `--control-app` source for an uninstall-only recovery operation. Normal repair, install replacement phases, and app UI behavior remain unchanged.
- Require the control app to be a complete Vifty bundle with the expected component identifiers, Developer ID TeamID `X88J3853S2`, and the pinned Auto-only recovery-helper SHA. Never accept an arbitrary ad-hoc recovery source.
- Use the existing root worker, receipts, Auto proof, immutable ledger validation, and durable transaction cleanup. Do not add a second root worker or a raw `chflags`/`mv` escape hatch.
- After the old target is safely unlocked, quarantine it reversibly before building the current source. Do not delete it.
- Build the current dirty source locally with the available Developer ID identity and TeamID, install it only after the target path is clear, then register the bundled daemon through the app’s existing `SMAppService` flow.
- Treat Fixed/Curve hardware smoke as the final acceptance gate. Tests, code signatures, `diagnose`, and BTM records are necessary preconditions, not substitutes for fan readback.

## Explicit non-claims

This review does not claim that the current source has already fixed the user’s Mac, that the public v1.4.5 archive contains the dirty-tree fix, that the stale manual marker reflects physical fan ownership, or that the current BTM registration is healthy. Those claims require the later runtime and hardware gates in the implementation plan.
