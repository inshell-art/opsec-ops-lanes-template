# Ops tools (reference implementations)

These scripts are runnable reference implementations for the template contracts.
Downstream repos can adapt them, but should preserve the same inputs/outputs and refusal behavior.

Expected behavior by script:
- `bundle.sh` creates `run.json`, `intent.json`, `checks.json`, and `bundle_manifest.json` (plus `deploy_params.json` when required/provided).
- `verify_bundle.sh` verifies manifest hashes, git commit, policy compatibility, and deploy params pinning for required deploy lanes.
- `approve_bundle.sh` records human approval tied to the bundle hash (and deploy params hash when present).
- `apply_bundle.sh` executes the approved bundle in signing context only and enforces bundled deploy params on required deploy lanes.
- `postconditions.sh` records post-apply verification and writes `postconditions.json`.
- `audit_plan.sh` creates `audit_plan.json`.
- `audit_collect.sh` indexes evidence files and writes `audit_evidence_index.json`.
- `audit_verify.sh` runs control checks and writes `audit_verification.json`.
- `audit_report.sh` generates `audit_report.json` and `findings.json`.
- `audit_signoff.sh` writes `signoff.json` linked to the report hash.
- `audit_gate.sh` enforces release-gate policy on `audit_report.json`.

Audit output contract:
- required: `audit_plan.json`, `audit_evidence_index.json`, `audit_verification.json`, `audit_report.json`, `findings.json`
- optional but recommended: `signoff.json`

All write operations must use keystore mode only. Do not use accounts-file signing.

Release gate behavior:
- periodic audit runs can publish artifacts without blocking releases
- release-gate runs should fail when `audit_report.json.status` is listed under `release_gate.fail_on_status`

Deploy params behavior:
- required by default for `sepolia/mainnet` `deploy` lanes when `deploy_params_pinned` is in lane `required_checks`
- source file env var defaults to `DEPLOY_PARAMS_FILE`
- bundled filename defaults to `deploy_params.json`
- apply rejects mismatched external params override when policy `allow_external_override` is `false`

Reference tests:
- `examples/scaffold/tests/audit_smoke.sh`
- `examples/scaffold/tests/audit_negative.sh`
- `examples/scaffold/tests/deploy_params_gate.sh`

Review and adapt these scripts before production use.
