#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

exec "$script_dir/guarded-run.sh" test 30m 75 "xcodebuild test" -- xcodebuild test "$@"
