#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
WORK_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cp -R "$TEMPLATE_ROOT/examples/scaffold/." "$WORK_DIR"
cp -R "$TEMPLATE_ROOT/schemas" "$WORK_DIR/schemas"
mkdir -p "$WORK_DIR/policy"
cp "$TEMPLATE_ROOT/policy/sepolia.policy.example.json" "$WORK_DIR/policy/sepolia.policy.example.json"
cp "$TEMPLATE_ROOT/policy/mainnet.policy.example.json" "$WORK_DIR/policy/mainnet.policy.example.json"

cd "$WORK_DIR"
chmod +x ops/tools/*.sh

git init -q
git config user.email "deploy-params-test@example.local"
git config user.name "Deploy Params Test"
git add .
git commit -q -m "init scaffold deploy params tests"

expect_fail() {
  local label="$1"
  shift
  if "$@"; then
    echo "Expected failure but command succeeded: $label" >&2
    exit 1
  fi
  echo "Expected failure observed: $label"
}

make_params() {
  local path="$1"
  cat > "$path" <<'JSON'
{
  "contract_name": "GovModule",
  "constructor_args": {
    "name": "Ops Token",
    "symbol": "OPS",
    "paymentToken": "0x0000000000000000000000000000000000000011",
    "treasury": "0x0000000000000000000000000000000000000022",
    "openTime": 1735689600,
    "startDelay": 3600,
    "pricing": {
      "startPrice": "1000000000000000000",
      "endPrice": "500000000000000000"
    },
    "tokenPerEpoch": "1000",
    "epochSeconds": 86400
  },
  "name": "Ops Token",
  "symbol": "OPS",
  "paymentToken": "0x0000000000000000000000000000000000000011",
  "treasury": "0x0000000000000000000000000000000000000022",
  "openTime": 1735689600,
  "startDelay": 3600,
  "pricing": {
    "startPrice": "1000000000000000000",
    "endPrice": "500000000000000000"
  },
  "tokenPerEpoch": "1000",
  "epochSeconds": 86400
}
JSON
}

write_approval() {
  local bundle_dir="$1"
  BUNDLE_DIR="$bundle_dir" python3 - <<'PY'
import json
import os
from pathlib import Path
bundle = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle / "bundle_manifest.json").read_text())
intent = json.loads((bundle / "intent.json").read_text())
run = json.loads((bundle / "run.json").read_text())
approval = {
    "approved_at": "2026-03-04T00:00:00Z",
    "approver": "test",
    "network": run.get("network", ""),
    "lane": run.get("lane", ""),
    "run_id": run.get("run_id", ""),
    "bundle_hash": manifest.get("bundle_hash", ""),
    "intent_hash": "",
    "deploy_params_sha256": intent.get("deploy_params_sha256", ""),
    "notes": "test approval"
}
(bundle / "approval.json").write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
PY
}

# 1) Missing params file for Sepolia deploy lane must fail at bundle time.
expect_fail "missing deploy params at bundle" env NETWORK=sepolia LANE=deploy RUN_ID=missing-params ops/tools/bundle.sh

# 2) Valid pinned params should pass verify/apply.
PARAMS_FILE="$WORK_DIR/deploy_params.valid.json"
make_params "$PARAMS_FILE"
NETWORK=sepolia LANE=deploy RUN_ID=valid-pinned DEPLOY_PARAMS_FILE="$PARAMS_FILE" ops/tools/bundle.sh
NETWORK=sepolia RUN_ID=valid-pinned ops/tools/verify_bundle.sh
write_approval "$WORK_DIR/bundles/sepolia/valid-pinned"

# 3) External override must fail for apply.
OTHER_PARAMS_FILE="$WORK_DIR/deploy_params.override.json"
make_params "$OTHER_PARAMS_FILE"
expect_fail "external deploy params override" env SIGNING_OS=1 NETWORK=sepolia RUN_ID=valid-pinned DEPLOY_PARAMS_FILE="$OTHER_PARAMS_FILE" ops/tools/apply_bundle.sh

# 4) Apply with bundled params should pass and record params hash.
env SIGNING_OS=1 NETWORK=sepolia RUN_ID=valid-pinned ops/tools/apply_bundle.sh
python3 - <<'PY'
import json
from pathlib import Path

txs = json.loads(Path("bundles/sepolia/valid-pinned/txs.json").read_text())
if not txs.get("deploy_params_sha256"):
    raise SystemExit("txs.json missing deploy_params_sha256")
if not txs.get("deploy_params_file"):
    raise SystemExit("txs.json missing deploy_params_file")
print("Pinned params recorded in txs.json")
PY

# 5) Mutating bundled params after bundle must fail verify.
NETWORK=sepolia LANE=deploy RUN_ID=mutated-params DEPLOY_PARAMS_FILE="$PARAMS_FILE" ops/tools/bundle.sh
python3 - <<'PY'
import json
from pathlib import Path
path = Path("bundles/sepolia/mutated-params/deploy_params.json")
data = json.loads(path.read_text())
data["name"] = "Tampered"
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
expect_fail "mutated bundled params" env NETWORK=sepolia RUN_ID=mutated-params ops/tools/verify_bundle.sh

# 6) Mainnet rehearsal-proof gate remains enforced.
NETWORK=mainnet LANE=deploy RUN_ID=mainnet-proof-check DEPLOY_PARAMS_FILE="$PARAMS_FILE" ops/tools/bundle.sh
NETWORK=mainnet RUN_ID=mainnet-proof-check ops/tools/verify_bundle.sh
write_approval "$WORK_DIR/bundles/mainnet/mainnet-proof-check"
expect_fail "mainnet rehearsal proof gate" env SIGNING_OS=1 NETWORK=mainnet RUN_ID=mainnet-proof-check ops/tools/apply_bundle.sh

echo "deploy_params_gate.sh: PASS"
