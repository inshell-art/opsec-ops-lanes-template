# opsec-ops-lanes-template

A public, repo-safe template for running **intent-gated onchain operations** with an **agent** under a practical **OPSEC compartment model**.

This repo contains:
- `docs/ops-lanes-agent.md` — the “Ops Lanes” contract between an agent and a human operator (keystore-mode signing, no accounts-file mode).
- `docs/opsec-ops-lanes-signer-map.md` — OPSEC compartments + signer aliases + phase split (Sepolia rehearsal → Mainnet).
- `policy/*.example.json` — example lane policies (RPC allowlist, signer allowlists, fee thresholds, required checks).
- `schemas/*` — starter JSON schemas for intent/check/approval artifacts.
- `examples/*` — toy examples (no real addresses, no secrets).
- `codex/BOOTSTRAP.md` — maintainer steps to create and publish the template repo.
- `codex/BUSINESS_REPO_ADOPTION.md` — quick checklist for adopting this template inside a business repo.

## What this template is (and is not)

**It is:**
- A disciplined process for *how* to deploy, handoff, and govern using deterministic intents + checks + approvals.
- A way to make agent-assisted ops safer by forcing “meaning approval” and “reality verification”.

**It is not:**
- A wallet tutorial.
- A full security guarantee.

## Secrets rule

This repo **must stay public-safe**:
- No seed phrases, private keys, keystore JSON, 2FA backups, RPC URLs with embedded credentials, or screenshots.
- Keystores and passwords live **outside the repo** (e.g., in a local encrypted directory or dedicated Signing OS).

## How to use this template in a business repo

Note: Fork/copy/submodule this repo into your business repo and keep secrets out of git (keystore/account.json, seed phrases, 2FA backups, RPC credentials). Commit only `*.example` templates.

Pick one approach:

### Option A — Git submodule (recommended for shared rules)
Add this repo to your business repo at a stable path (example: `ops-template/`), then reference docs/policy from there.

### Option B — Git subtree (simpler than submodules for some teams)
Vendor the template into your repo and periodically pull updates.

### Option C — Copy the docs
Copy `docs/` and `policy/` and maintain your own fork.

## Suggested private repo layout (business repo)

Keep “rules” separate from “instance data”:

- `ops-template/` (this repo, read-only)
- `ops/` (your instance: runbooks, lane policy, artifacts)
- `artifacts/<network>/...` (generated, commit only what you want public)

See `docs/integration.md` for a full example.

## License

MIT (see `LICENSE`).

## Contributing

PRs that improve safety, clarity, and reproducibility are welcome. See `CONTRIBUTING.md`.
