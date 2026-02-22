# Changelog

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
