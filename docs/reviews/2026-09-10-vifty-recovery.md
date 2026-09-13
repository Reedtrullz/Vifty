# Vifty recovery and lean-polish execution review

Date: 2026-09-12
Status: blocked before public-release replacement

## Verified execution

- Preserved the inherited dirty `codex/lean-polish` checkout at `e79bcab20ad7c9eda302fe4594bfa547b15f929a`; no reset, stash, clean, merge, release, tag, deployment, or global BTM reset was performed.
- Fixed one source integrity mismatch in `Sources/Vifty/DaemonInstallService.swift`: the compiled lifecycle-script SHA now matches the reviewed dirty `scripts/vifty-helper-lifecycle.sh` bytes (`9ff0f8137af7938917ac85fb59b8cda0a0062d5c71045ac6186cf3f417911074`). The focused regression passed.
- The initial full gate was blocked by six release-artifact fixture commits inheriting the host's global Git SSH-signing configuration and failing through 1Password. A focused reproduction passed with Git configuration isolated; the hermetic full gate then passed with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null`.
- Hermetic `make verify-full SWIFT_BUILD_PATH="$PWD/.build"` exited `0`: 2,037 XCTest cases passed, the release app build/bundle/codesign checks passed, and all Ruby release, governance, installer, helper-lifecycle, and UI evidence suites passed.
- The exact public archive was verified before installation: v1.4.5, 5,901,723 bytes, SHA-256 `13fa763cbfdca3e77fcf6f657df6d51b32e19a4d25dd17a79614635fe844b0d5`, notarized Developer ID identity, stapling, and Gatekeeper acceptance.

## Blocking result

`make install-public-release PUBLIC_RELEASE_ARCHIVE=.build/vifty-recovery/Vifty-v1.4.5.zip` stopped with exit 75 before replacement. The installer rejected the existing `/Applications/Vifty.app` because it is an ad-hoc v1.4.5 build 13 without a Team ID and is not an authenticated Developer ID or authenticated exact-path development source. The installer explicitly requires the existing app's CLI-mediated authorization/removal path before replacement.

Post-stop readback confirms the existing app remains ad-hoc (`TeamIdentifier=not set`) and the daemon remains in the prior `spawn failed`, `last exit code = 78: EX_CONFIG`, `needs LWCR update` state. No helper repair, native registration repair, healthy diagnose, Fixed/Curve UI smoke, Auto restoration, fan/SMC write, or cooling request was attempted.

## Evidence

All execution evidence is retained in:

`/Users/reidar/Projectos/Vifty/.build/vifty-recovery/continuation-20260911-221936/`

Key files: `verify-full-hermetic.log`, `public-release-verifier.log`, `public-release-summary.json`, `public-install.log`, and `public-install-blocker-state.txt`.

## Required next action

Obtain the owner-authorized CLI-mediated transition for the existing ad-hoc installation, then rerun the reviewed exact-archive installer. Do not bypass this gate with a raw app copy, direct helper/SMC command, manual BTM reset, or edited transaction ledger. Until that transition succeeds, runtime recovery and hardware acceptance remain unverified.
