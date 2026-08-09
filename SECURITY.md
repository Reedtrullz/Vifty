# Security Policy

<!-- BEGIN GENERATED RELEASE FACTS -->
> Release facts authority: `.github/release-manifest.json` (schema `docs/schemas/release-manifest.schema.json`).
> Published: `v1.4.5` (version `1.4.5`, build `13`), `arm64` only, minimum macOS `15.0`.
> Runtime identities: app `tech.reidar.vifty`, daemon `tech.reidar.vifty.daemon`, helper `tech.reidar.vifty.helper`, CLI `tech.reidar.vifty.ctl`.
> Canonical artifact: `Vifty-v1.4.5.zip` with checksum asset `Vifty-v1.4.5.zip.sha256` and SHA-256 `13fa763cbfdca3e77fcf6f657df6d51b32e19a4d25dd17a79614635fe844b0d5`.
> Public artifact trust: `passed` / `developer-id-notarized` for TeamID `X88J3853S2`; source `174dcd28a343de7f797d682d02c0f70e26b72c2e`, CI run `31283125895`, Release run `31284620552`.
> Tag policy: `v1.4.5` remains recorded as `signed-verified` evidence; signed tags are mandatory from version `1.3.3` onward.
> Separate exact-build claims: installed release review `pending`; manual Fixed/Curve/Auto compatibility `pending`.
<!-- END GENERATED RELEASE FACTS -->

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 1.4.5 | Supported Developer ID signed/notarized release; installed release review and manual Fixed/Curve/Auto validation pending |
| 1.4.4 | Historical Developer ID signed/notarized release; migration to it from v1.3.2 is blocked on macOS 26 |
| 1.3.2 | Historical Developer ID signed/notarized release; installed release review passed and manual Fixed/Curve/Auto validation passed on MacBookPro18,1 |
| 1.1.x source/tag | Supported source-first fallback; unsigned assets are not trust-complete |
| 1.0.x public asset | Not trust-complete; use source or a corrected 1.1.x release path |

## Reporting a Vulnerability

Vifty uses a privileged XPC helper (LaunchDaemon) to write fan SMC keys as root, and a local `viftyctl` CLI for agent-controlled cooling leases. We take safety and security seriously.

**Please do not open a public issue for security vulnerabilities.**

Instead, report vulnerabilities privately via GitHub Security Advisories:

1. Go to **Security → Advisories → Report a vulnerability** on this repository.
2. Describe the issue, affected components, and reproduction steps.
3. We aim to acknowledge within 48 hours and publish a fix within 90 days.

## Security Model

For the detailed privileged-helper, SMC write, release-signing, and agent-control trust boundaries, see [docs/trust-model.md](docs/trust-model.md).

For the current public binary trust state, see [docs/release-status.md](docs/release-status.md). A source tag, CI artifact, or ad-hoc local build is not a substitute for a Developer ID signed, notarized, stapled release artifact with a verified cask checksum.

Vifty's trust boundaries:

| Boundary | Description |
|---|---|
| **App ↔ Daemon (XPC)** | The unprivileged SwiftUI app communicates with the root daemon via XPC. The daemon validates client signing identifiers, optionally requires a release TeamID, clamps all fan RPM targets, and the SMC client only permits Vifty's fan-control write keys. |
| **Agent CLI ↔ Daemon (XPC)** | `viftyctl` sends bounded workload cooling leases through the daemon. Every lease carries a mandatory duration, reason, and idempotency key; the default policy caps leases at 30 minutes. The daemon enforces expiry independently. |
| **Daemon/helper ↔ SMC (IOKit)** | The root daemon owns normal fan writes. The guarded local helper may write only for a privileged/root caller on explicit recovery/probe paths. Both routes clamp targets and share the same fan-mode, fan-target, and guarded force-test allowlist; the unprivileged app never attempts direct AppleSMC writes. |
| **Local filesystem** | Curve profiles, manual-control markers, and agent-control lease/audit files are stored locally with restricted permissions. No data leaves the device. |
| **Agent lease safety** | User Auto-restore always wins over active and in-flight agent cooling. Sensor loss, unsupported hardware, helper uncertainty, or critical thermal pressure refuses or restores control. |

## Scope

In-scope for security reports:
- Privilege escalation via the XPC interface
- Daemon bypass allowing unprivileged SMC writes
- Agent lease escape (cooling applied without bounded duration or beyond expiry)
- Unsafe RPM targets reaching SMC writes
- Information disclosure from local storage

Out of scope:
- Denial-of-service via excessive local lease requests beyond the built-in prepare cooldown/rate limit
- Physical access attacks
- Issues in dependencies (report upstream)
- Social engineering

## Responsible Disclosure

We follow coordinated disclosure. Once a fix is released, we will:
1. Publish a GitHub Security Advisory with CVE if appropriate.
2. Credit the reporter (unless anonymity is requested).
3. Document the fix in the release notes.
