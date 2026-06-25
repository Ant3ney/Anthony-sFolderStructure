#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

read_toml_string() {
  local file="$1"
  local key="$2"
  local line value

  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null | tail -n 1 || true)"
  value="${line#*=}"
  value="${value%%#*}"
  value="${value//[[:space:]]/}"
  value="${value%\"}"
  value="${value#\"}"

  printf '%s' "$value"
}

require_output() {
  local output="$1"
  local expected="$2"
  local label="$3"

  if [[ "$output" != *"$expected"* ]]; then
    fail "$label did not contain '$expected'"
  fi
}

require_file_contains() {
  local file="$1"
  local expected="$2"
  local label="$3"

  grep -Fq -- "$expected" "$file" || fail "$label did not contain '$expected'"
}

require_file_count_at_least() {
  local file="$1"
  local expected="$2"
  local minimum="$3"
  local label="$4"
  local count

  count="$(grep -Fc -- "$expected" "$file" || true)"
  [[ "$count" -ge "$minimum" ]] || fail "$label contained '$expected' $count time(s), expected at least $minimum"
}

audit_startup_guard_rejects_restrictive_config() {
  local services_module="$1"
  local bad_config services_module_url output

  bad_config="$(mktemp)"
  printf 'approval_policy = "on-request"\nsandbox_mode = "workspace-write"\n' > "$bad_config"
  services_module_url="$(node -e "const { pathToFileURL } = require('node:url'); console.log(pathToFileURL(process.argv[1]).href)" "$services_module")"

  if output="$(CODEX_CONFIG_FILE="$bad_config" STONEFORGE_SERVICES_MODULE_URL="$services_module_url" node --input-type=module 2>&1 <<'NODE'
const services = await import(process.env.STONEFORGE_SERVICES_MODULE_URL);

try {
  await services.initializeServices({ dbPath: ':memory:', projectRoot: process.cwd() });
  console.error('initializeServices unexpectedly accepted restrictive Codex config');
  process.exit(1);
} catch (error) {
  const message = String(error?.message ?? error);
  if (
    message.includes('Codex permission invariant violation') &&
    message.includes('approval_policy') &&
    message.includes('sandbox_mode')
  ) {
    console.log('startup guard rejected restrictive Codex config');
    process.exit(0);
  }

  console.error(message);
  process.exit(1);
}
NODE
  )"; then
    rm -f "$bad_config"
    require_output "$output" 'startup guard rejected restrictive Codex config' "startup guard audit"
    return 0
  fi

  rm -f "$bad_config"
  fail "startup guard did not reject restrictive Codex config: $output"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_CONFIG="${CODEX_CONFIG_FILE:-${CODEX_HOME:-$HOME/.codex}/config.toml}"
CODEX_WRAPPER="${STONEFORGE_CODEX_WRAPPER:-$HOME/.local/bin/codex-stoneforge}"
CODEX_WRAPPER_TEMPLATE="${STONEFORGE_CODEX_WRAPPER_TEMPLATE:-$REPO_ROOT/tools/codex-stoneforge}"
SF_BIN="$(readlink -f "$(command -v sf)")"
SMITHY_ROOT="${STONEFORGE_SMITHY_ROOT:-$(dirname "$(dirname "$(dirname "$SF_BIN")")")}"

[[ -f "$CODEX_CONFIG" ]] || fail "Codex config not found at $CODEX_CONFIG"
[[ -f "$CODEX_WRAPPER_TEMPLATE" ]] || fail "Tracked Codex wrapper template not found at $CODEX_WRAPPER_TEMPLATE"

approval_policy="$(read_toml_string "$CODEX_CONFIG" approval_policy)"
sandbox_mode="$(read_toml_string "$CODEX_CONFIG" sandbox_mode)"

[[ "$approval_policy" == "never" ]] || fail "approval_policy is '${approval_policy:-unset}', expected 'never'"
[[ "$sandbox_mode" == "danger-full-access" ]] || fail "sandbox_mode is '${sandbox_mode:-unset}', expected 'danger-full-access'"

sf_config="$(sf config show --json)"
require_output "$sf_config" '"permissionModel": "unrestricted"' "sf config"

[[ -x "$CODEX_WRAPPER" ]] || fail "Codex Stoneforge wrapper is not executable at $CODEX_WRAPPER"
if ! cmp -s "$CODEX_WRAPPER_TEMPLATE" "$CODEX_WRAPPER"; then
  fail "installed wrapper at $CODEX_WRAPPER differs from tracked template $CODEX_WRAPPER_TEMPLATE"
fi
wrapper_audit="$("$CODEX_WRAPPER" --stoneforge-permission-audit)"
require_output "$wrapper_audit" 'approval_policy=never' "wrapper audit"
require_output "$wrapper_audit" 'sandbox_mode=danger-full-access' "wrapper audit"
require_output "$wrapper_audit" 'launch_approval_policy=never' "wrapper audit"
require_output "$wrapper_audit" 'launch_sandbox_mode=danger-full-access' "wrapper audit"

if output="$("$CODEX_WRAPPER" --ask-for-approval on-request --help 2>&1)"; then
  fail "wrapper accepted --ask-for-approval on-request"
else
  require_output "$output" "refusing approval override" "bad approval rejection"
fi

if output="$("$CODEX_WRAPPER" --sandbox workspace-write --help 2>&1)"; then
  fail "wrapper accepted --sandbox workspace-write"
else
  require_output "$output" "refusing sandbox override" "bad sandbox rejection"
fi

if output="$("$CODEX_WRAPPER" --config approval_policy=on-request --help 2>&1)"; then
  fail "wrapper accepted --config approval_policy=on-request"
else
  require_output "$output" "refusing Codex config override" "bad approval config rejection"
fi

if output="$("$CODEX_WRAPPER" --dangerously-bypass-approvals-and-sandbox --help 2>&1)"; then
  fail "wrapper accepted --dangerously-bypass-approvals-and-sandbox"
else
  require_output "$output" "refusing sandbox bypass flag" "sandbox bypass rejection"
fi

interactive_provider="$SMITHY_ROOT/dist/providers/codex/interactive.js"
server_manager="$SMITHY_ROOT/dist/providers/codex/server-manager.js"
headless_provider="$SMITHY_ROOT/dist/providers/codex/headless.js"
startup_services="$SMITHY_ROOT/dist/server/services.js"

[[ -f "$interactive_provider" ]] || fail "Codex interactive provider not found at $interactive_provider"
[[ -f "$server_manager" ]] || fail "Codex server manager not found at $server_manager"
[[ -f "$headless_provider" ]] || fail "Codex headless provider not found at $headless_provider"
[[ -f "$startup_services" ]] || fail "Stoneforge service startup file not found at $startup_services"

require_file_contains "$interactive_provider" "'--ask-for-approval', 'never', '--sandbox', 'danger-full-access'" "interactive provider"
require_file_contains "$server_manager" "'--ask-for-approval', 'never', '--sandbox', 'danger-full-access', 'app-server'" "app-server launch"
require_file_count_at_least "$headless_provider" "approvalPolicy: 'never'" 2 "headless provider"
require_file_count_at_least "$headless_provider" "sandbox: 'danger-full-access'" 2 "headless provider"
if grep -q -- "--full-auto" "$interactive_provider"; then
  fail "interactive provider still uses obsolete --full-auto"
fi

require_file_contains "$startup_services" "PROTECTED_CODEX_APPROVAL_POLICY = 'never'" "startup guard"
require_file_contains "$startup_services" "PROTECTED_CODEX_SANDBOX_MODE = 'danger-full-access'" "startup guard"
require_file_contains "$startup_services" "config.agents?.permissionModel !== 'unrestricted'" "startup guard"
require_file_contains "$startup_services" "assertCodexBasePermissionInvariant(config)" "startup guard"
require_file_contains "$startup_services" "assertCodexAgentLaunchers(agents)" "startup guard"
require_file_contains "$startup_services" "--stoneforge-permission-audit" "startup guard"
audit_startup_guard_rejects_restrictive_config "$startup_services"

echo "PASS: Stoneforge Codex permission invariant is enforced and auditable."
