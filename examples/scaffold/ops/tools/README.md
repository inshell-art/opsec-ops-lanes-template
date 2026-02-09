# Ops tools (stubs)

These scripts are placeholders. Replace them with your repo's real commands.

Expected behavior by script:
- `plan.sh` creates intents for lane1.
- `check.sh` runs required checks and writes checks artifacts.
- `approve.sh` records human approval tied to the intent hash.
- `apply.sh` executes the approved intent in signing context only.

All write operations must use keystore mode only. Do not use accounts-file signing.

Optional bundle tooling (reference implementations):
- `bundle.sh`, `verify_bundle.sh`, `approve_bundle.sh`, `apply_bundle.sh`

Review and adapt these scripts before use.
