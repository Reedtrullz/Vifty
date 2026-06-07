# Changelog

All notable changes to Vifty will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-07

### Added
- Menu bar cockpit with live fan RPM, temperatures, and power state
- Three fan control modes: Auto, Fixed RPM, and Temperature Curve
- Saveable, nameable curve profiles with backup and overwrite protection
- Live power tracking: adapter wattage, USB-C PD profiles, battery health, charge/drain watts
- `viftyctl` agent CLI with `status`, `capabilities`, `prepare`, `restore-auto`, and `run` commands
- Agent control: bounded-duration workload cooling leases with idempotency keys
- Daemon-owned lease monitoring and expiry (safety fallback)
- Privileged XPC helper (LaunchDaemon) for fail-closed SMC fan writes
- ViftyHelper debug CLI for direct SMC probing and emergency fan restoration
- Thermal-pressure state monitoring alongside raw temperatures
- In-memory rolling telemetry history
- Unclean-exit recovery (manual-control marker + Auto-restore on next launch)
- Timed manual modes (auto-restore after selected duration)
- Double-click installer (`Install Vifty.command`) and `make install` workflow
- Unsigned `.pkg` builder for reusable local installs
- Homebrew cask distribution
- 127 XCTest cases covering fan control, curves, XPC, power, and agent control
- GitHub Actions CI: Swift tests, release build, plist/code-sign checks
- SECURITY.md with vulnerability reporting and trust boundaries
- CONTRIBUTING.md with setup, architecture rules, and PR process
- CODEOWNERS for security-sensitive paths

### Security
- RPM clamping on all fan write paths
- Daemon-first architecture: unprivileged direct SMC writes refused (fail-closed)
- Sensor loss triggers Auto-restore
- Unsupported hardware refuses manual fan control
- Critical thermal pressure refuses or restores control
- User Auto always wins over active agent lease
