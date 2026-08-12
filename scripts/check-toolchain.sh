#!/usr/bin/env bash
set -euo pipefail

# Vifty builds SwiftUI views whose macros are compiled from Xcode's SwiftUI
# framework. The Command Line Tools SDK ships no SwiftUIMacros plugin, so a
# CLT-only developer directory fails with cryptic "SwiftUIMacros" errors.

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  # An explicit per-shell toolchain override takes precedence; honor it.
  exit 0
fi

developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
if [[ "${developer_dir}" == *"/CommandLineTools"* ]]; then
  echo "check-toolchain: the active developer directory is the Command Line Tools SDK (${developer_dir})." >&2
  echo "check-toolchain: Vifty needs a full Xcode toolchain for SwiftUI macros; builds under CLT fail with" >&2
  echo "check-toolchain: 'SwiftUIMacros' compile errors. Select Xcode once and re-run:" >&2
  echo "check-toolchain:   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  echo "check-toolchain: or set DEVELOPER_DIR for this shell, e.g.:" >&2
  echo "check-toolchain:   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer make verify" >&2
  exit 1
fi

if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
  echo "check-toolchain: xcodebuild is unavailable under the active developer directory '${developer_dir}'." >&2
  echo "check-toolchain: Select a full Xcode installation and re-run, or set DEVELOPER_DIR for this shell." >&2
  exit 1
fi
