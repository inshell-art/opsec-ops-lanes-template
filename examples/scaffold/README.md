# Scaffold example (downstream repo)

Purpose: provide a minimal, safe layout to integrate this template and run rehearsals (lane0 and lane1) in CI while keeping lane2+ manual.

This scaffold is **not runnable by default**. The `plan/check/approve/apply` scripts are stubs that intentionally fail until you implement them for your repo.

## Layout
- `ops/` — policy, runbooks, and tooling wrappers
- `artifacts/` — generated intents, checks, approvals, and snapshots
- `bundles/` — deterministic bundles (optional; created by bundle tooling)
- `ci/` — example CI workflow files to copy into `.github/workflows/`
- `.env.example` — local-only environment variables (no secrets)

## How to use
1. Copy this scaffold into your downstream repo root, or copy the pieces you want.
2. Replace stubs in `ops/tools/plan.sh`, `check.sh`, `approve.sh`, `apply.sh` with your real commands.
3. Copy example policies from the template into `ops/policy/` and edit the copies.
4. Keep secrets out of git.

## Optional: deterministic bundle tooling
This scaffold also includes `bundle.sh`, `verify_bundle.sh`, `approve_bundle.sh`, and `apply_bundle.sh` as **reference implementations** for deterministic bundles.
Review and adapt these scripts before use.

## CI and rehearsal guidance
- CI should run plan and check only (lane0 and lane1).
- Lane2+ apply happens on a signing OS with keystore mode only.
- HOT wallets are not ops-lane signers.

## References
- `docs/ops-lanes-agent.md`
- `docs/opsec-ops-lanes-signer-map.md`
- `docs/integration.md`
