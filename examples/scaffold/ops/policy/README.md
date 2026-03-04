# Policy files

Copy example policies from the template repo and edit the copies:
- `ops/policy/lane.devnet.example.json` -> `ops/policy/lane.devnet.json`
- `ops/policy/lane.sepolia.example.json` -> `ops/policy/lane.sepolia.json`
- `ops/policy/lane.mainnet.example.json` -> `ops/policy/lane.mainnet.json`
- `ops/policy/audit.policy.example.json` -> `ops/policy/audit.policy.json`

Keep secrets out of git. Only reference local keystore paths via env vars.

Mainnet write lanes default to:
- `gates.require_rehearsal_proof: true`
- `gates.rehearsal_proof_network: "devnet"`
Only set the gate to false if you are consciously overriding the control.
For EVM lanes, set realistic EIP-1559 bounds in each lane's `fee_policy`.
Sepolia/Mainnet deploy lanes default to include:
- `deploy_params_pinned` in `lanes.deploy.required_checks`
- `deploy_params.required_networks: [\"sepolia\", \"mainnet\"]`
- `deploy_params.required_lanes: [\"deploy\"]`
- `deploy_params.bundle_filename: \"deploy_params.json\"`
- `deploy_params.apply_env_var: \"DEPLOY_PARAMS_FILE\"`
- `deploy_params.allow_external_override: false`
- `deploy_params.schema_file: \"schemas/deploy_params.schema.json\"`
- `deploy_params.semantic_validator_cmd: \"\"` (downstream hook for protocol-specific checks)
Legacy keys (`requires_*_rehearsal_proof`, `gates.require_*_rehearsal_proof`) are deprecated but temporarily supported during migration.
Audit policy controls coverage thresholds and open-finding gates for periodic/release audits.
Audit contract requires:
- `audit_plan.json`
- `audit_evidence_index.json`
- `audit_verification.json`
- `audit_report.json`
- `findings.json`
Optional but recommended:
- `signoff.json`
