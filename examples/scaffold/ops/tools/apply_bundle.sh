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
    echo "Usage: NETWORK=<devnet|sepolia|mainnet> RUN_ID=<id> $0" >&2
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

IFS=$'\t' read -r BUNDLE_HASH APPROVAL_HASH NETWORK_FROM_RUN LANE_FROM_RUN INTENT_DEPLOY_PARAMS_HASH APPROVAL_DEPLOY_PARAMS_HASH <<EOF_META
$(python3 - <<'PY'
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
approval = json.loads((bundle_dir / "approval.json").read_text())
run = json.loads((bundle_dir / "run.json").read_text())
intent = json.loads((bundle_dir / "intent.json").read_text())

def emit(value):
    return value if value else "__EMPTY__"

print("\t".join([
    emit(manifest.get("bundle_hash", "")),
    emit(approval.get("bundle_hash", "")),
    emit(run.get("network", "")),
    emit(run.get("lane", "")),
    emit(intent.get("deploy_params_sha256", "")),
    emit(approval.get("deploy_params_sha256", "")),
]))
PY
)
EOF_META

for field in BUNDLE_HASH APPROVAL_HASH NETWORK_FROM_RUN LANE_FROM_RUN INTENT_DEPLOY_PARAMS_HASH APPROVAL_DEPLOY_PARAMS_HASH; do
  if [[ "${!field}" == "__EMPTY__" ]]; then
    printf -v "$field" '%s' ""
  fi
done

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

POLICY_FILE=""
for candidate in \
  "$ROOT/ops/policy/lane.${NETWORK_FROM_RUN}.json" \
  "$ROOT/ops/policy/${NETWORK_FROM_RUN}.policy.json" \
  "$ROOT/ops/policy/lane.${NETWORK_FROM_RUN}.example.json" \
  "$ROOT/ops/policy/${NETWORK_FROM_RUN}.policy.example.json" \
  "$ROOT/policy/${NETWORK_FROM_RUN}.policy.example.json"
do
  if [[ -f "$candidate" ]]; then
    POLICY_FILE="$candidate"
    break
  fi
done

if [[ -z "$POLICY_FILE" ]]; then
  echo "Missing policy file for network: $NETWORK_FROM_RUN" >&2
  echo "Expected one of: lane.${NETWORK_FROM_RUN}.json, ${NETWORK_FROM_RUN}.policy.json, lane.${NETWORK_FROM_RUN}.example.json, ${NETWORK_FROM_RUN}.policy.example.json, policy/${NETWORK_FROM_RUN}.policy.example.json" >&2
  exit 2
fi

IFS=$'\t' read -r REQUIRES_REHEARSAL REHEARSAL_NETWORK DEPLOY_PARAMS_REQUIRED DEPLOY_PARAMS_FILENAME DEPLOY_PARAMS_ENV_VAR DEPLOY_PARAMS_ALLOW_OVERRIDE <<EOF_POLICY
$(POLICY_FILE="$POLICY_FILE" RUN_LANE="$LANE_FROM_RUN" RUN_NETWORK="$NETWORK_FROM_RUN" python3 - <<'PY'
import json
import os
from pathlib import Path

policy_path = Path(os.environ["POLICY_FILE"])
run_lane = os.environ["RUN_LANE"]
run_network = os.environ["RUN_NETWORK"]
policy = json.loads(policy_path.read_text())
lanes = policy.get("lanes", {})
lane = lanes.get(run_lane, {})
gates = lane.get("gates", {})

if not isinstance(gates, dict):
    gates = {}

new_keys_present = "require_rehearsal_proof" in gates or "rehearsal_proof_network" in gates
if new_keys_present:
    require_flag = bool(gates.get("require_rehearsal_proof", False))
    proof_network = str(gates.get("rehearsal_proof_network", "devnet")).strip().lower()
    if require_flag and proof_network not in {"devnet", "sepolia"}:
        raise SystemExit(f"invalid rehearsal_proof_network for lane '{run_lane}': {proof_network}")
    if not require_flag:
        proof_network = ""
else:
    devnet_flag = bool(lane.get("requires_devnet_rehearsal_proof", False) or gates.get("require_devnet_rehearsal_proof", False))
    sepolia_flag = bool(lane.get("requires_sepolia_rehearsal_proof", False) or gates.get("require_sepolia_rehearsal_proof", False))
    require_flag = devnet_flag or sepolia_flag
    if devnet_flag:
        proof_network = "devnet"
    elif sepolia_flag:
        proof_network = "sepolia"
    else:
        proof_network = ""

required_checks = lane.get("required_checks", [])
if not isinstance(required_checks, list):
    required_checks = []

deploy_defaults = {
    "required_networks": ["sepolia", "mainnet"],
    "required_lanes": ["deploy"],
    "bundle_filename": "deploy_params.json",
    "apply_env_var": "DEPLOY_PARAMS_FILE",
    "allow_external_override": False,
}

deploy_cfg = dict(deploy_defaults)
if isinstance(policy.get("deploy_params"), dict):
    deploy_cfg.update(policy["deploy_params"])

required_networks = deploy_cfg.get("required_networks", [])
required_lanes = deploy_cfg.get("required_lanes", [])
if not isinstance(required_networks, list):
    required_networks = []
if not isinstance(required_lanes, list):
    required_lanes = []

require_deploy_params = (
    run_network in required_networks
    and run_lane in required_lanes
    and "deploy_params_pinned" in required_checks
)

print("\t".join([
    "true" if require_flag else "false",
    proof_network if proof_network else "__EMPTY__",
    "true" if require_deploy_params else "false",
    str(deploy_cfg.get("bundle_filename", "deploy_params.json")),
    str(deploy_cfg.get("apply_env_var", "DEPLOY_PARAMS_FILE")),
    "true" if bool(deploy_cfg.get("allow_external_override", False)) else "false",
]))
PY
)
EOF_POLICY

if [[ "$REHEARSAL_NETWORK" == "__EMPTY__" ]]; then
  REHEARSAL_NETWORK=""
fi
REQUIRES_REHEARSAL=${REQUIRES_REHEARSAL:-false}
DEPLOY_PARAMS_REQUIRED=${DEPLOY_PARAMS_REQUIRED:-false}
DEPLOY_PARAMS_FILENAME=${DEPLOY_PARAMS_FILENAME:-deploy_params.json}
DEPLOY_PARAMS_ENV_VAR=${DEPLOY_PARAMS_ENV_VAR:-DEPLOY_PARAMS_FILE}
DEPLOY_PARAMS_ALLOW_OVERRIDE=${DEPLOY_PARAMS_ALLOW_OVERRIDE:-false}

if [[ "$NETWORK_FROM_RUN" == "mainnet" && "$REQUIRES_REHEARSAL" == "true" ]]; then
  PROOF_RUN_ID="${REHEARSAL_PROOF_RUN_ID:-${DEVNET_PROOF_RUN_ID:-${SEPOLIA_PROOF_RUN_ID:-}}}"
  if [[ -z "$PROOF_RUN_ID" ]]; then
    echo "Missing rehearsal proof run id for mainnet apply. Set REHEARSAL_PROOF_RUN_ID (fallbacks: DEVNET_PROOF_RUN_ID, SEPOLIA_PROOF_RUN_ID)." >&2
    exit 2
  fi
  if [[ -z "$REHEARSAL_NETWORK" ]]; then
    echo "Policy requested rehearsal proof but rehearsal_proof_network is empty for lane: $LANE_FROM_RUN" >&2
    exit 2
  fi
  PROOF_DIR="$ROOT/bundles/$REHEARSAL_NETWORK/$PROOF_RUN_ID"
  if [[ ! -f "$PROOF_DIR/txs.json" || ! -f "$PROOF_DIR/postconditions.json" ]]; then
    echo "Rehearsal proof missing txs.json or postconditions.json in $REHEARSAL_NETWORK bundle: $PROOF_DIR" >&2
    exit 2
  fi
fi

DEPLOY_PARAMS_FILE_USED=""
DEPLOY_PARAMS_SHA256_USED=""
if [[ "$DEPLOY_PARAMS_REQUIRED" == "true" ]]; then
  if [[ ! "$DEPLOY_PARAMS_ENV_VAR" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Invalid deploy params env var name in policy: $DEPLOY_PARAMS_ENV_VAR" >&2
    exit 2
  fi

  EXPECTED_DEPLOY_PARAMS_PATH="$BUNDLE_DIR/$DEPLOY_PARAMS_FILENAME"
  if [[ ! -f "$EXPECTED_DEPLOY_PARAMS_PATH" ]]; then
    echo "Deploy params required but missing bundled file: $EXPECTED_DEPLOY_PARAMS_PATH" >&2
    exit 2
  fi

  CURRENT_DEPLOY_OVERRIDE="${!DEPLOY_PARAMS_ENV_VAR:-}"
  if [[ -n "$CURRENT_DEPLOY_OVERRIDE" && "$CURRENT_DEPLOY_OVERRIDE" != "$EXPECTED_DEPLOY_PARAMS_PATH" && "$DEPLOY_PARAMS_ALLOW_OVERRIDE" != "true" ]]; then
    echo "External deploy params override is not allowed. Expected $DEPLOY_PARAMS_ENV_VAR=$EXPECTED_DEPLOY_PARAMS_PATH" >&2
    exit 2
  fi

  export "$DEPLOY_PARAMS_ENV_VAR=$EXPECTED_DEPLOY_PARAMS_PATH"

  IFS=$'\t' read -r ACTUAL_DEPLOY_PARAMS_HASH INTENT_DEPLOY_HASH_NOW APPROVAL_DEPLOY_HASH_NOW <<EOF_DEPLOY
$(BUNDLE_DIR="$BUNDLE_DIR" DEPLOY_PARAMS_FILENAME="$DEPLOY_PARAMS_FILENAME" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
filename = os.environ["DEPLOY_PARAMS_FILENAME"]
params_path = bundle_dir / filename
intent = json.loads((bundle_dir / "intent.json").read_text())
approval = json.loads((bundle_dir / "approval.json").read_text())
actual = hashlib.sha256(params_path.read_bytes()).hexdigest()
def emit(value):
    return value if value else "__EMPTY__"
print("\t".join([
    emit(actual),
    emit(intent.get("deploy_params_sha256", "")),
    emit(approval.get("deploy_params_sha256", "")),
]))
PY
)
EOF_DEPLOY

  for field in ACTUAL_DEPLOY_PARAMS_HASH INTENT_DEPLOY_HASH_NOW APPROVAL_DEPLOY_HASH_NOW; do
    if [[ "${!field}" == "__EMPTY__" ]]; then
      printf -v "$field" '%s' ""
    fi
  done

  if [[ -z "$INTENT_DEPLOY_HASH_NOW" ]]; then
    echo "Deploy params required but intent.json.deploy_params_sha256 is missing" >&2
    exit 2
  fi
  if [[ "$ACTUAL_DEPLOY_PARAMS_HASH" != "$INTENT_DEPLOY_HASH_NOW" ]]; then
    echo "Deploy params hash mismatch: bundled file vs intent.json" >&2
    exit 2
  fi
  if [[ -z "$APPROVAL_DEPLOY_HASH_NOW" ]]; then
    echo "Deploy params required but approval.json.deploy_params_sha256 is missing" >&2
    exit 2
  fi
  if [[ "$ACTUAL_DEPLOY_PARAMS_HASH" != "$APPROVAL_DEPLOY_HASH_NOW" ]]; then
    echo "Deploy params hash mismatch: bundled file vs approval.json" >&2
    exit 2
  fi

  DEPLOY_PARAMS_FILE_USED="$EXPECTED_DEPLOY_PARAMS_PATH"
  DEPLOY_PARAMS_SHA256_USED="$ACTUAL_DEPLOY_PARAMS_HASH"

  if [[ -n "$INTENT_DEPLOY_PARAMS_HASH" && "$INTENT_DEPLOY_PARAMS_HASH" != "$ACTUAL_DEPLOY_PARAMS_HASH" ]]; then
    echo "Intent deploy params hash changed unexpectedly since initial read" >&2
    exit 2
  fi
  if [[ -n "$APPROVAL_DEPLOY_PARAMS_HASH" && "$APPROVAL_DEPLOY_PARAMS_HASH" != "$ACTUAL_DEPLOY_PARAMS_HASH" ]]; then
    echo "Approval deploy params hash changed unexpectedly since initial read" >&2
    exit 2
  fi
fi

TXS_PATH="$BUNDLE_DIR/txs.json"
SNAP_DIR="$BUNDLE_DIR/snapshots"
mkdir -p "$SNAP_DIR"

APPLIED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export APPLIED_AT TXS_PATH SNAP_DIR DEPLOY_PARAMS_FILE_USED DEPLOY_PARAMS_SHA256_USED
python3 - <<'PY'
import json
import os
from pathlib import Path

applied_at = os.environ["APPLIED_AT"]

tx_payload = {
    "applied_at": applied_at,
    "txs": ["0xSTUB_TX"],
    "notes": "Scaffold stub. Replace with real tx hashes.",
}

params_file = os.environ.get("DEPLOY_PARAMS_FILE_USED", "").strip()
params_hash = os.environ.get("DEPLOY_PARAMS_SHA256_USED", "").strip()
if params_file:
    tx_payload["deploy_params_file"] = params_file
if params_hash:
    tx_payload["deploy_params_sha256"] = params_hash

(Path(os.environ["TXS_PATH"]).parent).mkdir(parents=True, exist_ok=True)
(Path(os.environ["SNAP_DIR"])).mkdir(parents=True, exist_ok=True)

(Path(os.environ["TXS_PATH"])).write_text(json.dumps(tx_payload, indent=2, sort_keys=True) + "\n")

snapshot_payload = {
    "applied_at": applied_at,
    "notes": "Scaffold stub. Replace with real snapshots.",
}
if params_file:
    snapshot_payload["deploy_params_file"] = params_file
if params_hash:
    snapshot_payload["deploy_params_sha256"] = params_hash

(Path(os.environ["SNAP_DIR"]) / "post_state.json").write_text(json.dumps(snapshot_payload, indent=2, sort_keys=True) + "\n")
PY

echo "Apply stub complete. Wrote txs.json and snapshots/ in $BUNDLE_DIR"
