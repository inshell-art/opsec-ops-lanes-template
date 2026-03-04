# Scaffold audit tests

These scripts validate the template audit module contracts in an isolated temporary scaffold checkout.

## Scripts
- `audit_smoke.sh`
  - Runs `bundle -> audit_plan -> audit_collect -> audit_verify -> audit_report`.
  - Checks required audit output files and JSON validity.
- `audit_negative.sh`
  - Verifies expected failures for:
    - manifest mismatch
    - commit mismatch
    - missing approval
    - approval hash mismatch
    - missing postconditions in required rehearsal proof
- `deploy_params_gate.sh`
  - Verifies deploy params integrity gate behavior:
    - missing params fail for Sepolia/Mainnet deploy bundle
    - mutated bundled params fail verify
    - external override fails apply
    - valid pinned params pass verify/apply and are recorded in apply evidence
    - mainnet rehearsal-proof gate remains enforced

## Usage
```bash
examples/scaffold/tests/audit_smoke.sh
examples/scaffold/tests/audit_negative.sh
examples/scaffold/tests/deploy_params_gate.sh
```
