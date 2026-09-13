# Vifty v1.4.8 supervised hardware smoke attestation

- Date: 2026-09-13 (Europe/Oslo)
- Result: `passed-auto-restored`
- Operator boundary: the user authorized the supervised run and the fan writes were issued only through the installed Vifty app UI. UI automation was used for the normal Auto, Fixed RPM, Temperature Curve, and Apply controls; Codex did not invoke raw SMC writes, `ViftyHelper setFixed`, `ViftyHelper auto`, or an unguarded agent cooling command. `viftyctl diagnose` and `ViftyHelper probeLocal` were read-only.
- Exact app: public Vifty `v1.4.8`, version `1.4.8`, build `16`, Developer ID Team ID `X88J3853S2`.
- Public artifact: `Vifty-v1.4.8.zip`, SHA-256 `7853ca7ad8ca51a35aa89f56f2779c3d2b528523b7e3198be7c550d208e16683`.
- Source identity: tag `v1.4.8`, peeled commit `65cc3862beee62dd7abf7a31847988bbec7e37e8`.
- Hardware: `MacBookPro18,1`, Apple Silicon MacBook Pro, two controllable fans, six temperature sensors.
- Operating system: macOS `27.0`, build `26A428`.

## Supervised sequence

1. Baseline Auto was settled before the manual run. The daemon and read-only local probe reported two controllable fans, valid `F0Md`/`F1Md` mode keys, macOS Auto ownership, nominal thermal pressure, and no manual-control marker or cooling blockers.
2. Fixed RPM was selected and applied at 2,800 RPM. The UI reported Vifty manual hardware control; read-only daemon samples reported Forced/raw `1` with targets at 2,800 RPM and current readings around 2,814/2,801 RPM, followed by additional in-range samples near the requested target.
3. Temperature Curve was selected with `CPU Efficiency Core 1` as the sensor and applied through the UI. At approximately 67 C, the UI and telemetry showed both fans under manual hardware control with a requested target around 3,216 RPM and current readings around 3,071/3,045 RPM. The target changed with the selected sensor temperature, demonstrating curve resolution and fan writes rather than a Fixed-mode hold.
4. Auto was selected and applied. The immediate restore transition reported the expected protected/System raw mode (`3`) before the later final readback settled to macOS Auto/raw `0`; the manual marker and ownership were clear, thermal pressure was nominal, and no fan-control blockers remained.

## Evidence bindings

- Installed app CDHash: `31f209f32afc0c834b14a80298fa0195fc2e8bc6`.
- Installed and expected daemon SHA-256: `4ad6417413e91f8fbc4155a7114f3a3a2c5d15aba4b0c0720a0455585ce51108`.
- Final read-only `viftyctl diagnose --json`: `state=ready`, `manualControlActive=false`, `safeToRequestCooling=true`, empty `failedCheckIDs` and `coolingBlockerIDs`, daemon path/hash match true.
- Final read-only helper probe: both fans Auto/raw `0`, current/target RPM 1,505/1,522 and 1,649/1,643, with valid ranges and restore eligibility.
- Formal release review: `passed`, read-only collection, no cooling commands, no failures or warnings.
- Formal supported-hardware review: `passed`, `manualSmokeTestResult=passed-auto-restored`, no failures or warnings.

The raw read-only evidence bundle remains in the local `.build/` workspace rather than the Git repository; its privacy review passed before the report was accepted.

## Claim boundary

This validates manual Fixed RPM, Temperature Curve, and explicit Auto restoration for the exact public Vifty v1.4.8 build 16 on model identifier `MacBookPro18,1`. It does not validate other Vifty versions, other Mac models, broad Apple Silicon compatibility, agent-run cooling, or automatic updates.
