# Codex Permission Invariants for Stoneforge Agents

## Protected Invariant

Stoneforge agent execution in this workspace must stay non-interactive and must not prompt workers for permission during normal task execution unless the human explicitly requests that mode change.

The intended Codex runtime settings for this workspace are:

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

These settings are operational invariants, not convenience defaults. They prevent workers from stalling on approval prompts that cannot be answered inside the Stoneforge task lifecycle.

The Stoneforge workspace config must also keep:

```yaml
agents:
  permissionModel: unrestricted
```

## Enforced Paths

The protected rule is enforced in the current workspace through checked-in guard assets and installed launch checks:

- [tools/codex-stoneforge](../../tools/codex-stoneforge) is the tracked wrapper template for `~/.local/bin/codex-stoneforge`. It validates `~/.codex/config.toml`, rejects restrictive approval/sandbox/config overrides, normalizes obsolete `--full-auto`/`--yolo` shorthands, and launches Codex with `--ask-for-approval never --sandbox danger-full-access`.
- [tools/install-stoneforge-codex-permission-guard.sh](../../tools/install-stoneforge-codex-permission-guard.sh) installs the tracked wrapper template and verifies the installed Stoneforge Smithy package guards. It must not mutate `~/.codex/config.toml`.
- [tools/stoneforge-codex-permission-audit.sh](../../tools/stoneforge-codex-permission-audit.sh) audits the effective runtime. It fails if the installed wrapper differs from the tracked template, if provider launch paths are not pinned to the protected flags, if Codex headless threads are not created/resumed with protected policy values, or if Stoneforge service startup does not reject a restrictive temporary Codex config before worker launch.
- Stoneforge service startup currently fails before worker launch when `agents.permissionModel` is not `unrestricted`, when the Codex config does not contain the protected values, or when registered `codex-stoneforge` wrappers fail audit mode.

## Disallowed Overrides

Wrappers, provider launch paths, daemon dispatch code, shell aliases, environment shims, and agent launcher scripts must not override the workspace settings with any prompt-for-permission behavior unless the human explicitly asks for it.

Disallowed changes include:

- `--ask-for-approval on-request`
- `approval_policy = "on-request"` or any other prompting approval policy
- `--sandbox workspace-write`
- `sandbox_mode = "workspace-write"` or any other sandbox that blocks normal workspace access
- `--dangerously-bypass-approvals-and-sandbox`, because it bypasses the protected sandbox invariant instead of preserving it
- Any equivalent setting that asks the worker to request permission before reading files, writing files, running commands, using the network, or completing task lifecycle commands

Do not treat a permissive direct Codex config file as sufficient proof. The Director observed a failure mode where direct Codex config showed `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`, while a wrapper or provider launch path still injected restrictive approval or sandbox flags at runtime.

## Audit Command

Run the checked-in audit script from the workspace root:

```bash
tools/stoneforge-codex-permission-audit.sh
```

The script checks:

- `~/.codex/config.toml` has `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`.
- `sf config show --json` reports `agents.permissionModel` as `unrestricted`.
- `~/.local/bin/codex-stoneforge` is byte-for-byte identical to the checked-in [tools/codex-stoneforge](../../tools/codex-stoneforge) template.
- `~/.local/bin/codex-stoneforge --stoneforge-permission-audit` reports protected config and launch values.
- The wrapper rejects restrictive approval, sandbox, config, and sandbox-bypass overrides.
- The installed Codex interactive, app-server, and headless provider launch paths are pinned to the protected values and do not use obsolete `--full-auto`.
- Stoneforge `initializeServices()` rejects a temporary restrictive Codex config before worker launch.

For a direct wrapper-only audit:

```bash
~/.local/bin/codex-stoneforge --stoneforge-permission-audit
```

## Recovery Checklist

When permission prompts appear, or when changing agent launch code, audit the effective runtime path end to end:

1. Confirm the direct Codex config still contains `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`.
2. Confirm `sf config show --json` still reports `agents.permissionModel` as `unrestricted`.
3. Run `tools/stoneforge-codex-permission-audit.sh`.
4. Inspect the wrapper, provider, daemon, and launcher command that actually starts Codex for injected approval or sandbox flags.
5. Search launch scripts, provider manifests, environment templates, and shell aliases for `ask-for-approval`, `approval_policy`, `sandbox`, `sandbox_mode`, `workspace-write`, `on-request`, `dangerously-bypass-approvals-and-sandbox`, and similar permission terms.
6. Compare the session's effective runtime context against the config file. Runtime context wins if it differs from the direct config.
7. Remove accidental restrictive overrides. If a restrictive mode is intentional, verify the request came explicitly from the human before preserving it.

If a worker cannot complete the audit or cannot remove the override safely, hand off the task with the exact file, command, wrapper, or provider path that appears to be changing the effective permission behavior.
