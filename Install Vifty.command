#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
OPEN_AFTER_INSTALL=1 exec ./scripts/install-vifty.sh
