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

json_get() {
  local key="$1"
  python3 -c $'import sys, json\nkey=sys.argv[1]\nval=\"\"\nfor line in sys.stdin.read().splitlines():\n    line=line.strip()\n    if not line:\n        continue\n    try:\n        obj=json.loads(line)\n    except Exception:\n        continue\n    if not isinstance(obj, dict):\n        continue\n    if key in obj:\n        val=obj[key]\nprint(val)\n' "$key"
}

class_hash_from_utils() {
  local contract="$1"
  sncast utils class-hash --package multisig_wallet --contract-name "$contract" \
    | awk '/Class Hash:/ {print $3}' \
    | tail -n 1
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
if ! [[ "$CLASS_HASH" =~ ^0x[0-9a-fA-F]+$ ]]; then
  CLASS_HASH=""
fi

if [[ -z "$CLASS_HASH" || "$FORCE_DECLARE" == "1" ]]; then
  DECLARE_JSON=$(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json declare \
    --package multisig_wallet --contract-name ExampleCounter \
    --url "$RPC")

  CLASS_HASH=$(echo "$DECLARE_JSON" | json_get class_hash)
  DECLARE_TX=$(echo "$DECLARE_JSON" | json_get transaction_hash)

  if [[ -z "$CLASS_HASH" ]]; then
    CLASS_HASH=$(class_hash_from_utils ExampleCounter)
  fi

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

ADDRESS=$(echo "$DEPLOY_JSON" | json_get contract_address)
DEPLOY_TX=$(echo "$DEPLOY_JSON" | json_get transaction_hash)

if [[ -z "$ADDRESS" || -z "$DEPLOY_TX" ]]; then
  echo "Failed to parse deploy output." >&2
  echo "$DEPLOY_JSON" >&2
  exit 1
fi

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
