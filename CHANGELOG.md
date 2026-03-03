# Changelog

## 2026-03-03

### feat: audit module v1.1 (contract hardening)

- Hardened audit module contract and defaults:
  - required audit outputs now explicitly include:
    - `audit_plan.json`
    - `audit_evidence_index.json`
    - `audit_verification.json`
    - `audit_report.json`
    - `findings.json`
  - `signoff.json` remains optional but recommended
- Extended audit policy template with:
  - `required_artifacts`
  - `claims.require_tier_labels`
  - `release_gate.fail_on_status`
- Updated audit schemas:
  - `audit_plan.schema.json` requires `generated_at`
  - `audit_report.schema.json` now requires `network` and `inferred_claims`
  - `audit_finding.schema.json` now requires `tier`
- Updated scaffold audit scripts:
  - `audit_plan.sh` enforces schema-required keys
  - `audit_report.sh` now requires plan/index/verification inputs, validates claim-tier outputs, and enforces required artifact presence before finalize
  - `audit_gate.sh` enforces release-gate policy status checks
- Updated scaffold CI example (`examples/scaffold/.github/workflows/ops_audit.yml`):
  - supports both periodic audit mode and release-gate mode
  - includes tag-triggered release-gate example (`v*`)
- Added scaffold test fixtures/scripts:
  - `examples/scaffold/tests/audit_smoke.sh`
  - `examples/scaffold/tests/audit_negative.sh`
  - negative checks cover manifest mismatch, commit mismatch, missing approval/hash mismatch, and missing required rehearsal postconditions
- Added missing fixture artifact:
  - `examples/scaffold/audits/devnet/audit-20260222-example/audit_verification.json`

### migration notes (downstream repos)

- Update `ops/policy/audit.policy.json` from the v1.1 example.
- Wire audit targets in `ops/Makefile`:
  - `audit-plan`, `audit-collect`, `audit-verify`, `audit-report`, `audit-signoff`, `audit-gate`
- Paste/update root `AGENTS.md` snippets:
  - `docs/snippets/root-AGENTS-ops-agent-contract.md`
  - `docs/snippets/root-AGENTS-audit-response-contract.md`

## 2026-03-01

### feat: audit module v1 (opt-in)

- Added audit module docs:
  - `docs/audit-framework.md`
  - `docs/audit-runbook.md`
  - `docs/audit-controls-catalog.md`
  - `docs/snippets/root-AGENTS-audit-response-contract.md`
- Added audit schemas:
  - `schemas/audit_plan.schema.json`
  - `schemas/audit_report.schema.json`
  - `schemas/audit_finding.schema.json`
- Added audit policy templates:
  - `policy/audit.policy.example.json`
  - `examples/scaffold/ops/policy/audit.policy.example.json`
- Added scaffold audit tools and make targets:
  - `audit_plan.sh`, `audit_collect.sh`, `audit_verify.sh`, `audit_report.sh`, `audit_signoff.sh`
  - `audit-plan`, `audit-collect`, `audit-verify`, `audit-report`, `audit-signoff`, `audit-all`
- Added scaffold audit artifacts fixture:
  - `examples/scaffold/audits/devnet/audit-20260222-example/*`
- Added optional CI entrypoint:
  - `examples/scaffold/.github/workflows/ops_audit.yml`

Compatibility:
- Existing lane flow remains unchanged (`bundle -> verify -> approve -> apply -> postconditions`).
- Audit module is opt-in for the first release cycle.

## 2026-02-22

### breaking: devnet-first rehearsal and generic proof gating

- Added Devnet as a first-class rehearsal network across template scripts, examples, and CI workflow inputs.
- Mainnet example write lanes now use generic rehearsal gates:
  - `gates.require_rehearsal_proof`
  - `gates.rehearsal_proof_network`
- Mainnet example policies now default to Devnet proof (`rehearsal_proof_network: "devnet"`).
- Added new template/example files:
  - `policy/devnet.policy.example.json`
  - `examples/scaffold/ops/policy/lane.devnet.example.json`
  - `examples/scaffold/artifacts/devnet/current/addresses.example.json`
  - `examples/toy/artifacts/devnet/current/*`
- Updated apply gate logic to resolve proof bundles from `bundles/<rehearsal_network>/<run_id>/` instead of hardcoding Sepolia.

### migration notes

- New canonical proof env var:
  - `REHEARSAL_PROOF_RUN_ID`
- Backward-compatible proof env fallbacks are still supported for one migration cycle:
  - `DEVNET_PROOF_RUN_ID`
  - `SEPOLIA_PROOF_RUN_ID`
- Deprecated but temporarily supported legacy policy keys:
  - `requires_devnet_rehearsal_proof` / `gates.require_devnet_rehearsal_proof`
  - `requires_sepolia_rehearsal_proof` / `gates.require_sepolia_rehearsal_proof`

## 2026-02-11

### breaking: drop legacy lane aliases, enforce semantic lane IDs only

- Removed `lane_aliases` from:
  - `policy/sepolia.policy.example.json`
  - `policy/mainnet.policy.example.json`
- Semantic lane IDs are now the only supported machine-facing IDs:
  - `observe`, `plan`, `deploy`, `handoff`, `govern`, `treasury`, `operate`, `emergency`
- Updated example intent lane value to semantic form in:
  - `examples/toy/artifacts/sepolia/current/intents/deploy_gov_safe.intent.json`

### Migration required for downstream repos

- Use semantic lane names only in:
  - policy lane keys
  - workflow inputs (`LANE`)
  - intent artifacts (`"lane": "<semantic_id>"`)
- Remove alias-normalization logic and legacy `lane_aliases` blocks in downstream tooling and policy files.
