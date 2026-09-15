#!/usr/bin/env bash
set -Eeuo pipefail

if (($# < 1)); then
  printf 'Usage: %s MODULE_NAME [additional build_wrf.sh options]\n' "$0" >&2
  exit 2
fi

readonly MODULE_NAME="$1"
shift
readonly PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
exec "$PROJECT_DIR/build_wrf.sh" \
  --module "$MODULE_NAME" \
  --compiler auto \
  --dependencies system \
  --parallel dmpar \
  --target em_real \
  --nesting basic \
  --wps yes \
  "$@"

