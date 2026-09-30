# Vifty operational scripts

These are consequential lifecycle/release tools. `Makefile` is the command index; `.github/release-manifest.json` is recorded release identity. Read the root safety rules and `docs/release.md` before invoking a workflow.

`install-vifty.sh`, `repair-vifty-helper.sh`, `uninstall-vifty.sh` and helper-lifecycle scripts can change installed privileged state. Release and tag scripts can contact GitHub or publish. `collect-agent-run-smoke-evidence.sh` can request a cooling lease; it is different from read-only readiness/evidence collectors. Documentation discovery should inspect source, not execute these scripts.

Keep public-artifact trust, source CI, installed-helper parity and human hardware acceptance separate. Generated release-facts blocks are produced by `render-release-facts.sh`; do not hand-edit their values to make them look current.
