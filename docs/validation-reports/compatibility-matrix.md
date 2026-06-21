# Vifty Compatibility Matrix Draft

Generated from reviewed validation report summaries. Treat source-first and unsigned-dev reports as compatibility evidence only; they are not Developer ID, notarization, Homebrew, or trusted binary evidence.

| Model family | Public status | Validated reports | Candidate reports | Agent run smoke reports | Safe-block reports | Rejected reports | Model identifiers | Install sources | Readiness | Evidence |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |
| MacBookPro18 | Needs manual smoke | 0 | 4 | 1 | 0 | 3 | MacBookPro18,1 | local-ad-hoc-build | safeToRequestCooling=false, true<br>daemonControlPathReady=true<br>manualControlActive=true, unknown<br>agentAction=requestCooling, requestCoolingWithCaution, restoreAutoBeforeRequestingCooling<br>recoveryAction=none, restoreAutoBeforeRetry<br>failedCheckIDs=manualControlClear<br>coolingBlockerIDs=manualControlClear | source: main@24154ae, main@30035f8, main@3e7970b, main@8cbabb9, main@aec12c6, main@afa7929, main@b757c4b<br>reviewed: 2026-06-15, 2026-06-16, 2026-06-17, 2026-06-18, 2026-06-20, 2026-06-21<br>manual: not recorded<br>agent-run: 2026-06-18-macbookpro18-main-agent-run-smoke/agent-run-smoke-evidence-summary.json |
