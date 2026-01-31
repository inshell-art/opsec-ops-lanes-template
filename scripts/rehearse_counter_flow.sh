#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

NETWORK="${NETWORK:-devnet}"
RPC="${RPC:-${RPC_URL:-}}"
ACCOUNTS_FILE="${ACCOUNTS_FILE:-}"
OUT_DIR="${OUT_DIR:-}"
SIGNER_A="${SIGNER_A:-}"
SIGNER_B="${SIGNER_B:-}"
LABEL="${MULTISIG_LABEL:-admin}"

usage() {
  cat <<EOF
Usage: rehearse_counter_flow.sh [--label admin|treasury]

Env vars:
  NETWORK, RPC, ACCOUNTS_FILE, OUT_DIR, SIGNER_A, SIGNER_B, MULTISIG_LABEL
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$RPC" || -z "$ACCOUNTS_FILE" || -z "$SIGNER_A" || -z "$SIGNER_B" ]]; then
  echo "Missing RPC, ACCOUNTS_FILE, SIGNER_A, or SIGNER_B env vars." >&2
  usage
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$ROOT_DIR/artifacts/$NETWORK"
fi

MSIG_FILE="$OUT_DIR/multisig.${LABEL}.json"
COUNTER_FILE="$OUT_DIR/counter.json"

if [[ ! -f "$MSIG_FILE" || ! -f "$COUNTER_FILE" ]]; then
  echo "Missing artifacts in $OUT_DIR. Expected: multisig.${LABEL}.json and counter.json" >&2
  exit 1
fi

MSIG_ADDR=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$MSIG_FILE").read_text())["address"])
PY
)

COUNTER_ADDR=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$COUNTER_FILE").read_text())["address"])
PY
)

INCREMENT_SELECTOR=$(sncast selector --name increment | tail -n 1)
SALT=$("$ROOT_DIR/scripts/salt.sh")

cat <<SUMMARY
Intent summary
- target:   $COUNTER_ADDR
- selector: $INCREMENT_SELECTOR (increment)
- calldata: [ ]
- salt:     $SALT
SUMMARY

SUBMIT_JSON=$(sncast --account "$SIGNER_A" --accounts-file "$ACCOUNTS_FILE" --json invoke --url "$RPC" \
  --contract-address "$MSIG_ADDR" --function submit_transaction \
  --calldata "$COUNTER_ADDR" "$INCREMENT_SELECTOR" 0 "$SALT")
SUBMIT_TX=$(echo "$SUBMIT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["transaction_hash"])')

TX_ID=$(sncast --account "$SIGNER_A" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$MSIG_ADDR" --function hash_transaction \
  --calldata "$COUNTER_ADDR" "$INCREMENT_SELECTOR" 0 "$SALT" \
  | tail -n 1)

CONFIRM_A_JSON=$(sncast --account "$SIGNER_A" --accounts-file "$ACCOUNTS_FILE" --json invoke --url "$RPC" \
  --contract-address "$MSIG_ADDR" --function confirm_transaction \
  --calldata "$TX_ID")
CONFIRM_A_TX=$(echo "$CONFIRM_A_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["transaction_hash"])')

CONFIRM_B_JSON=$(sncast --account "$SIGNER_B" --accounts-file "$ACCOUNTS_FILE" --json invoke --url "$RPC" \
  --contract-address "$MSIG_ADDR" --function confirm_transaction \
  --calldata "$TX_ID")
CONFIRM_B_TX=$(echo "$CONFIRM_B_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["transaction_hash"])')

EXECUTE_JSON=$(sncast --account "$SIGNER_A" --accounts-file "$ACCOUNTS_FILE" --json invoke --url "$RPC" \
  --contract-address "$MSIG_ADDR" --function execute_transaction \
  --calldata "$COUNTER_ADDR" "$INCREMENT_SELECTOR" 0 "$SALT")
EXECUTE_TX=$(echo "$EXECUTE_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["transaction_hash"])')

FINAL_VALUE=$(sncast --account "$SIGNER_A" --accounts-file "$ACCOUNTS_FILE" call --url "$RPC" \
  --contract-address "$COUNTER_ADDR" --function get \
  | tail -n 1)

OUT_FILE="$OUT_DIR/rehearsal.counter.json"
ROOT_DIR="$ROOT_DIR" NETWORK="$NETWORK" LABEL="$LABEL" MSIG_ADDR="$MSIG_ADDR" COUNTER_ADDR="$COUNTER_ADDR" \
  SALT="$SALT" TX_ID="$TX_ID" SUBMIT_TX="$SUBMIT_TX" CONFIRM_A_TX="$CONFIRM_A_TX" CONFIRM_B_TX="$CONFIRM_B_TX" \
  EXECUTE_TX="$EXECUTE_TX" FINAL_VALUE="$FINAL_VALUE" OUT_FILE="$OUT_FILE" \
  python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

payload = {
    "network": os.environ["NETWORK"],
    "label": os.environ["LABEL"],
    "multisig_address": os.environ["MSIG_ADDR"],
    "counter_address": os.environ["COUNTER_ADDR"],
    "salt": os.environ["SALT"],
    "tx_id": os.environ["TX_ID"],
    "submit_tx": os.environ["SUBMIT_TX"],
    "confirm_tx_a": os.environ["CONFIRM_A_TX"],
    "confirm_tx_b": os.environ["CONFIRM_B_TX"],
    "execute_tx": os.environ["EXECUTE_TX"],
    "final_counter_value": os.environ["FINAL_VALUE"],
    "completed_at": datetime.now(timezone.utc).isoformat(),
}

out_file = Path(os.environ["OUT_FILE"])
out_file.write_text(json.dumps(payload, indent=2) + "\n")
PY

cat <<REPORT
Rehearsal complete
- tx_id: $TX_ID
- submit_tx: $SUBMIT_TX
- confirm_tx_a: $CONFIRM_A_TX
- confirm_tx_b: $CONFIRM_B_TX
- execute_tx: $EXECUTE_TX
- final_counter_value: $FINAL_VALUE
- wrote: $OUT_FILE

Fill out workbook/20-rehearsal-counter.md and add a run log in workbook/runs/.
REPORT
