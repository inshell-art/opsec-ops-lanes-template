#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

NETWORK="${NETWORK:-devnet}"
RPC="${RPC:-${RPC_URL:-}}"
ACCOUNT="${ACCOUNT:-}"
ACCOUNTS_FILE="${ACCOUNTS_FILE:-}"
OUT_DIR="${OUT_DIR:-}"
QUORUM="${QUORUM:-2}"
LABEL="both"
SIGNERS_ARG=""
ADMIN_SIGNERS_ARG="${ADMIN_SIGNERS:-}"
TREASURY_SIGNERS_ARG="${TREASURY_SIGNERS:-}"
FORCE_DECLARE="${FORCE_DECLARE:-0}"

usage() {
  cat <<EOF
Usage: deploy_multisig.sh [--label admin|treasury|both] [--quorum N] [--signers addr1,addr2] \
                         [--admin-signers addr1,addr2] [--treasury-signers addr1,addr2]

Env vars:
  NETWORK, RPC, ACCOUNT, ACCOUNTS_FILE, OUT_DIR, QUORUM
  SIGNERS (for single label), ADMIN_SIGNERS, TREASURY_SIGNERS
  FORCE_DECLARE=1 to redeclare even if class_hash exists
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2;;
    --quorum) QUORUM="$2"; shift 2;;
    --signers) SIGNERS_ARG="$2"; shift 2;;
    --admin-signers) ADMIN_SIGNERS_ARG="$2"; shift 2;;
    --treasury-signers) TREASURY_SIGNERS_ARG="$2"; shift 2;;
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

if [[ -z "$CLASS_HASH" || "$FORCE_DECLARE" == "1" ]]; then
  DECLARE_JSON=$(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json declare \
    --package multisig_wallet --contract-name MultisigWallet \
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
  deploy_json=$(sncast --account "$ACCOUNT" --accounts-file "$ACCOUNTS_FILE" --json deploy \
    --class-hash "$CLASS_HASH" --url "$RPC" --salt "$salt" \
    --constructor-calldata "$QUORUM" "$count" "${signers[@]}")

  local address
  local tx_hash
  address=$(echo "$deploy_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["contract_address"])')
  tx_hash=$(echo "$deploy_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["transaction_hash"])')

  local out_file="$OUT_DIR/multisig.${label}.json"
  ROOT_DIR="$ROOT_DIR" NETWORK="$NETWORK" LABEL="$label" CLASS_HASH="$CLASS_HASH" ADDRESS="$address" DEPLOY_TX="$tx_hash" \
    QUORUM="$QUORUM" SIGNERS_RAW="$raw_signers" OUT_FILE="$out_file" \
    python3 - <<'PY'
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

case "$LABEL" in
  admin)
    if [[ -z "$SIGNERS_ARG" ]]; then
      SIGNERS_ARG="$ADMIN_SIGNERS_ARG"
    fi
    label_deploy "admin" "$SIGNERS_ARG"
    ;;
  treasury)
    if [[ -z "$SIGNERS_ARG" ]]; then
      SIGNERS_ARG="$TREASURY_SIGNERS_ARG"
    fi
    label_deploy "treasury" "$SIGNERS_ARG"
    ;;
  both)
    if [[ -z "$ADMIN_SIGNERS_ARG" || -z "$TREASURY_SIGNERS_ARG" ]]; then
      echo "ADMIN_SIGNERS and TREASURY_SIGNERS are required for label=both." >&2
      exit 1
    fi
    label_deploy "admin" "$ADMIN_SIGNERS_ARG"
    label_deploy "treasury" "$TREASURY_SIGNERS_ARG"
    ;;
  *)
    echo "Invalid label: $LABEL" >&2
    usage
    exit 1
    ;;
esac
