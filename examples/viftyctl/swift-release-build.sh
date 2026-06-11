#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

exec "$script_dir/guarded-run.sh" build 25m 75 "swift release build" -- swift build -c release "$@"
