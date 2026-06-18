# Vifty Compatibility Matrix Draft

Generated from reviewed validation report summaries. Treat source-first and unsigned-dev reports as compatibility evidence only; they are not Developer ID, notarization, Homebrew, or trusted binary evidence.

| Model family | Public status | Validated reports | Candidate reports | Agent run smoke reports | Safe-block reports | Rejected reports | Model identifiers | Install sources | Readiness | Evidence |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| MacBookPro18 | Needs manual smoke | 0 | 4 | 1 | 0 | 0 | MacBookPro18,1 | local-ad-hoc-build | safeToRequestCooling=true<br>daemonControlPathReady=true<br>manualControlActive=unknown<br>agentAction=requestCooling, requestCoolingWithCaution<br>recoveryAction=none | source: main@24154ae, main@30035f8, main@8cbabb9, main@b757c4b<br>reviewed: 2026-06-15, 2026-06-16, 2026-06-17, 2026-06-18<br>manual: not recorded<br>agent-run: 2026-06-18-macbookpro18-main-agent-run-smoke/agent-run-smoke-evidence-summary.json |
