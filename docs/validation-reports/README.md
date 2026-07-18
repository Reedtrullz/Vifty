# Validation Reports

This directory stores reviewed validation summaries, not raw evidence bundles.

Raw bundles from `scripts/collect-validation-evidence.sh` can contain many
captured command outputs, so keep them in `.build/` or attach them to a
Hardware Validation Report only after checking `privacy-review.tsv`. Commit the
reviewed `review-result.json` summary only when it is safe to publish and useful
for the compatibility index.

The current exact-binary validated report is
[`2026-07-14-v1.3.2-macbookpro18-supported`](2026-07-14-v1.3.2-macbookpro18-supported/).
Its review result, machine-readable smoke summary, and human-supervised
attestation scope Fixed → Auto → Curve → Auto proof to public Vifty v1.3.2
build 7 on `MacBookPro18,1`. The adjacent
[`2026-07-14-v1.3.2-macbookpro18-release`](2026-07-14-v1.3.2-macbookpro18-release/)
summary records the separate installed-release review.

Regenerate the checked-in index after adding or replacing report summaries:

```sh
scripts/summarize-validation-reports.sh \
  --input docs/validation-reports \
  --output-json docs/validation-reports/compatibility-index.json \
  --output-tsv docs/validation-reports/compatibility-index.tsv \
  --output-markdown docs/validation-reports/compatibility-matrix.md
```

Candidate supported-hardware rows remain **Needs manual smoke** until a
reviewed report records `manualSmokeTestResult: "passed-auto-restored"`.
Passed local-ad-hoc manual smoke summaries must also carry a
`manualSmokeReadinessSource` from the read-only manual-smoke preflight, proving
the installed daemon matched the expected build before the smoke result was
accepted.
Passed local-ad-hoc issue-template agent-run smoke summaries must carry either
an `agentRunSmokeReadinessSource` from the read-only agent-run preflight or an
`agentRunSmokeSource` pointing to a captured
`agent-run-smoke-evidence-summary.json` bundle, proving the helper/build
boundary was checked before accepting developer-workload proof.
Source-first, unsigned-dev, and local ad-hoc reports are compatibility evidence
only; they are not Developer ID, notarization, Homebrew, or trusted binary
evidence.
