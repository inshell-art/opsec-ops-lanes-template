# OPSEC × Ops-lanes Signer Map (Template) — compartments + signer aliases + two-phase rollout

This document is the **single source of truth** for:

- OPSEC compartments (PUBLIC / OPS / HOT / DEPLOYER / ADMIN / TREASURY / WATCH)
- a lane-agnostic **signer alias** scheme (so your runbooks + agents never confuse signers)
- a two-phase rollout (Sepolia rehearsal → Mainnet)

It is designed to pair with: `ops-lanes-agent.md`.

It is written as a **guideline table** you can follow during rehearsal (devnet/Sepolia) and later mainnet operations.

---

## 0) Core mental model

**Compartmentation beats cleverness.**

- Put different kinds of actions into different “places” (browser/profile/OS/device).
- Keep “eyes” (monitoring) separate from “hands” (signing).
- Prefer **scripted ops + runbook/workbook discipline** over ad-hoc clicking.

---

## 1) Roles & vocabulary

- **PUBLIC**: your open identity + browsing + open-source presence.
- **OPS**: infrastructure and billing consoles (Cloudflare, registrar). No wallets here.
- **HOT**: low-stakes wallet used like a normal user (tiny funds, disposable).
- **ADMIN**: protocol authority (ownership/roles/wiring); high-impact operations.
- **TREASURY**: custody of value; rare outflows.
- **DEPLOYER**: tool identity used only to declare/deploy; must end with **zero privilege**.
- **WATCH**: watch-only monitoring (explorer watchlists, address book).

---

## 1.1) Signer aliases (lane-agnostic)

You do **not** need lane numbers inside signer aliases.

- Aliases encode **network + power domain + signer type** and stay stable.
- Lane permissions live in your lane policy (agent-enforced allowlists), not in names.

### Alias scheme

`<NET>_<DOMAIN>_<TYPE>_<A/B>`

- `NET`: `SEPOLIA` or `MAINNET`
- `DOMAIN`: `DEPLOY`, `GOV`, `TREASURY`, `HOT_USER`
- `TYPE`: `SW` (software keystore) or `HW` (Ledger)
- `A/B`: signer index for quorum setups (2-of-2: A + B)

### Recommended alias set

**Sepolia**
- `SEPOLIA_DEPLOY_SW_A`
- `SEPOLIA_GOV_SW_A`
- `SEPOLIA_GOV_HW_B`
- `SEPOLIA_TREASURY_SW_A`
- `SEPOLIA_TREASURY_HW_B`
- `SEPOLIA_GOV_MSIG`
- `SEPOLIA_TREASURY_MSIG`
- `SEPOLIA_HOT_USER_BRAAVOS` (never used for lanes)

**Mainnet**
- `MAINNET_DEPLOY_SW_A`
- `MAINNET_GOV_SW_A`
- `MAINNET_GOV_HW_B`
- `MAINNET_TREASURY_SW_A`
- `MAINNET_TREASURY_HW_B`
- `MAINNET_GOV_MSIG`
- `MAINNET_TREASURY_MSIG`
- `MAINNET_HOT_USER_BRAAVOS` (never used for lanes)

### Role → alias mapping

| OPSEC role | Sepolia alias | Mainnet alias |
|---|---|---|
| DEPLOYER | `SEPOLIA_DEPLOY_SW_A` | `MAINNET_DEPLOY_SW_A` |
| ADMIN_MAC | `SEPOLIA_GOV_SW_A` | `MAINNET_GOV_SW_A` |
| LEDGER_ADMIN | `SEPOLIA_GOV_HW_B` | `MAINNET_GOV_HW_B` |
| TREASURY_MAC | `SEPOLIA_TREASURY_SW_A` | `MAINNET_TREASURY_SW_A` |
| LEDGER_TREASURY | `SEPOLIA_TREASURY_HW_B` | `MAINNET_TREASURY_HW_B` |
| ADMIN_MSIG | `SEPOLIA_GOV_MSIG` | `MAINNET_GOV_MSIG` |
| TREASURY_MSIG | `SEPOLIA_TREASURY_MSIG` | `MAINNET_TREASURY_MSIG` |
| HOT | `SEPOLIA_HOT_USER_BRAAVOS` | `MAINNET_HOT_USER_BRAAVOS` |

---

## 1.2) Default lane allowlists (starter)

Treat these as sane defaults; your agent enforces them via allowlists.

- **Lane 0/1 (Observe/Plan)**: no signers required (watch-only). Never load keystores.
- **Lane 2 (Deploy)**: allow `*_DEPLOY_SW_A` only.
- **Lane 3 (Handoff/Lockdown)**:
  - allow `*_DEPLOY_SW_A` for the “grant/transfer from deployer” steps
  - allow `*_GOV_*` for the “accept/execute via governance” steps
- **Lane 5 (Govern)**:
  - governance changes: allow `*_GOV_SW_A` + `*_GOV_HW_B` (2-of-2 via `*_GOV_MSIG`)
  - treasury changes: allow `*_TREASURY_SW_A` + `*_TREASURY_HW_B` (2-of-2 via `*_TREASURY_MSIG`)
- **HOT user actions**: never part of lanes; never allow `*_HOT_USER_*` in any lane.

## 2) Phase split

### Phase A — Sepolia (rehearsal, low stakes)
Goal: speed + learning. Accept reduced isolation, but keep role boundaries intact.

- ADMIN/TREASURY use **CLI keystores with different seeds** on the same machine/user.
- Ledger is used as the second factor for 2-of-2 multisigs (recommended).

### Phase B — Mainnet (high stakes)
Goal: reduce attack surface and human error.

- Use a **Signing OS** on an **external SSD** for admin/treasury signing.
- Daily OS stays for browsing/dev/ops, not for privileged signing.

---

## 3) Structure table — Phase A (Sepolia)

| Role | Where (device / OS / browser) | Wallet / signer | Secrets location | Primary actions | Hard boundaries (never do) |
|---|---|---|---|---|---|
| **PUBLIC** | Daily macOS → Chrome “Public” profile | None | None | Browse, OSS, docs, socials, reading | No wallets/extensions; no infra billing consoles; don’t handle keys here |
| **OPS** | Daily macOS → Firefox “Ops” profile (local-only) | None | Ops email 2FA secrets in KeePassXC | Cloudflare Pages settings, DNS, registrar, billing | No wallet extensions; no signing; avoid mixing public identity sessions |
| **HOT** | Daily macOS → separate browser profile (not Public/Ops) | **Braavos** (extension) | HOT seed on paper (disposable) + KeePassXC for passwords | Normal user actions: mint/test with tiny funds | Never hold protocol roles/ownership; never store large funds; rotate if suspicious |
| **ADMIN_MAC** | Daily macOS → terminal (same OS user allowed on Sepolia) | CLI keystore signer | `ADMIN_MAC` keystore (encrypted) + password in KeePassXC | Sign multisig ops for admin (submit/confirm/execute) | Don’t browse; don’t install random tools; don’t reuse treasury keystore |
| **TREASURY_MAC** | Daily macOS → terminal (same OS user allowed on Sepolia) | CLI keystore signer | `TREASURY_MAC` keystore (encrypted) + password in KeePassXC | Sign multisig ops for treasury (submit/confirm/execute) | Don’t browse; never reuse ADMIN keystore; keep funds small on Sepolia |
| **LEDGER_ADMIN** | Ledger device | Ledger signer account (admin) | Ledger recovery phrase on metal | Second factor for **ADMIN_MSIG** | Don’t share this key with HOT; verify destination + calldata before approving |
| **LEDGER_TREASURY** | Ledger device | Ledger signer account (treasury) | Ledger recovery phrase on metal | Second factor for **TREASURY_MSIG** | Same: verify carefully; treasury outflows are rare and deliberate |
| **ADMIN_MSIG** | On-chain contract (OZ multisig) | 2-of-2: `ADMIN_MAC` + `LEDGER_ADMIN` | N/A | Holds protocol sovereignty | Should be the only admin/owner/role-holder (see mapping below) |
| **TREASURY_MSIG** | On-chain contract (OZ multisig) | 2-of-2: `TREASURY_MAC` + `LEDGER_TREASURY` | N/A | Custody and value movement | Kept separate from ADMIN_MSIG to limit blast radius |
| **DEPLOYER** | Daily macOS → terminal | CLI keystore signer | `DEPLOYER` keystore (encrypted) + password in KeePassXC | Declare + deploy only | Must transfer ownership/roles to ADMIN_MSIG then end with **zero privilege** |
| **WATCH** | Any environment (including Public/Ops) | None | None | Explorer watchlists, address book, alerts | Watch-only: do not sign from monitoring contexts |

### Admin power mapping (what ADMIN_MSIG should control)
After handoff:
- **PathNFT**: holder of `DEFAULT_ADMIN_ROLE`
- **PathMinter**: holder of `DEFAULT_ADMIN_ROLE`
- **PathMinterAdapter**: `owner`

System roles remain system-owned:
- **PathNFT `MINTER_ROLE`** → PathMinter contract
- **PathMinter `SALES_ROLE`** → Adapter (or your sales pipeline contract)

---

## 4) Structure table — Phase B (Mainnet)

| Role | Where (device / OS / browser) | Wallet / signer | Secrets location | Primary actions | Hard boundaries (never do) |
|---|---|---|---|---|---|
| **PUBLIC** | Daily macOS → Chrome “Public” | None | None | Browse, OSS, socials | No wallets/extensions; no infra consoles |
| **OPS** | Daily macOS → Firefox “Ops” | None | Ops email 2FA secrets in KeePassXC | Cloudflare/registrar/DNS/billing | No wallets; don’t sign; don’t mix public identity sessions |
| **HOT** | Daily macOS → separate browser profile | Braavos extension | HOT seed on paper (disposable) | Normal user actions with tiny funds | Never admin; never treasury |
| **SIGNING_OS** | **External SSD macOS** (boot only when signing) | CLI + Ledger | SSD encrypted (FileVault), minimal apps | The only place where admin/treasury keystores live and are used | No browsing; no email; no random installs; update carefully |
| **ADMIN_MAC** | SIGNING_OS terminal | CLI keystore signer | admin keystore + password in KeePassXC (stored in Signing OS) | Admin multisig signing | Don’t co-mingle with treasury; verify intent |
| **TREASURY_MAC** | SIGNING_OS terminal | CLI keystore signer | treasury keystore + password in KeePassXC (Signing OS) | Treasury multisig signing | Outflows are rare; require deliberate runbook checks |
| **LEDGER_ADMIN** | Ledger device | Ledger signer account (admin) | Ledger recovery phrase on metal | Admin second factor | Verify on-device before approving |
| **LEDGER_TREASURY** | Ledger device | Ledger signer account (treasury) | Ledger recovery phrase on metal | Treasury second factor | Same; rare outflows |
| **ADMIN_MSIG** | On-chain OZ multisig instance | 2-of-2 | N/A | Own protocol authority | Sole admin/owner/role-holder |
| **TREASURY_MSIG** | On-chain OZ multisig instance | 2-of-2 | N/A | Custody | Separate from admin |
| **DEPLOYER** | SIGNING_OS terminal (or separate deploy-only OS) | CLI keystore signer | deployer keystore + password | Declare + deploy only | Must handoff and end with zero privilege |
| **WATCH** | Anywhere | None | None | Monitoring | Watch-only |

---

## 5) Key storage policy (simple, strict)

- **Ledger recovery phrase**: metal backup, stored safely and separately from devices.
- **ADMIN/TREASURY keystores**: encrypted files; passwords in KeePassXC.
- **HOT seed**: paper is sufficient (disposable); rotate freely.
- Never store mnemonics/private keys in:
  - repo files
  - screenshots
  - chat logs
  - cloud notes
  - shell history

---

## 6) Secrets-out-of-repo rules (Codex + CI safety)

- `.env` and keystores live **outside** the git repo or are gitignored.
- Cloudflare Pages uses **Git integration** (CF pulls and builds); avoid putting CF deploy tokens into GitHub Actions secrets.
- Run gitleaks/secret scan before pushing public repos.
- Prefer committed `*.example` templates; keep real artifacts and run logs untracked.

---

## 7) Rehearsal discipline (the “boring ops” standard)

### Scripts (automation)
- Generate exact calldata, salts, tx ids.
- Write artifacts (addresses, tx hashes, outputs).
- Print an **intent summary** before every invoke.

### Runbook (safety)
- Preflight checks: chain, RPC, accounts funded, correct addresses.
- Stop-and-verify: target contract, selector, calldata meaning, expected effect.
- Recovery steps: what to retry vs what to stop and investigate.

### Workbook (evidence)
- Step-by-step checklist.
- Fill in: class hash, addresses, tx hashes, observed outputs.
- Compare runs to catch drift.

### Artifacts (truth)
- addresses.json / txs.json / metadata snapshots / SVG outputs.
- Environment-scoped (devnet/sepolia/mainnet).
- Avoid retyping by reading artifacts in later steps.

---

## 8) Minimum “never” list

- Never do privileged signing from PUBLIC or OPS contexts.
- Never let HOT wallet hold admin roles or meaningful funds.
- Never keep admin/treasury secrets in the repo or CI logs.
- Never sign a Ledger prompt without verifying target + intent.
- Never mix browsing and signing in the Mainnet Signing OS.

