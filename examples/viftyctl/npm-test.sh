#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

exec "$script_dir/guarded-run.sh" test 20m 70 "npm test" -- npm test "$@"
