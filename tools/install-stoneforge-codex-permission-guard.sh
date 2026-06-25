#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_TEMPLATE="${STONEFORGE_CODEX_WRAPPER_TEMPLATE:-$SCRIPT_DIR/codex-stoneforge}"
WRAPPER_TARGET="${STONEFORGE_CODEX_WRAPPER:-$HOME/.local/bin/codex-stoneforge}"

if [[ ! -f "$WRAPPER_TEMPLATE" ]]; then
  echo "Tracked Codex wrapper template not found: $WRAPPER_TEMPLATE" >&2
  exit 1
fi

install -d "$(dirname "$WRAPPER_TARGET")"
install -m 0755 "$WRAPPER_TEMPLATE" "$WRAPPER_TARGET"

"$SCRIPT_DIR/stoneforge-codex-permission-audit.sh"

echo "Installed Stoneforge Codex wrapper guard at $WRAPPER_TARGET"
echo "Verified installed Smithy provider/startup guards without mutating ~/.codex/config.toml"
