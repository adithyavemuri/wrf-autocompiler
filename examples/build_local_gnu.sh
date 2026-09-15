#!/usr/bin/env bash
set -Eeuo pipefail
readonly PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec "$PROJECT_DIR/build_wrf.sh" \
  --compiler gnu \
  --dependencies local \
  --parallel dmpar \
  --target em_real \
  --nesting basic \
  --wps yes \
  "$@"

