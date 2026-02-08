# AGENTS.md — downstream usage guide

This file is for agent operators working in downstream repos that consume this template via subtree or submodule.

## Purpose
- The template repo is the source of truth for ops‑lanes docs, policies, schemas, and examples.
- Downstream repos should **consume** it, not edit it in place.

## Where it lives in downstream repos
- Subtree (current default): `opsec-ops-lanes-template/`
- Submodule (optional): `ops-template/` or another stable path

## What agents may do in downstream repos
- Reference template docs directly from the subtree path.
- Copy example policy files into `ops/policy/` and edit the copies.
- Create runbooks in `ops/runbooks/`.
- Maintain run artifacts in `artifacts/<network>/...` (commit only what is safe).
- Add local `.env.example` and `.gitignore` entries that keep secrets out of git.

## What agents must not do in downstream repos
- Do not edit files inside the subtree path (`opsec-ops-lanes-template/`) directly.
- Do not commit secrets, keystores, seed phrases, or RPC credentials.
- Do not introduce accounts‑file signing mode. Keystore mode only.

## How to update the template in a downstream repo
Use one of these methods:

```bash
git subtree pull --prefix opsec-ops-lanes-template https://github.com/inshell-art/opsec-ops-lanes-template.git main --squash
```

```bash
make -f ops/Makefile subtree-update
```

If the repo has a helper script:

```bash
ops/tools/update_ops_template.sh
```

## How to make edits to the template
- Make edits **in the template repo** (`opsec-ops-lanes-template`), then push to `main`.
- Downstream repos should pull updates via subtree or submodule.

## Minimal verification checklist for agents
- Confirm the template subtree path exists.
- Ensure the downstream repo has a local policy copy in `ops/policy/`.
- Check that no secrets are tracked in git.
- Verify that docs used by operators match the template versions.

## Operator safety reminders
- Keep keystore and `account.json` paths outside the repo and reference via local env vars.
- Never paste private keys or mnemonics into docs, scripts, or chat logs.
- Do not approve or execute a write without the required checks and approvals.
