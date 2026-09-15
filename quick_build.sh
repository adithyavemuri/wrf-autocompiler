#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

"$PROJECT_DIR/build_wrf.sh" \
  --preflight \
  --compiler gnu \
  --dependencies local \
  --parallel dmpar \
  --target em_real \
  --nesting basic \
  --wps yes

exec "$PROJECT_DIR/examples/build_local_gnu.sh" "$@"

