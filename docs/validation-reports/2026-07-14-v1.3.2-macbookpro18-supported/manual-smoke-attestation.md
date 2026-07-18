# Vifty v1.3.2 supervised hardware smoke attestation

- Date: 2026-07-14 (Europe/Oslo)
- Result: `passed-auto-restored`
- Operator boundary: the repository owner was physically present at the Mac and performed every Auto, Fixed RPM, and Temperature Curve UI action. Codex collected read-only daemon diagnostics, local helper probes, hashes, and video frames; it did not automate UI interaction or issue raw SMC writes.
- Exact app: public Vifty `v1.3.2`, version `1.3.2`, build `7`, Developer ID Team ID `X88J3853S2`.
- Public artifact: `Vifty-v1.3.2.zip`, SHA-256 `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`.
- Source identity: tag `v1.3.2`, peeled commit `6a771c2ea10386bf7a0a8369a759930f01d56062`.
- Hardware: `MacBookPro18,1`, Apple Silicon MacBook Pro, two controllable fans, six temperature sensors.
- Operating system: macOS `26.5.2`, build `25F84`.

## Supervised sequence

1. Baseline Auto settled with both fans at hardware mode `Auto`, raw mode `0`, and the manual-control marker clear.
2. Fixed RPM was applied at 2,800 RPM to both fans. The recording initially shows the run as `Until changed`; the operator then changed it to a 10-minute bounded run before the recording ended. Daemon diagnostics and a direct helper probe both observed `Forced`/raw `1`, target 2,800 RPM, in-range current speeds, and nominal thermal pressure.
3. Auto was selected once. The UI briefly showed the observed transition boundary while hardware still reported Forced; by 5-10 seconds both the UI and hardware had settled to macOS Auto. Read-only daemon and helper evidence then showed both fans `Auto`/raw `0`, the manual marker clear, and no later reassertion.
4. A three-point curve was applied without saving or overwriting the restored `Quiet` profile: 55 C / 1,800 RPM, 70 C / 3,000 RPM, 85 C / 4,200 RPM, per-fan overrides off, 10-minute bounded run. One late video frame briefly shows different per-fan displayed targets, which is treated as a polling/display observation rather than authoritative simultaneous hardware state. The later daemon snapshot observed equal 2,928 RPM targets and the later helper probe observed equal 2,963 RPM targets as temperature changed; both fans were `Forced`/raw `1`, tracked those readback targets, remained within hardware ranges, and thermal pressure stayed nominal. This attestation does not claim perfectly synchronized per-fan UI target rendering.
5. Auto was selected once. The recording shows Curve active at 1 second, the observed Forced-to-Auto settling state at 5 seconds, stable Auto ownership by 10 seconds, and stable Auto again at 19 seconds. Later daemon diagnostics and a direct helper probe independently confirmed both fans `Auto`/raw `0`, normal macOS targets (1,522 and 1,643 RPM), the manual marker clear, no failed checks, no cooling blockers, and nominal thermal pressure.

## Evidence bindings

- Fixed UI recording SHA-256: `204122c2fbb16963672685beb828ba53ea5456a16fd166b51922ee4ff0bb727c` (27.288333 s).
- Fixed-to-Auto recording SHA-256: `128601f61f6c07ce687bbcc99fab6a28d1268312e7dec4e3b52323296b8e62d5` (10.2 s).
- Curve UI recording SHA-256: `4c344923ebd1ffd0aed8a7cc52b2ae9a72127f34e427cdb496b9426012748978` (48.861667 s).
- Curve-to-Auto recording SHA-256: `ba52dbd824b45fd80463d31381d4d44ad5a8998c6887b7b3ffe55b583219aea3` (20.1 s).
- Installed/public bundle parity: all 54 regular files and all symlink targets matched the downloaded public artifact; app CDHash matched `666e4972fcb31fa3fcb3134c956daae0bdf62189`.
- Bundled and installed daemon SHA-256 both matched `7543c573528a57bb096b045b9a7476b1d4da4aef88b7cd8b54d4cd2ca5bf7dac`.
- Formal release review: `passed`, read-only collection, no cooling commands, no failures or warnings.
- Formal supported-hardware review: `passed`, `manualSmokeTestResult=passed-auto-restored`, no failures or warnings.

The recordings remain in the local checksummed operator bundle rather than the Git repository. Their hashes bind this attestation to those exact files. The checked-in [smoke summary](smoke-summary.json) preserves the machine-readable sequence and claim boundary.

## Claim boundary

This validates manual Fixed RPM, Temperature Curve, and explicit Auto restoration only for the exact public Vifty v1.3.2 build 7 binary on model identifier MacBookPro18,1. It does not validate the current remediation branch, other Vifty versions, other Mac models, broad Apple Silicon compatibility, agent-run cooling, or automatic updates.
