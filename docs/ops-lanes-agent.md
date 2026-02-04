# Ops Lanes (Agent) — operator rules for intent‑gated onchain ops (keystore mode)

This document defines **Ops Lanes** and the split of responsibilities between an **agent (automation)** and **you (human approver)** when operating on **Sepolia/Mainnet** using:

- **CLI signing in keystore mode** (starkli-style account.json + encrypted keystore.json)
- optional **Ledger hardware signer** (as a signer *type*, not a wallet UI)
- **NO accounts-file signing mode**
- **NO Argent/Ready wallet signing surfaces** (except HOT-user browsing wallet; see OPSEC table)

This doc is designed to **implement** the OPSEC compartment model in `opsec-ops-lanes-signer-map.md` (PUBLIC/OPS/HOT/DEPLOYER/ADMIN/TREASURY/WATCH + Phase A/B).

> **Principle:** Humans approve **meaning**. Machines verify **reality**.

---

## 0) Vocabulary

- **Lane**: a permission + process boundary defined by:
  - **Signer(s)** (which account/multisig is allowed)
  - **Allowed operations** (what actions are permitted)
  - **Required checks** (what must be proven true before execution)
  - **Approval rules** (how/when a human can authorize execution)
  - **OPSEC context** (which compartment/OS is allowed to run it)

- **Intent**: canonical, machine-readable description of one operation to execute (usually one tx).
- **Checks**: machine-generated proof that an intent is safe/consistent (preconditions, identity, simulation).
- **Approval**: human “go” tied to a specific intent hash (approves meaning, not hex).
- **Apply**: execution that must use only the approved intent (no manual args).

---

## 1) Golden rules (Sepolia/Mainnet)

1) **No manual args at apply time.**  
   `apply` must read everything from `intent.json` and artifacts.

2) **Keystore mode only for signing.**  
   - For any lane that writes to chain (Lane 2+), the agent must refuse if it detects accounts-file signing mode.
   - Secrets must never be stored in repo files.

3) **No “paste into invoke.”**  
   If you must paste an address/tx hash, paste only into a dedicated `inputs/*` script that:
   - validates format
   - verifies on-chain identity (class hash / interface)
   - persists into `manual_inputs.json`

4) **Network-scoped artifacts only.**  
   Artifacts live under `artifacts/<network>/current/*` (or archived `runs/<run_id>`). Never mix.

5) **Identity checks are mandatory.**  
   Every write must verify:
   - chain id matches lane config
   - target code identity matches expected (class hash / compiled class hash policy)
   - signer matches lane signer allowlist

6) **Plan + Check + Approve + Apply are logically distinct** (even if run in one command).  
   Apply refuses unless the exact intent hash is:
   - checked (`checks.json: pass`)
   - approved (`approval.json` matches intent hash)

7) **Postconditions are proof.**  
   “Tx succeeded” isn’t enough. Every write produces:
   - `snapshots/post_*.json`
   - postcondition checks (expected state matches)

8) **No secrets in logs.**  
   Agent must never print:
   - private keys
   - keystore contents
   - keystore passwords
   - seed phrases
   - full RPC URLs if they embed credentials

---

## 2) OPSEC coupling (where each lane is allowed to run)

This section ties lanes to the OPSEC compartments in `opsec-ops-lanes-signer-map.md`.

### Phase A (Sepolia rehearsal)
- **Lane 0/1 (read/plan)**: may run anywhere (PUBLIC/OPS/WATCH), but still no secrets.
- **Lane 2+ (writes)**: run only in the **terminal signing context**:
  - **DEPLOYER** (for deploy lane writes)
  - **ADMIN_MAC / TREASURY_MAC** (for multisig operations)
  - No browsing while executing.

### Phase B (Mainnet)
- **Lane 0/1**: anywhere (watch-only).
- **Lane 2+**: run only inside **SIGNING_OS** (external SSD) with minimal apps.

---

## 3) Standard artifacts (minimum set)

- `run.json` — run id, git commit, network, rpc hint, timestamps
- `addresses.json` — labeled addresses (PATH_CORE, MULTISIG_GOV, …)
- `intents/<name>.intent.json` — one intent per tx (canonical bytes + semantic args)
- `checks/<name>.checks.json` — machine proof: identity + preconditions + simulation
- `approvals/<name>.approval.json` — human go/no-go tied to intent hash
- `txs.json` — tx hashes per step
- `snapshots/*.json` — baseline + post-* readbacks
- `checks/postconditions.json` (or per-step) — pass/fail + evidence pointers

---

## 4) Agent vs Human (who does what)

### Agent responsibilities (automation)
The agent must be able to truthfully say: **“All required checks passed for this exact intent.”**

**Must do**
- Resolve labels → addresses from artifacts (never from memory).
- Generate `intent.json` deterministically (args + ABI → calldata).
- Run required checks and write `checks.json`:
  - chain id, rpc allowlist
  - signer address allowlist
  - target class hash / identity
  - preconditions (ownership/roles/config)
  - simulation/fee estimate where supported
- Enforce lane policy: refuse operations outside allowed list.
- Ask the human for **semantic approval** (not hex review).
- On apply:
  - re-load intent from disk
  - re-check critical invariants just-in-time (chain id, signer, identity)
  - execute the tx
  - persist `txs.json` + snapshots + postconditions
- Produce a short, human-readable statement for approval (labels not raw addresses).

**Must not**
- Store or print secrets.
- “Guess” inputs interactively.
- Proceed on partial checks.
- Accept raw addresses at apply time (unless it’s a read-only operation).

### Human responsibilities (you, the approver)
Your job is to approve **meaning**, and to ensure the signer context is the correct one.

**Must do**
- Confirm the **lane** you are authorizing (Deploy / Handoff / Govern / Emergency).
- Confirm the **network** (Sepolia vs Mainnet).
- Confirm the **semantic statement** matches your intent:
  - “Deploy OZ Multisig with signers A,B and quorum 2”
  - “Transfer ownership of PATH_CORE → GOV_MSIG”
  - “Execute proposal <label> via GOV_MSIG”
- Confirm signing context:
  - you are in the correct OPSEC compartment (DEPLOYER vs ADMIN vs TREASURY)
  - you are using the intended keystore/account.json pair
  - if using Ledger: correct app open; verify on-device prompts

**Must not**
- Try to validate calldata/addresses by eyeballing (that’s what `checks.json` is for).
- Approve on Mainnet if lane policy says “requires Sepolia proof” and it’s missing.

---

## 5) Ops Lanes (tight definition)

Each lane is defined by: **Signer(s), Allowed ops, Required checks, Approval rule, OPSEC context**.

### Lane 0 — Observe (read-only)
- **Signer:** none (or any)
- **Ops:** reads, snapshots, diffs, simulate/estimate (no state changes)
- **Checks:** chain id & identity checks recommended
- **Approval:** none
- **OPSEC context:** WATCH / PUBLIC / OPS allowed

### Lane 1 — Build & Plan (no chain writes)
- **Signer:** none
- **Ops:** compile/build, derive calldata, produce intents, run read/sim checks
- **Checks:** determinism + intent hashing; “bundle hash” creation
- **Approval:** none
- **OPSEC context:** OPS (preferred) or PUBLIC; never load keystores

### Lane 2 — Deploy (create primitives)
- **Signer:** deployer keystore signer only (**DEPLOYER** compartment)
- **Ops:** declare/deploy, minimal bootstrap config required to make contracts exist
- **Checks (required):**
  - chain id / rpc allowlist
  - class hash / compiled class hash policy
  - expected address derivation (if used)
  - post-deploy snapshot
- **Approval:** required (bundle-level or per-intent depending on risk)
- **OPSEC context:** DEPLOYER (Phase A) / SIGNING_OS (Phase B)

### Lane 3 — Handoff & Lockdown (remove deployer power)
- **Signer:** deployer and/or governance per design; prefer governance as final authority
- **Ops:** set roles, transfer ownership to multisig/governance, revoke deployer privileges
- **Checks (required):**
  - current ownership/roles match expected
  - postconditions: deployer cannot mutate protected state
- **Approval:** required (high-safety)
- **OPSEC context:** DEPLOYER + GOV signers (Phase A terminal / Phase B SIGNING_OS)

### Lane 4 — Operate (routine actions within bounds)
- **Signer:** operator role accounts (NOT deployer; NOT HOT user wallet)
- **Ops:** routine parameter updates within bounded policy
- **Checks (required):**
  - role membership proof
  - bounds/rate limits
  - postconditions per operation
- **Approval:** required (often per-intent)
- **OPSEC context:** dedicated operator compartment (if you introduce it); otherwise treat as GOV lane

> Note: HOT (Braavos) is for “normal user actions” and is not an Ops Lane signer.

### Lane 5 — Govern (high-power changes)
- **Signer:** GOV_MSIG / TREASURY_MSIG signers only (2-of-2 confirmations)
- **Ops:** upgrades, sensitive config, treasury moves, long-term parameter changes
- **Checks (required):**
  - strict identity checks + simulation
  - pre/post state proofs
  - multisig quorum rules satisfied
- **Approval:** via multisig confirmations (plus optional “proposal approval” artifact)
- **OPSEC context:** ADMIN_MAC / TREASURY_MAC (Phase A) or SIGNING_OS (Phase B)

### Lane 6 — Emergency (break-glass)
- **Signer:** emergency key/multisig (separate from routine), if you add one later
- **Ops:** pause/freeze, disable components, stop-the-bleed actions
- **Checks (required):**
  - tight allowlist of actions
  - mandatory immediate postcondition snapshot
- **Approval:** required, with extra friction (typed phrase + short timeout)
- **OPSEC context:** SIGNING_OS only

---

## 6) Approval mechanics (semantic, not hex)

### Preferred: bundle-per-lane approval
To avoid “approval fatigue”, approve once per **lane bundle**:
- Deploy lane bundle (N tx)
- Handoff lane bundle (M tx)
- Operator action bundle (usually 1 tx)
- Governance proposal bundle

Agent executes each intent only if:
- `checks.json.status == pass`
- `approval.json` exists for the bundle hash (or the intent hash)
- per-intent risk gates satisfied

### Approval phrases (no copy/paste)
Use typed phrases that include lane + network:
- `APPROVE SEPOLIA DEPLOY`
- `APPROVE SEPOLIA HANDOFF`
- `APPROVE SEPOLIA GOVERN`
- `APPROVE MAINNET GOVERN`
- `APPROVE MAINNET EMERGENCY`

Optionally require a short “context token” the agent prints (e.g., last 4 chars of intent hash) to avoid autopilot.

---

## 7) Keystore / Ledger signing rules (what you actually check)

### When signing via keystore mode
Before you sign/broadcast a write tx:

1) **Lane + network**: confirm lane policy matches the step.
2) **RPC allowlist**: ensure the RPC used matches the lane config.
3) **Signer identity**: ensure the derived signer address matches the lane allowlist.
4) **Intent hash**: ensure approval is for the exact intent hash.

### When signing via Ledger (if used)
- Treat Ledger signing as “confirming a hash,” not a human-readable tx (current Starknet Ledger app limitations vary).
- This increases reliance on the agent’s `checks.json` + semantic statement.
- Always verify you are in the correct OPSEC context (ADMIN vs TREASURY).

---

## 8) Remote CI + Local CD (recommended shape)

### Remote CI (no secrets)
- Build/test
- Produce release bundle (compiled artifacts + hashes + policies)
- Generate intents + checks for Sepolia/Mainnet (read/sim only)
- Upload artifacts (bundle + intents + checks)

### Local CD (secrets stay local)
- Download the CI bundle
- Re-run critical checks (defense-in-depth)
- Ask for semantic approval
- Apply intents with keystore-mode signer (and Ledger if applicable)
- Write txs + snapshots + postconditions
- Archive `artifacts/<net>/runs/<run_id>/`

---

## 9) Stop conditions (when the agent must refuse)

Agent must abort if any of these occur:
- chain id mismatch
- rpc not allowlisted
- signer not allowed for lane
- target identity mismatch (class hash / compiled class hash / interface)
- preconditions fail (ownership/roles/config not as expected)
- simulation fails / revert predicted
- fee estimate above threshold (unless elevated approval present)
- intent hash doesn’t match checks/approval
- postconditions fail after tx

---

## Appendix A — OPSEC × Ops-Lanes Signer Map (template)

Put real addresses only into `artifacts/<network>/current/addresses.json`.
Keep keystore/account.json paths **outside the repo** and reference them via local env vars.

Example labels:
- `DEPLOYER_SW_A`
- `GOV_SW_A`
- `GOV_HW_B`
- `TREASURY_SW_A`
- `TREASURY_HW_B`
- `GOV_MSIG`
- `TREASURY_MSIG`

