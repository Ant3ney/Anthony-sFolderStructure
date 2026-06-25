# Codex Permission Invariants for Stoneforge Agents

## Protected Invariant

Stoneforge agent execution in this workspace must stay non-interactive and must not prompt workers for permission during normal task execution unless the human explicitly requests that mode change.

The intended Codex runtime settings for this workspace are:

```toml
approval_policy = "never"
sandbox_mode = "danger-full-access"
```

These settings are operational invariants, not convenience defaults. They prevent workers from stalling on approval prompts that cannot be answered inside the Stoneforge task lifecycle.

## Disallowed Overrides

Wrappers, provider launch paths, daemon dispatch code, shell aliases, environment shims, and agent launcher scripts must not override the workspace settings with any prompt-for-permission behavior unless the human explicitly asks for it.

Disallowed changes include:

- `--ask-for-approval on-request`
- `approval_policy = "on-request"` or any other prompting approval policy
- `--sandbox workspace-write`
- `sandbox_mode = "workspace-write"` or any other sandbox that blocks normal workspace access
- Any equivalent setting that asks the worker to request permission before reading files, writing files, running commands, using the network, or completing task lifecycle commands

Do not treat a permissive direct Codex config file as sufficient proof. The Director observed a failure mode where direct Codex config showed `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`, while a wrapper or provider launch path still injected restrictive approval or sandbox flags at runtime.

## Audit Checklist

When permission prompts appear, or when changing agent launch code, audit the effective runtime path end to end:

1. Confirm the direct Codex config still contains `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`.
2. Inspect the wrapper, provider, daemon, and launcher command that actually starts Codex for injected approval or sandbox flags.
3. Search launch scripts, provider manifests, environment templates, and shell aliases for `ask-for-approval`, `approval_policy`, `sandbox`, `sandbox_mode`, `workspace-write`, `on-request`, and similar permission terms.
4. Compare the session's effective runtime context against the config file. Runtime context wins if it differs from the direct config.
5. Remove accidental restrictive overrides. If a restrictive mode is intentional, verify the request came explicitly from the human before preserving it.

If a worker cannot complete the audit or cannot remove the override safely, hand off the task with the exact file, command, wrapper, or provider path that appears to be changing the effective permission behavior.
