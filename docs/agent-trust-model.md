# Agent Trust Model for Ops Lanes Bundles

This document defines how to use an LLM agent (for example, Codex) without making it a security boundary.

Core principle:

- Humans approve meaning.
- Deterministic scripts verify reality.
- Runtime apply uses pinned scripts only.

## 1) Trust the verifiers, not the agent

Treat agent output as untrusted suggestions until reproducible by deterministic checks.

For bundle integrity, the source of truth is script behavior and exit codes, not natural language claims.

## 2) Trust tiers for agent statements

Every agent statement about correctness should be labeled as one of:

- `PROPOSED`: idea or plan, not verified.
- `VERIFIED`: reproducible with deterministic commands and expected outputs.
- `PINNED`: verified and tied to a specific commit/tag.
- `ON_CHAIN`: verified from chain receipts/events/transactions.

`PROPOSED` must never be presented as `VERIFIED`.

## 3) Evidence Pack format (required)

For any instruction or claim like "X is proven", provide:

1. Claim (with tier)
2. Source of truth script(s) and commit (`git rev-parse HEAD`)
3. Exact reproduce command(s)
4. Expected output
5. Files read/produced
6. Stop conditions
7. What the evidence does not prove

## 4) What "bundle consistency" means in this template

A bundle is consistent when:

- Required files exist:
  - `run.json`
  - `intent.json`
  - `checks.json`
  - `bundle_manifest.json`
- `bundle_manifest.json` has `immutable_files` entries with `path` + `sha256`.
- The verifier recomputes each immutable hash and matches all entries.
- Recomputed aggregate `bundle_hash` matches the manifest.
- Cross-file identity matches expected values (`network`, `lane`, `run_id`, `git_commit`).
- If `approval.json` exists, it binds to the same `bundle_hash`.

Operationally, this gives tamper evidence and internal consistency.

## 5) What bundle consistency does not prove

Bundle consistency does not prove:

- semantic correctness of intent
- target contract safety/correctness
- RPC honesty
- successful execution on-chain

It is an integrity check, not a full safety proof.

## 6) Fast confidence workflow

Use pinned verifier scripts and run quick checks on rehearsal bundles.

Suggested calibration drills:

1. Mutation test (should fail): edit one byte in `intent.json`, rerun verifier.
2. Missing file test (should fail): remove `checks.json`, rerun verifier.
3. Fresh bundle test (should pass): regenerate with `bundle.sh`, rerun verifier.

## 7) AIRLOCK rule

If bundles move across OSes, treat AIRLOCK as untrusted input.

Before signing:

- copy bundle from AIRLOCK to local working path
- run `verify_bundle.sh` locally
- refuse signing on any verifier failure

Never store secrets in AIRLOCK.

## 8) Example Evidence Pack

Claim (`VERIFIED`):
Bundle consistency was verified by `ops/tools/verify_bundle.sh` at commit `<GIT_SHA>`.

Reproduce:

```bash
git rev-parse HEAD
NETWORK=sepolia RUN_ID=<RUN_ID> ops/tools/verify_bundle.sh
```

Expected output:

- `Manifest hashes verified`
- `Bundle verified: ...`
- exit code `0`

Stop conditions:

- missing required files
- hash mismatch for any immutable file
- `bundle_hash` mismatch
- commit mismatch (`run.json` vs current checkout)
- lane missing from policy
- approval hash mismatch (if approval exists)

Scope limit:

This does not prove semantic safety, only bundle integrity and consistency.

## 9) Agent refusal rule

When evidence is missing, the agent must answer `UNKNOWN` and provide exact commands to obtain missing proof.

No trust-by-assertion answers.

## 10) Repo linkage

This document is part of the runtime safety model and should be read with:

- `docs/ops-lanes-agent.md`
- `docs/downstream-ops-contract.md`
- `docs/pipeline-reference.md`
