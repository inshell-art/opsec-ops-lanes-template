# Scaffold example (CI bundle + local apply)

This is a **minimal scaffold** you can copy into a business repo to implement the Ops‑lanes flow:

- Remote CI builds/tests and produces a **bundle**.
- Local signing machine verifies/approves/applies the bundle.
- No secrets committed.

> This example assumes a Starknet toolchain (Scarb + Foundry + starkli). Adjust build/test
> and apply commands for your stack.

## Copy into your repo

From inside your business repo:

```
cp -R opsec-ops-lanes-template/examples/scaffold/. .
```

## Configure policy

Copy and edit the policy examples (no secrets):

```
cp opsec-ops-lanes-template/policy/sepolia.policy.example.json ops/policy/sepolia.policy.json
cp opsec-ops-lanes-template/policy/mainnet.policy.example.json ops/policy/mainnet.policy.json
```

## Configure runbooks

Write runbooks in `ops/runbooks/` (deploy, handoff, govern, emergency). Reference the rules in:
- `opsec-ops-lanes-template/docs/ops-lanes-agent.md`
- `opsec-ops-lanes-template/docs/opsec-ops-lanes-signer-map.md`

## CI bundle flow

The example workflow is at:
- `.github/workflows/ops_bundle.yml`

It runs build/test, then creates:
- `bundles/<network>/<run_id>/intent.json`
- `checks.json`, `run.json`, `policy.json`, `bundle_manifest.json`

## Local CD flow (signing OS)

```
make -f ops/Makefile verify  NETWORK=<network> RUN_ID=<run_id>
make -f ops/Makefile approve NETWORK=<network> RUN_ID=<run_id>
make -f ops/Makefile apply   NETWORK=<network> RUN_ID=<run_id>
```

> Apply reads only from the bundle (no manual args). Keystore/account files stay outside the repo.
