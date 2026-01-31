#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

NETWORK="${NETWORK:-devnet}"
RPC="${RPC:-${RPC_URL:-}}"
ACCOUNT="${ACCOUNT:-}"
ACCOUNTS_FILE="${ACCOUNTS_FILE:-}"
OUT_DIR="${OUT_DIR:-}"
INITIAL_VALUE="${INITIAL_VALUE:-0}"
FORCE_DECLARE="${FORCE_DECLARE:-0}"

usage() {
  cat <<EOF
Usage: deploy_example_counter.sh [--initial N]

Env vars:
  NETWORK, RPC, ACCOUNT, ACCOUNTS_FILE, OUT_DIR, INITIAL_VALUE, FORCE_DECLARE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --initial) INITIAL_VALUE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$RPC" || -z "$ACCOUNT" || -z "$ACCOUNTS_FILE" ]]; then
  echo "Missing RPC, ACCOUNT, or ACCOUNTS_FILE env vars." >&2
  usage
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$ROOT_DIR/artifacts/$NETWORK"
fi
mkdir -p "$OUT_DIR"

scarb build

CLASS_FILE="$OUT_DIR/counter.class.json"
CLASS_HASH=""
DECLARE_TX=""

if [[ -f "$CLASS_FILE" && "$FORCE_DECLARE" != "1" ]]; then
  CLASS_HASH=$(python3 - <<PY
import json
from pathlib import Path
p = Path("$CLASS_FILE")
try:
    data = json.loads(p.read_text())
    print(data.get("class_hash", ""))
except Exception:
    print("")
PY
)
fi

if [[ -z "$CLASS_HASH" || "$FORCE_DECLARE" == "1" ]]; then
  DECLARE_JSON=$(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json declare \
    --package multisig_wallet --contract-name ExampleCounter \
    --url "$RPC")

  CLASS_HASH=$(echo "$DECLARE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["class_hash"])')
  DECLARE_TX=$(echo "$DECLARE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["transaction_hash"])')

  ROOT_DIR="$ROOT_DIR" NETWORK="$NETWORK" CLASS_HASH="$CLASS_HASH" DECLARE_TX="$DECLARE_TX" CLASS_FILE="$CLASS_FILE" \
  python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

class_file = Path(os.environ["CLASS_FILE"])
class_file.parent.mkdir(parents=True, exist_ok=True)

payload = {
    "network": os.environ["NETWORK"],
    "contract": "ExampleCounter",
    "class_hash": os.environ["CLASS_HASH"],
    "declare_tx": os.environ["DECLARE_TX"],
    "declared_at": datetime.now(timezone.utc).isoformat(),
}
class_file.write_text(json.dumps(payload, indent=2) + "\n")
PY
fi

DEPLOY_JSON=$(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json deploy \
  --class-hash "$CLASS_HASH" --url "$RPC" \
  --constructor-calldata "$INITIAL_VALUE")

ADDRESS=$(echo "$DEPLOY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["contract_address"])')
DEPLOY_TX=$(echo "$DEPLOY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["transaction_hash"])')

OUT_FILE="$OUT_DIR/counter.json"
ROOT_DIR="$ROOT_DIR" NETWORK="$NETWORK" CLASS_HASH="$CLASS_HASH" ADDRESS="$ADDRESS" DEPLOY_TX="$DEPLOY_TX" \
  INITIAL_VALUE="$INITIAL_VALUE" OUT_FILE="$OUT_FILE" \
  python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

payload = {
    "network": os.environ["NETWORK"],
    "contract": "ExampleCounter",
    "address": os.environ["ADDRESS"],
    "deploy_tx": os.environ["DEPLOY_TX"],
    "class_hash": os.environ["CLASS_HASH"],
    "constructor": {
        "initial": int(os.environ["INITIAL_VALUE"]),
    },
    "deployed_at": datetime.now(timezone.utc).isoformat(),
}

out_file = Path(os.environ["OUT_FILE"])
out_file.write_text(json.dumps(payload, indent=2) + "\n")
PY

cat <<REPORT
Deployed ExampleCounter
- address: $ADDRESS
- deploy_tx: $DEPLOY_TX
- class_hash: $CLASS_HASH
REPORT
