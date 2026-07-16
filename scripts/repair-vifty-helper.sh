#!/usr/bin/env -S -i HOME=/var/empty PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(/usr/bin/dirname -- "$0")" && pwd -P)"
exec /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /bin/bash --noprofile --norc "${SCRIPT_DIR}/vifty-helper-lifecycle.sh" \
  --operation repair "$@"
