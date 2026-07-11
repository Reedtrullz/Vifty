# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 1.2.0 candidate | Supported source; public binary trust pending exact-artifact release verification |
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
| **Daemon ↔ SMC (IOKit)** | Only the root daemon writes SMC keys, and low-level writes are allowlisted to fan mode, fan target, and guarded force-test keys. The app never attempts direct AppleSMC writes (fail-closed). |
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
