# Policy files

Copy example policies from the template repo and edit the copies:
- `ops/policy/lane.sepolia.example.json` -> `ops/policy/lane.sepolia.json`
- `ops/policy/lane.mainnet.example.json` -> `ops/policy/lane.mainnet.json`

Keep secrets out of git. Only reference local keystore paths via env vars.

Mainnet lanes default to `requires_sepolia_rehearsal_proof: true`. Only set it to false if you are consciously overriding the gate.
For EVM lanes, set realistic EIP-1559 bounds in each lane's `fee_policy`.
