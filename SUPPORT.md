# Support

Vifty controls fans through a privileged local daemon, so support starts with
read-only evidence and conservative safety gates.

## Where To Ask

- **Security vulnerabilities:** do not open a public issue. Use GitHub
  Security Advisories and follow [SECURITY.md](SECURITY.md).
- **Release trust:** use the **Release Trust Report** issue template for
  source-first release warnings, unsigned-dev asset naming or checksum issues,
  Gatekeeper, Developer ID, notarization, Homebrew, TeamID, release-readiness,
  verifier, or reviewer problems. For source-first releases, remember that the
  optional unsigned `.app` zip is tester convenience only. The `v1.1.1`
  source-first hotfix supersedes the known `v1.1.0` helper-unreachable issue;
  keep both reports in the release-trust evidence lane, not as proof of trusted
  binary distribution.
- **Hardware validation:** use the **Hardware Validation Report** issue
  template and follow [docs/hardware-validation.md](docs/hardware-validation.md).
- **Agent/build/test cooling:** use the **Agent Cooling Report** issue template
  for `viftyctl prepare`, `viftyctl run`, `restore-auto`, guarded wrappers,
  rate limits, expired leases, restore failures, or child-command preflight
  issues.
- **General bugs or UI issues:** use the bug report template. Include screenshots
  only after collecting the safe diagnostics below when fan state is involved.
- **Questions and design discussion:** use GitHub Discussions when no bug,
  safety issue, or validation report is involved.

Maintainers triage reports with [docs/support-triage.md](docs/support-triage.md).

## Safe First Evidence

Start with these read-only commands when Vifty is installed:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
/Applications/Vifty.app/Contents/MacOS/viftyctl capabilities --json
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json
/Applications/Vifty.app/Contents/MacOS/viftyctl audit --limit 20 --json
```

If the report is about fan telemetry on a supported Apple Silicon MacBook Pro,
maintainers may also ask for:

```sh
sudo /Applications/Vifty.app/Contents/MacOS/ViftyHelper probeLocal
```

Do not attach evidence publicly until you have checked for private data. The
validation collector writes `privacy-review.tsv`; a nonzero privacy row means
the bundle may contain a hostname, `/Users/...` path, serial-number label, or
hardware UUID label that should be redacted or shared privately.

## Safety Rules

- Do not run `sudo ViftyHelper setFixed`, raw SMC tools, or manual fan-write
  smoke tests when `diagnose --json` reports `state: "blocked"` or
  `safeToRequestCooling: false` or `daemonControlPathReady: false`.
- Do not retry `viftyctl prepare` or `viftyctl run` while readiness is blocked,
  thermal pressure is critical, sensors are missing, no controllable fans are
  present, fan IDs or RPM ranges are invalid, or Auto restore is pending.
- Unsupported Macs should remain under macOS automatic fan control. Follow
  [docs/unsupported-hardware.md](docs/unsupported-hardware.md) and collect
  read-only evidence only.
- Prefer [docs/safe-agent-cooling.md](docs/safe-agent-cooling.md) and the
  guarded wrappers in [examples/viftyctl](examples/viftyctl/README.md) for local
  build/test/agent workloads.

When in doubt, stop at read-only diagnostics and ask before running any command
that changes fan state.
