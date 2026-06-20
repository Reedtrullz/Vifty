# Validation Reports

This directory stores reviewed validation summaries, not raw evidence bundles.

Raw bundles from `scripts/collect-validation-evidence.sh` can contain many
captured command outputs, so keep them in `.build/` or attach them to a
Hardware Validation Report only after checking `privacy-review.tsv`. Commit the
reviewed `review-result.json` summary only when it is safe to publish and useful
for the compatibility index.

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
Source-first, unsigned-dev, and local ad-hoc reports are compatibility evidence
only; they are not Developer ID, notarization, Homebrew, or trusted binary
evidence.
