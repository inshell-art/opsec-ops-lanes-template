#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
RUN_ID=${RUN_ID:-}
BUNDLE_PATH=${BUNDLE_PATH:-}

ROOT=$(git rev-parse --show-toplevel)

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

export BUNDLE_DIR ROOT

IFS=$'\t' read -r BUNDLE_HASH INTENT_HASH NETWORK_FROM_RUN LANE_FROM_RUN RUN_ID_FROM_RUN DEPLOY_PARAMS_HASH DEPLOY_PARAMS_PATH <<EOF_META
$(python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
root = Path(os.environ["ROOT"])
manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
run = json.loads((bundle_dir / "run.json").read_text())
intent = json.loads((bundle_dir / "intent.json").read_text())

network = run.get("network", "")
lane = run.get("lane", "")

policy_path = None
for candidate in [
    root / "ops/policy" / f"lane.{network}.json",
    root / "ops/policy" / f"{network}.policy.json",
    root / "ops/policy" / f"lane.{network}.example.json",
    root / "ops/policy" / f"{network}.policy.example.json",
    root / "policy" / f"{network}.policy.example.json",
]:
    if candidate.exists():
        policy_path = candidate
        break

params_filename = "deploy_params.json"
if policy_path:
    policy = json.loads(policy_path.read_text())
    deploy_cfg = policy.get("deploy_params", {})
    if isinstance(deploy_cfg, dict):
        params_filename = str(deploy_cfg.get("bundle_filename", params_filename))

bundle_hash = manifest.get("bundle_hash", "")
intent_hash = ""
for item in manifest.get("immutable_files", []):
    if item.get("path") == "intent.json":
        intent_hash = item.get("sha256", "")
        break
if not intent_hash and (bundle_dir / "intent.json").exists():
    intent_hash = hashlib.sha256((bundle_dir / "intent.json").read_bytes()).hexdigest()

deploy_hash = intent.get("deploy_params_sha256", "")
deploy_params_path = ""
if deploy_hash:
    candidate = bundle_dir / params_filename
    if not candidate.exists():
        raise SystemExit(f"intent has deploy_params_sha256 but missing {candidate}")
    actual = hashlib.sha256(candidate.read_bytes()).hexdigest()
    if actual != deploy_hash:
        raise SystemExit("deploy params hash mismatch: intent vs bundle file")
    deploy_params_path = str(candidate)

def emit(value):
    return value if value else "__EMPTY__"

print("\t".join([
    emit(bundle_hash),
    emit(intent_hash),
    emit(network),
    emit(lane),
    emit(run.get("run_id", "")),
    emit(deploy_hash),
    emit(deploy_params_path),
]))
PY
)
EOF_META

for field in BUNDLE_HASH INTENT_HASH NETWORK_FROM_RUN LANE_FROM_RUN RUN_ID_FROM_RUN DEPLOY_PARAMS_HASH DEPLOY_PARAMS_PATH; do
  if [[ "${!field}" == "__EMPTY__" ]]; then
    printf -v "$field" '%s' ""
  fi
done

if [[ -z "$BUNDLE_HASH" || -z "$NETWORK_FROM_RUN" || -z "$LANE_FROM_RUN" ]]; then
  echo "Invalid bundle or run.json" >&2
  exit 2
fi

if [[ -n "$DEPLOY_PARAMS_HASH" && -n "$DEPLOY_PARAMS_PATH" ]]; then
  echo "Deploy params summary (deterministic):"
  DEPLOY_PARAMS_PATH="$DEPLOY_PARAMS_PATH" python3 - <<'PY'
import json
import os
from pathlib import Path

params_path = Path(os.environ["DEPLOY_PARAMS_PATH"])
payload = json.loads(params_path.read_text())
ctor = payload.get("constructor_args", {}) if isinstance(payload.get("constructor_args"), dict) else {}


def pick(key):
    if key in payload:
        return payload[key]
    if key in ctor:
        return ctor[key]
    return "<missing>"

rows = [
    ("name", pick("name")),
    ("symbol", pick("symbol")),
    ("paymentToken", pick("paymentToken")),
    ("treasury", pick("treasury")),
    ("openTime", pick("openTime")),
    ("startDelay", pick("startDelay")),
]

pricing = pick("pricing")
if isinstance(pricing, dict):
    pricing_display = json.dumps(pricing, sort_keys=True)
else:
    pricing_display = pricing
rows.append(("pricing", pricing_display))
rows.append(("tokenPerEpoch", pick("tokenPerEpoch")))
rows.append(("epochSeconds", pick("epochSeconds")))

for key, value in rows:
    if isinstance(value, (dict, list)):
        value = json.dumps(value, sort_keys=True)
    print(f"  {key:16} {value}")
PY
fi

SUFFIX=${BUNDLE_HASH: -8}
if [[ -n "$DEPLOY_PARAMS_HASH" ]]; then
  DEPLOY_SUFFIX=${DEPLOY_PARAMS_HASH: -8}
  PHRASE_REQUIRED="APPROVE $NETWORK_FROM_RUN $LANE_FROM_RUN $SUFFIX DP$DEPLOY_SUFFIX"
else
  PHRASE_REQUIRED="APPROVE $NETWORK_FROM_RUN $LANE_FROM_RUN $SUFFIX"
fi

echo "Type exactly: $PHRASE_REQUIRED"
read -r PHRASE

if [[ "$PHRASE" != "$PHRASE_REQUIRED" ]]; then
  echo "Approval phrase mismatch" >&2
  exit 2
fi

APPROVER=${USER:-unknown}
APPROVED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export BUNDLE_HASH INTENT_HASH NETWORK_FROM_RUN LANE_FROM_RUN APPROVER APPROVED_AT RUN_ID_FROM_RUN DEPLOY_PARAMS_HASH

python3 - <<'PY'
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
approval = {
    "approved_at": os.environ["APPROVED_AT"],
    "approver": os.environ["APPROVER"],
    "network": os.environ["NETWORK_FROM_RUN"],
    "lane": os.environ["LANE_FROM_RUN"],
    "run_id": os.environ.get("RUN_ID_FROM_RUN", ""),
    "bundle_hash": os.environ["BUNDLE_HASH"],
    "intent_hash": os.environ["INTENT_HASH"],
    "notes": "Human approval required. No manual calldata review."
}

deploy_hash = os.environ.get("DEPLOY_PARAMS_HASH", "").strip()
if deploy_hash:
    approval["deploy_params_sha256"] = deploy_hash

(bundle_dir / "approval.json").write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")
print(f"Approval written to {bundle_dir / 'approval.json'}")
PY
