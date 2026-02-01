#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

NETWORK="${NETWORK:-devnet}"
RPC="${RPC:-${RPC_URL:-}}"
ACCOUNT="${ACCOUNT:-}"
ACCOUNTS_FILE="${ACCOUNTS_FILE:-}"
OUT_DIR="${OUT_DIR:-}"
QUORUM="${QUORUM:-2}"
LABEL="${MULTISIG_LABEL:-primary}"
SIGNERS_ARG="${SIGNERS:-}"
FORCE_DECLARE="${FORCE_DECLARE:-0}"

usage() {
  cat <<EOF
Usage: deploy_multisig.sh [--label <name>] [--quorum N] [--signers addr1,addr2]

Env vars:
  NETWORK, RPC, ACCOUNT, ACCOUNTS_FILE, OUT_DIR, QUORUM
  SIGNERS (comma separated addresses)
  MULTISIG_LABEL (default label if --label not provided)
  FORCE_DECLARE=1 to redeclare even if class_hash exists

Notes:
  Run this script multiple times with different --label values to deploy
  multiple multisig instances.
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
    --label) LABEL="$2"; shift 2;;
    --quorum) QUORUM="$2"; shift 2;;
    --signers) SIGNERS_ARG="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$RPC" || -z "$ACCOUNT" || -z "$ACCOUNTS_FILE" ]]; then
  echo "Missing RPC, ACCOUNT, or ACCOUNTS_FILE env vars." >&2
  usage
  exit 1
fi

if [[ -z "$SIGNERS_ARG" ]]; then
  echo "Missing SIGNERS env var or --signers argument." >&2
  usage
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$ROOT_DIR/artifacts/$NETWORK"
fi
mkdir -p "$OUT_DIR"

# Build
scarb build

CLASS_FILE="$OUT_DIR/multisig.class.json"
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
  DECLARE_JSON=$(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json declare     --package multisig_wallet --contract-name MultisigWallet     --url "$RPC")

  CLASS_HASH=$(echo "$DECLARE_JSON" | json_get class_hash)
  DECLARE_TX=$(echo "$DECLARE_JSON" | json_get transaction_hash)

  if [[ -z "$CLASS_HASH" ]]; then
    CLASS_HASH=$(class_hash_from_utils MultisigWallet)
  fi

  ROOT_DIR="$ROOT_DIR" NETWORK="$NETWORK" CLASS_HASH="$CLASS_HASH" DECLARE_TX="$DECLARE_TX" CLASS_FILE="$CLASS_FILE"   python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

class_file = Path(os.environ["CLASS_FILE"])
class_file.parent.mkdir(parents=True, exist_ok=True)

payload = {
    "network": os.environ["NETWORK"],
    "contract": "MultisigWallet",
    "class_hash": os.environ["CLASS_HASH"],
    "declare_tx": os.environ["DECLARE_TX"],
    "declared_at": datetime.now(timezone.utc).isoformat(),
}
class_file.write_text(json.dumps(payload, indent=2) + "\n")
PY
fi

label_deploy() {
  local label="$1"
  local raw_signers="$2"
  local -a signers
  IFS=',' read -r -a signers <<< "$raw_signers"
  local count="${#signers[@]}"
  if [[ "$count" -lt 1 ]]; then
    echo "No signers for label: $label" >&2
    exit 1
  fi
  if ! [[ "$QUORUM" =~ ^[0-9]+$ ]]; then
    echo "Invalid QUORUM: $QUORUM" >&2
    exit 1
  fi
  if (( QUORUM < 1 || QUORUM > count )); then
    echo "Invalid QUORUM: $QUORUM (signers count: $count)" >&2
    exit 1
  fi
  local salt
  salt=$("$ROOT_DIR/scripts/salt.sh")

  local deploy_json
  deploy_json=$(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json deploy     --class-hash "$CLASS_HASH" --url "$RPC" --salt "$salt"     --constructor-calldata "$QUORUM" "$count" "${signers[@]}")

  local address
  local tx_hash
  address=$(echo "$deploy_json" | json_get contract_address)
  tx_hash=$(echo "$deploy_json" | json_get transaction_hash)

  if [[ -z "$address" || -z "$tx_hash" ]]; then
    echo "Failed to parse deploy output." >&2
    echo "$deploy_json" >&2
    exit 1
  fi

  local out_file="$OUT_DIR/multisig.${label}.json"
  ROOT_DIR="$ROOT_DIR" NETWORK="$NETWORK" LABEL="$label" CLASS_HASH="$CLASS_HASH" ADDRESS="$address" DEPLOY_TX="$tx_hash"     QUORUM="$QUORUM" SIGNERS_RAW="$raw_signers" OUT_FILE="$out_file"     python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

signers = [s for s in os.environ["SIGNERS_RAW"].split(",") if s]

payload = {
    "network": os.environ["NETWORK"],
    "label": os.environ["LABEL"],
    "contract": "MultisigWallet",
    "address": os.environ["ADDRESS"],
    "deploy_tx": os.environ["DEPLOY_TX"],
    "class_hash": os.environ["CLASS_HASH"],
    "constructor": {
        "quorum": int(os.environ["QUORUM"]),
        "signers": signers,
    },
    "deployed_at": datetime.now(timezone.utc).isoformat(),
}

out_file = Path(os.environ["OUT_FILE"])
out_file.write_text(json.dumps(payload, indent=2) + "\n")
PY

  cat <<REPORT
Deployed MultisigWallet [$label]
- address: $address
- deploy_tx: $tx_hash
- class_hash: $CLASS_HASH
- signers: $raw_signers
REPORT
}

label_deploy "$LABEL" "$SIGNERS_ARG"
