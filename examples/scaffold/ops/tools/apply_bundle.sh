#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "apply_bundle.sh accepts no args. Use env NETWORK=... RUN_ID=..." >&2
  exit 2
fi

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
BUNDLE_PATH=${BUNDLE_PATH:-}

if [[ "${SIGNING_OS:-}" != "1" ]]; then
  echo "Refusing to run: SIGNING_OS=1 is required." >&2
  exit 2
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Refusing to run: working tree is dirty." >&2
  exit 2
fi

ROOT=$(git rev-parse --show-toplevel)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ -n "$BUNDLE_PATH" ]]; then
  BUNDLE_DIR="$BUNDLE_PATH"
else
  if [[ -z "$NETWORK" || -z "$RUN_ID" ]]; then
    echo "Usage: NETWORK=<sepolia|mainnet> RUN_ID=<id> $0" >&2
    echo "   or: BUNDLE_PATH=<path> $0" >&2
    exit 2
  fi
  BUNDLE_DIR="$ROOT/bundles/$NETWORK/$RUN_ID"
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Bundle directory not found: $BUNDLE_DIR" >&2
  exit 2
fi

if [[ ! -f "$BUNDLE_DIR/bundle_manifest.json" ]]; then
  echo "Missing bundle_manifest.json in $BUNDLE_DIR" >&2
  exit 2
fi

export BUNDLE_DIR

BUNDLE_PATH="$BUNDLE_DIR" "$SCRIPT_DIR/verify_bundle.sh"

if [[ ! -f "$BUNDLE_DIR/approval.json" ]]; then
  echo "Missing approval.json in $BUNDLE_DIR" >&2
  exit 2
fi

read -r BUNDLE_HASH APPROVAL_HASH NETWORK_FROM_RUN LANE_FROM_RUN <<EOF_HASH
$(python3 - <<'PY'
import json
import os
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
approval = json.loads((bundle_dir / "approval.json").read_text())
run = json.loads((bundle_dir / "run.json").read_text())
print(manifest.get("bundle_hash", ""), approval.get("bundle_hash", ""), run.get("network", ""), run.get("lane", ""))
PY
)
EOF_HASH

if [[ -z "$BUNDLE_HASH" || -z "$APPROVAL_HASH" ]]; then
  echo "Invalid manifest or approval" >&2
  exit 2
fi

if [[ "$BUNDLE_HASH" != "$APPROVAL_HASH" ]]; then
  echo "Approval does not match bundle hash" >&2
  exit 2
fi

if [[ -n "$NETWORK" && "$NETWORK" != "$NETWORK_FROM_RUN" ]]; then
  echo "Network mismatch: $NETWORK vs $NETWORK_FROM_RUN" >&2
  exit 2
fi

POLICY_FILE="$ROOT/ops/policy/lane.${NETWORK_FROM_RUN}.json"
if [[ ! -f "$POLICY_FILE" ]]; then
  POLICY_FILE="$ROOT/ops/policy/lane.${NETWORK_FROM_RUN}.example.json"
fi

if [[ ! -f "$POLICY_FILE" ]]; then
  echo "Missing policy file for network: $NETWORK_FROM_RUN" >&2
  exit 2
fi

REQUIRES_SEPOLIA=$(POLICY_FILE="$POLICY_FILE" RUN_LANE="$LANE_FROM_RUN" python3 - <<'PY'
import json
import os
from pathlib import Path
policy_path = Path(os.environ["POLICY_FILE"])
run_lane = os.environ["RUN_LANE"]
policy = json.loads(policy_path.read_text())
lanes = policy.get("lanes", {})
lane = lanes.get(run_lane, {})
gates = lane.get("gates", {})
flag = lane.get("requires_sepolia_rehearsal_proof", False) or gates.get("require_sepolia_rehearsal_proof", False)
print("true" if flag else "false")
PY
)

if [[ "$NETWORK_FROM_RUN" == "mainnet" && "$REQUIRES_SEPOLIA" == "true" ]]; then
  if [[ -z "${SEPOLIA_PROOF_RUN_ID:-}" ]]; then
    echo "Missing SEPOLIA_PROOF_RUN_ID for mainnet apply" >&2
    exit 2
  fi
  PROOF_DIR="$ROOT/bundles/sepolia/$SEPOLIA_PROOF_RUN_ID"
  if [[ ! -f "$PROOF_DIR/txs.json" || ! -f "$PROOF_DIR/postconditions.json" ]]; then
    echo "Sepolia proof missing txs.json or postconditions.json: $PROOF_DIR" >&2
    exit 2
  fi
fi

TXS_PATH="$BUNDLE_DIR/txs.json"
POST_PATH="$BUNDLE_DIR/postconditions.json"
SNAP_DIR="$BUNDLE_DIR/snapshots"
mkdir -p "$SNAP_DIR"

APPLIED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export APPLIED_AT TXS_PATH POST_PATH SNAP_DIR
python3 - <<'PY'
import json
import os
from pathlib import Path

applied_at = os.environ["APPLIED_AT"]

(Path(os.environ["TXS_PATH"]).parent).mkdir(parents=True, exist_ok=True)
(Path(os.environ["SNAP_DIR"])).mkdir(parents=True, exist_ok=True)

(Path(os.environ["TXS_PATH"])).write_text(json.dumps({
    "applied_at": applied_at,
    "txs": ["0xSTUB_TX"],
    "notes": "Scaffold stub. Replace with real tx hashes."
}, indent=2, sort_keys=True) + "\n")

(Path(os.environ["POST_PATH"])).write_text(json.dumps({
    "applied_at": applied_at,
    "pass": True,
    "notes": "Scaffold stub. Replace with real postconditions."
}, indent=2, sort_keys=True) + "\n")

(Path(os.environ["SNAP_DIR"]) / "post_state.json").write_text(json.dumps({
    "applied_at": applied_at,
    "notes": "Scaffold stub. Replace with real snapshots."
}, indent=2, sort_keys=True) + "\n")
PY

echo "Apply stub complete. Wrote txs.json, postconditions.json, snapshots/ in $BUNDLE_DIR"
