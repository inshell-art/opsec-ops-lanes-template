# Downstream Ops Contract

This document defines the **non-negotiable rules** for any business repo that adopts the template.

## Required directory conventions
Downstream repos must follow these (or compatible) paths:

```
ops/
  policy/
  runbooks/
  tools/
artifacts/
  <network>/current/
bundles/
  <network>/<run_id>/
```

- `ops/` contains policies, runbooks, and scripts.
- `artifacts/` contains generated evidence (intents, checks, approvals, snapshots).
- `bundles/` contains immutable bundle directories used across CI/CD and Signing OS.

## Required pipeline shape

### Remote CI (no secrets, no signing)
- Build/test (read-only)
- Generate bundle:
  - `run.json`
  - `intent.json`
  - `checks.json`
  - `bundle_manifest.json`
- Upload bundle as CI artifact

### Local CD (Signing OS only)
- Download bundle from AIRLOCK (untrusted input)
- Verify manifest hashes + policy compatibility
- Human approval recorded **before apply**
- Apply with keystore + Ledger only
- Produce post-apply evidence (`txs.json`, `snapshots/*`, `postconditions.json`)

## No manual args at apply time
Apply **must not** accept manual calldata, addresses, or tx hashes. It must read from the bundle artifacts.

## No LLM in apply
LLMs may be used to author scripts and docs, but **must never** be invoked at runtime for apply.

## AIRLOCK integrity rules
- AIRLOCK is **untrusted input**.
- Bundles are immutable once approved.
- Apply **refuses** on manifest mismatch or dirty repo.
- Chain truth is preferred over local `txs.json` when verifying.

## Sepolia → Mainnet gating
If policy requires a rehearsal proof:
- Mainnet apply **refuses** unless a Sepolia bundle exists with:
  - `txs.json`
  - `postconditions.json`
  - manifest hash match

At minimum, proof means a successful Sepolia run bundle archived and referenced by run id.
