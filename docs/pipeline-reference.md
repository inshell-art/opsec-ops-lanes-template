# Pipeline Reference (CI → Local CD)

This is a minimal “stupid steps” reference for the deterministic pipeline.

## Inputs
- `NETWORK` (`sepolia` | `mainnet`)
- `LANE` (`deploy` | `handoff` | `govern` | `treasury` | `operate` | `emergency`)
- `RUN_ID` (string; CI can default to `YYYYMMDDTHHMMSSZ-<short_sha>`)
- Optional: `BUNDLE_PATH` (local path to a bundle directory)
- Optional (mainnet only): `SEPOLIA_PROOF_RUN_ID` (run id of the rehearsal bundle)

## Outputs
- Bundle directory: `bundles/<network>/<run_id>/`
- Post-apply evidence:
  - `txs.json`
  - `snapshots/*`
  - `postconditions.json`

## Remote CI (plan + checks only)
1. Checkout repo (pinned action SHA).
2. Build/test (read-only).
3. Generate bundle:
   - `run.json` (includes git SHA)
   - `intent.json`
   - `checks.json` (read/sim only)
   - `bundle_manifest.json` (hashes immutable files)
4. Upload bundle artifact.

## Local CD (Signing OS only)
1. Pull bundle from AIRLOCK into `bundles/<network>/<run_id>/`.
2. Verify bundle:
   - manifest hashes match immutable files
   - `run.json` commit matches checkout
   - policy contains the lane
3. Approve bundle:
   - record approval tied to `bundle_hash`
   - typed phrase includes network + lane + hash suffix
4. Apply bundle (requires `SIGNING_OS=1`):
    - refuses on dirty repo
    - refuses on manifest mismatch
    - refuses if approval missing
    - refuses if policy requires Sepolia proof and it’s missing
    - no manual calldata/addresses at apply time
    - no LLM calls during apply
5. Write `txs.json`, `snapshots/*`, `postconditions.json`.

## CI hardening defaults
- Pin GitHub Actions to commit SHAs.
- Least privilege `GITHUB_TOKEN` permissions.
- No secrets in CI for public repos.
- Avoid workflows that run on fork PRs with write permissions.
