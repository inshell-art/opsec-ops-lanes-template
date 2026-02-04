# Codex guide — adopting the template inside a business repo

This file is intended for use inside a business repo that wants to adhere to the template rules.

## Add template as submodule
```bash
git submodule add <REMOTE_URL_OF_TEMPLATE> ops-template
git commit -m "Add ops-template submodule"
```

## Create instance directories
```bash
mkdir -p ops/policy ops/runbooks artifacts/sepolia/current artifacts/mainnet/current
```

## Copy example policies (edit placeholders)
```bash
cp ops-template/policy/sepolia.policy.example.json ops/policy/sepolia.policy.json
cp ops-template/policy/mainnet.policy.example.json ops/policy/mainnet.policy.json
```

## Keep secrets out-of-repo
Store keystore/account.json files outside the repo and reference them via env vars (gitignored).
