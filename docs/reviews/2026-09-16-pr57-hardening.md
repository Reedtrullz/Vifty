# PR #57 review follow-up

Scope: fixes on top of `9f1aa8fc8db0951b2649c4d7d0abf064ce152b04`.
This is source/test evidence, not an installed-build or public-release claim.

## Changes

- Replacement unlocks retain depth-first traversal and error propagation, skip
  symlinks, use `chflags -h` as a no-follow guard, and remove only the selected
  lifecycle lock flag. They no longer clear every flag with `chflags 0`.
- The process runner delivers stdin nonblockingly under the same monotonic
  deadline as child execution. Partial writes are retained, interrupted or
  backpressured writes retry within that deadline, and per-descriptor SIGPIPE
  suppression turns a closed reader into an error routed through group cleanup.
- The compiled lifecycle digest was updated with the script.

## Regression evidence

The flag-boundary test failed before the fix: a symlink chain caused a sibling
sentinel's `uchg` flag to disappear. After the fix it preserves that flag, an
internal target's unrelated `hidden` flag, internal symlinks, and dangling links.
A separate real unreadable-subtree test confirms that partially clearing a
readable entry does not turn incomplete traversal into success.

The stalled-stdin test failed before the fix: a child holding stdin open without
reading returned only after its finite five-second lifetime, with EPIPE rather
than the configured timeout. After the fix it reports timeout and proves both
child and private process group are gone. A one-MiB transfer test checks that
nonblocking delivery does not truncate input. The focused process suite passed
all 13 tests.

The maintenance bridge fixture now gives candidate and previous executables
different bytes and execution markers, verifies the candidate main registrar
with previous ctl/helper, and rejects a maintenance bundle other than the
previous installation before teardown. Authorization-refusal fixtures replace
only the privileged execution boundary in a disposable lifecycle copy: finish
preserves the prepared ledger, release-lock preserves the locked ledger, and
both preserve disabled/offline service state. They do not invoke sudo or prove
native authorization/TCC behavior. These four focused tests passed 43 assertions.

## Validation boundary

Full `make verify-full SWIFT_BUILD_PATH="$PWD/.build"
APP_DIR="$PWD/.build/pr57-verification/Vifty.app"` passed with exit 0:

- 2,065 Swift tests, zero failures.
- 225 Ruby tests / 1,764 assertions, zero failures or skips. This includes 49
  installer/lifecycle tests / 675 assertions.
- Warnings-as-errors build, release app bundling, plist validation, deep/strict
  local code-sign verification, schema/wrapper checks, and CLI identifier checks.
- Independent narrow review of the new stdin loop found no concrete introduced
  issue; parent review and the tests remain the verification basis.

The local log is `.build/pr57-verify-full.log`. The lifecycle SHA256 is
`d343e2c3004cd3b5b5823480bbe83310a944c1695a8b52b90153be0518b9b695`.
The generated app is an isolated local validation bundle, not a new Developer ID
release. No installed app, daemon, fan state, permissions, release tag, or public
artifact was changed. At this validation checkpoint the edits were local;
the previous PR head's green CI does not validate them. Subsequent PR CI must
be checked against the commit containing these fixes.
