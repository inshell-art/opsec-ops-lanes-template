# Policy files

Copy example policies from the template repo and edit the copies:
- `policy/sepolia.policy.example.json` -> `ops/policy/sepolia.policy.json`
- `policy/mainnet.policy.example.json` -> `ops/policy/mainnet.policy.json`

Keep secrets out of git. Only reference local keystore paths via env vars.
