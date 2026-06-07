# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

Vifty uses a privileged XPC helper (LaunchDaemon) to write fan SMC keys as root, and a local `viftyctl` CLI for agent-controlled cooling leases. We take safety and security seriously.

**Please do not open a public issue for security vulnerabilities.**

Instead, report vulnerabilities privately via GitHub Security Advisories:

1. Go to **Security → Advisories → Report a vulnerability** on this repository.
2. Describe the issue, affected components, and reproduction steps.
3. We aim to acknowledge within 48 hours and publish a fix within 90 days.

## Security Model

Vifty's trust boundaries:

| Boundary | Description |
|---|---|
| **App ↔ Daemon (XPC)** | The unprivileged SwiftUI app communicates with the root daemon via XPC. The daemon validates and clamps all fan RPM targets before writing. |
| **Agent CLI ↔ Daemon (XPC)** | `viftyctl` sends bounded workload cooling leases through the daemon. Every lease carries a mandatory duration, reason, and idempotency key. The daemon enforces expiry independently. |
| **Daemon ↔ SMC (IOKit)** | Only the root daemon writes SMC keys. The app never attempts direct AppleSMC writes (fail-closed). |
| **Local filesystem** | Curve profiles and manual-control markers are stored in `~/Library/Application Support/Vifty/` with restricted permissions. No data leaves the device. |
| **Agent lease safety** | User Auto-restore always wins over an active agent lease. Sensor loss, unsupported hardware, helper uncertainty, or critical thermal pressure refuses or restores control. |

## Scope

In-scope for security reports:
- Privilege escalation via the XPC interface
- Daemon bypass allowing unprivileged SMC writes
- Agent lease escape (cooling applied without bounded duration or beyond expiry)
- Unsafe RPM targets reaching SMC writes
- Information disclosure from local storage

Out of scope:
- Denial-of-service via excessive lease requests (rate-limiting is on the roadmap, not yet implemented)
- Physical access attacks
- Issues in dependencies (report upstream)
- Social engineering

## Responsible Disclosure

We follow coordinated disclosure. Once a fix is released, we will:
1. Publish a GitHub Security Advisory with CVE if appropriate.
2. Credit the reporter (unless anonymity is requested).
3. Document the fix in the release notes.
