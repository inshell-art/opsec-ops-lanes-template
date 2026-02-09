# Integration guide

This template is designed to be *imported* into one or more business repos without copying secrets.

See also: `codex/BUSINESS_REPO_ADOPTION.md` for a short adoption checklist.

## Scaffold example

See `examples/scaffold/` for a minimal downstream repo layout and CI rehearsal stub (plan + check only).
An optional bundle workflow example is included for teams that want deterministic bundles.

## Recommended structure

```
business-repo/
  ops-template/                 # this repo as a submodule (or subtree)
    docs/
    policy/
    schemas/
  ops/
    policy/
      sepolia.policy.json       # your real policy (no secrets)
      mainnet.policy.json
    runbooks/
      lane2-deploy.md
      lane3-handoff.md
      lane5-govern.md
  artifacts/
    sepolia/current/            # generated artifacts (safe to commit if redacted)
    sepolia/runs/<run_id>/
    mainnet/current/
  .env.example                  # env vars with local paths (no secrets)
  .gitignore
```

## Keeping secrets out of the repo

Use *local-only* locations for keystores and account.json:

Example (operator machine):
```
~/.opsec/
  sepolia/
    deploy_sw_a/{account.json,keystore.json}
    gov_sw_a/{account.json,keystore.json}
    treasury_sw_a/{account.json,keystore.json}
  mainnet/
    ...
```

Only reference these via local env vars or local config files that are gitignored.

## Submodule commands (example)

```bash
git submodule add <REMOTE_URL> ops-template
git commit -m "Add ops-template"
```

To update later:
```bash
git submodule update --remote --merge
git commit -am "Update ops-template"
```

## What to customize

1) Copy an example policy and edit it:
- `ops-template/policy/sepolia.policy.example.json` → `ops/policy/sepolia.policy.json`
- `ops-template/policy/mainnet.policy.example.json` → `ops/policy/mainnet.policy.json`

2) Define your signer aliases (addresses) in `artifacts/<net>/current/addresses.json`.

3) Keep runbooks in `ops/runbooks/`, but reference the lane rules in:
- `ops-template/docs/ops-lanes-agent.md`
- `ops-template/docs/opsec-ops-lanes-signer-map.md`
