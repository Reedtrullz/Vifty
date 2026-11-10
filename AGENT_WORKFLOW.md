# Agent Engineering Workflow

> This file is the repository-specific contract for agent-assisted planning and implementation. Keep it aligned with the actual GitHub Project configuration.

## System

- **Product/system:** `Vifty`
- **GitHub Project:** `Vifty — Engineering Roadmap`
- **Project URL:** `https://github.com/users/Reedtrullz/projects/18`
- **Repositories covered:**
  - `Reedtrullz/Vifty`

## Sources of truth

- Repository: implementation reality
- GitHub Issue: canonical work item/problem statement
- Pull request: canonical implementation/change review
- GitHub Project: planning/execution state

Project draft items are not substitutes for real Issues when implementation work is concrete enough to ticket.

## Lifecycle

`Intake → Ready → In Progress → Blocked → In Review → Done`

Audit agents create/reuse Issues and place new findings in **Intake**. They do not mark their own findings Ready by default.

## Ready definition

A ticket is Ready only when:

- evidence is adequate, or the ticket is explicitly a bounded Research/Investigation task
- it is not a duplicate
- repository ownership is correct
- scope is coherent and bounded
- acceptance criteria are present
- blockers/dependencies are represented
- Priority, Phase, Effort, Confidence, Category, and Area are set where applicable

## Done definition

A ticket is Done only when the intended outcome is complete, required verification passes, and linked implementation is merged/closed as appropriate.

Duplicate/not-planned/obsolete work should be closed with the correct GitHub reason instead of being mislabeled Done.

## Project fields

- **Status:** Intake / Ready / In Progress / Blocked / In Review / Done
- **Priority:** P0 / P1 / P2 / P3
- **Phase:** Immediate / Foundation / Near-term / Medium-term / Advanced / Stretch
- **Effort:** XS / S / M / L / XL
- **Confidence:** Confirmed / Strong evidence / Needs validation
- **Category:** repository/project taxonomy (do not create a custom Project field named `Type`; preserve native Issue Type if the repo uses it)
- **Area:** real subsystem ownership
- **Iteration:** execution-selected work only

Do not invent dates or precise hour estimates solely to populate fields.

## Durable labels

Prefer existing repository labels. Standard workflow labels, when configured:

- `agent-found`
- `needs-validation`
- `roadmap`
- `epic`

Do not duplicate mutable Project fields as labels.

## Agent-created ticket provenance

Agent-created audit tickets should include a hidden marker similar to:

`<!-- agent-audit:v3 repo=Reedtrullz/Vifty head=<CURRENT_SHA> baseline=<BASELINE_SHA> fingerprint=<STABLE_FINGERPRINT> content_sha256=<CURRENT_CONTENT_HASH> skill=github-agent-engineering mode=<audit|targeted-audit|reconciled> -->`

The visible ticket should also state the revalidated current commit/date where that materially affects the finding, and may record the original evidence baseline separately. Old proposal documents must be revalidated against current canonical HEAD/merged PRs before creating new open Issues.

The stable fingerprint should be deterministic enough to help repeated audits recognize the same finding. Prefer a SHA-256 over a normalized string such as:

`repository | primary subsystem/path | normalized finding slug`

Portable recipe:

```bash
printf '%s' "$NORMALIZED" | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])'
```

`content_sha256` should hash the current semantic title + body with all `agent-audit` markers removed and whitespace/newlines normalized. When reconciliation rewrites a ticket to residual scope, refresh `head`, `content_sha256`, and `mode=reconciled`; migrate stale v1/v2 markers when touching the body.

Do not treat the fingerprint as proof that two semantically different findings are identical; still perform normal deduplication.

## Issue structure

Implementation-useful Issues normally contain:

1. Summary
2. Current state / Evidence
3. Problem / Motivation
4. Proposed direction
5. Scope / Out of scope
6. Acceptance criteria
7. Dependencies / Related work
8. Provenance when agent-created

Facts, hypotheses, and stretch ideas must be clearly distinguished.

## Epics and dependencies

- Use parent/sub-issues for coherent outcomes with genuinely separable work.
- Use blocking/blocked-by relationships where supported.
- Keep implementation ownership in the repository that owns the code.
- For cross-repo initiatives, use a primary tracking Issue and separate child/related Issues only when independent changes are required.

## Audit agents

Audit agents:

- inspect broadly or by requested focus
- deduplicate against Issues and PRs
- create/reuse real Issues
- add them to Project as Intake
- set initial evidence-based metadata
- never implement findings during the audit
- perform a second pass for missed areas on broad audits

## Triage agents

Triage agents challenge Intake findings before execution. They may:

- move a well-supported ticket to Ready
- keep it in Intake
- convert/refine it into Research/Investigation
- close as duplicate/not planned/obsolete when justified
- split or consolidate scope
- set dependencies and parent/sub-issue relationships

They do not implement tickets while triaging.

## Implementation agents

Implementation agents work only on explicitly authorized **Ready**, unblocked work unless a user directly overrides this contract.

They:

- read the full Issue, parent, dependencies, and related PRs
- verify the ticket still matches current code before changing anything
- keep changes within scope
- add/update tests appropriate to the claim
- run relevant checks
- open/link a PR
- use closing keywords for every Issue the merge fully resolves; never for residual/partial scope
- move the work to In Review when appropriate
- after an authorized merge, verify fully resolved Issues are closed and their Project items are Done before reporting completion

If the Issue is materially wrong or obsolete, stop and update/report the ticket instead of forcing an implementation.

## Verification agents

Prefer a fresh agent/session for verification.

The verifier independently evaluates:

- linked Issue and acceptance criteria
- actual diff and affected code
- tests/checks
- regression risk
- scope drift
- whether the Issue itself was underspecified or wrong

Use one of these verdicts:

- `PASS`
- `NEEDS_FIX`
- `ISSUE_SCOPE_WRONG`

Verification should not silently rewrite the implementation before giving a verdict.

## Post-merge lifecycle closure

Completed work should not require a separate manual cleanup prompt. When an agent is present for an authorized merge, it must finish the lifecycle:

- fully resolved Issue → closed as completed
- Project item → Done
- partial Issue → remains open with truthful residual scope
- parent/dependency progress → refreshed when material
- final GitHub state → re-read and verified

Do not delete completed Issues. Preserve them as durable engineering history.

The Project should use native closed-Issue → Done automation when supported, and PRs should use GitHub closing keywords so later manual merges still close the correct Issues automatically.

## Reconciliation

After development waves, reconcile:

- duplicate Issues
- obsolete/stale findings
- merged PRs whose Issues/Project state did not update
- completed blockers
- parent/sub-issue progress
- tickets whose underlying code changed
- stale Intake/Ready work

Age alone is not a reason to close valid work.

## Security and side effects

- Respect current user authorization for GitHub writes and code changes.
- Never expose credentials/tokens in Issues, PRs, logs, or files.
- Do not weaken repository/organization security to make automation work.
- Preserve unrelated uncommitted work.

## Verified repository configuration

- **Category options:** Bug / Feature / UX / Accessibility / Architecture / Reliability / Performance / Security / Testing / Developer Experience / Infrastructure / Documentation / Research
- **Area options:** Telemetry and sensor identity / Fan ownership and safety / Agent CLI and leases / Native UI and profiles / Private storage and evidence / Packaging and release

Project fields, saved views and repository linkage were read back through ProjectV2 GraphQL on 2026-10-07. Native workflows are configured and verified separately; an enabled workflow flag alone does not establish its action target. Closure of an Issue as not planned must not assert completed implementation. Existing repository instructions, domain acceptance and release gates take precedence.
