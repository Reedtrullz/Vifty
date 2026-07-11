# Competitive Analysis and Product Direction

Vifty's product thesis is narrow on purpose: Vifty should be the open-source, auditable thermal-control layer for Apple Silicon MacBook Pro developer workloads.

Do not compete as a general-purpose system monitor yet. Macs already have mature tools for broad sensor dashboards, polished menu-bar telemetry, battery management, and consumer fan control. Vifty earns its place by making privileged fan control inspectable, local, fail-closed, and useful for builds, tests, and local coding agents.

## Comparison Set

Plain-name comparison set: Macs Fan Control, TG Pro, iStat Menus, Stats, Hot and MacThrottle, Sensei, AlDente and coconutBattery.

- [Macs Fan Control](https://crystalidea.com/macs-fan-control) is the simple default many users know for fan RPM and temperature-sensor-linked control.
- [TG Pro](https://www.tunabellysoftware.com/tgpro/) is a mature commercial thermal utility with broad UX, notifications, diagnostics, and support expectations.
- [iStat Menus](https://bjango.com/mac/istatmenus/) is the polished general menu-bar monitor, including fan controls as one part of a much larger system-monitoring suite.
- [Stats](https://github.com/exelban/stats) is the major open-source menu-bar monitor, but Vifty should own the safer fan-control and agent-workload lane rather than clone every Stats widget.
- [Hot](https://github.com/macmade/Hot) and [MacThrottle](https://github.com/angristan/MacThrottle) are thermal-throttling visibility tools, useful comparison points for observability but not direct fan-control workflow owners.
- [Sensei](https://cindori.com/sensei) competes on broader Mac maintenance and performance polish.
- [AlDente](https://apphousekitchen.com/aldente-overview/) and [coconutBattery](https://coconut-flavour.com/) are battery-specialist comparison points; Vifty's power telemetry should support thermal decisions, not become a full charge-management product.

## What Vifty Should Own

- Auditable SMC write boundaries: allowlisted fan mode and target keys, RPM clamping, daemon-first writes, and fail-closed behavior when the helper, hardware shape, or telemetry is uncertain.
- Developer workload cooling: `viftyctl diagnose --json`, bounded leases, guarded `run`, explicit restore behavior, and local audit evidence that agents can consume without parsing UI copy.
- Evidence-gated release trust: source-first and unsigned-dev builds stay explicitly limited, while Developer ID candidates remain untrusted until the exact public artifact, checksum, notarization, Gatekeeper, and Homebrew checks pass.
- Report-backed compatibility: generated validation indexes and compatibility tables, not handwritten support claims.
- Helper repair clarity: every blocked write path should tell the user the next safe action and explain why fan writes remain blocked.
- Subtle in-memory trend sparklines are in scope when they help users judge build, test, or agent workload impact; full historical monitoring, cloud sync, analytics, and persistent telemetry remain out of scope without a separate privacy plan.

## What Vifty Should Avoid For Now

- A broad iStat-style dashboard that dilutes the fan-control trust story.
- Battery charge limiting, battery aging policy, cloud sync, analytics, full historical monitoring, or persistent telemetry without a separate privacy plan.
- Raw agent SMC writes, arbitrary fan-key access, or automation that prepares cooling before validating the child command.
- Public binary trust claims before Developer ID signing, notarization, stapling, checksum verification, and Homebrew alignment pass.

## Near-Term Roadmap

Priority order: trusted release story, hardware validation evidence, daemon safety, helper repair clarity, human UI polish, local observability, and developer/agent workflow proof.

The concrete execution plan for the next cycle is [plans/2026-06-13-next-workplan.md](plans/2026-06-13-next-workplan.md). It starts with M1 Pro validation on available hardware, keeps untested model families as "Needs report," and sequences UI/helper/menu-bar/observability work before future trusted-binary updater work.

1. **Trusted release story:** publish `v1.2.0` only through the strict Developer ID workflow, preserve the historical `v1.1.1` source-first boundary, and keep Homebrew blocked until the public checksum and verifier pass.
2. **Hardware validation evidence:** publish only generated compatibility evidence from reviewed reports; keep unvalidated rows as "Needs report."
3. **Helper repair clarity:** keep first-run, approval, unreachable, telemetry-only, repair, unsupported, and healthy states distinct in the app and support docs.
4. **Human UI polish:** prioritize small-window scrolling, full-height operational panes, main-window settings, a compact/readiness-oriented menu-bar popover, compact power/history/temperature surfaces, and a better screenshot/demo.
5. **Local observability:** keep optional local notifications for helper failure, sustained high thermal pressure, Auto restore failure, plugged-in battery drain, and agent cooling that needs attention; defaults should remain conservative and local-only.
6. **Trusted updater:** add Sparkle auto-update only in the future trusted binary lane, after Developer ID signing, notarization, EdDSA appcast signing, and canonical artifact verification exist.
7. **Developer and agent workflow:** make Swift, Xcode, npm, pnpm, Bun, Go, cargo, uv, pytest, local-model, and custom guarded-run examples easy to find; defer MCP and Shortcuts until real users prove the CLI contract.

## Interface Boundaries

- No breaking changes to existing `viftyctl` JSON fields.
- Menu-bar and notification preferences must be additive and local.
- Compatibility docs may add generated report views, but support claims must remain tied to reviewed evidence.
- Trusted releases must keep strict Developer ID, notarization, stapling, TeamID, checksum, verifier, and Homebrew checks.
