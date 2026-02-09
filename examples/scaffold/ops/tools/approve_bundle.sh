#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
NETWORK="${NETWORK:-}"
RUN_ID="${RUN_ID:-}"
APPROVER="${APPROVER:-}"
APPROVER_EMAIL="${APPROVER_EMAIL:-}"
FORCE="${FORCE:-0}"

if [[ -z "$NETWORK" || -z "$RUN_ID" ]]; then
  echo "Missing NETWORK or RUN_ID env vars." >&2
  exit 1
fi

BUNDLE_DIR="$ROOT_DIR/bundles/$NETWORK/$RUN_ID"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Bundle dir not found: $BUNDLE_DIR" >&2
  exit 1
fi

if [[ -z "$APPROVER" ]]; then
  APPROVER=$(git config user.name || true)
fi
if [[ -z "$APPROVER" ]]; then
  APPROVER="${USER:-unknown}"
fi
if [[ -z "$APPROVER_EMAIL" ]]; then
  APPROVER_EMAIL=$(git config user.email || true)
fi

APPROVAL_PATH="$BUNDLE_DIR/approval.json"
if [[ -f "$APPROVAL_PATH" && "$FORCE" != "1" ]]; then
  echo "approval.json already exists. Set FORCE=1 to overwrite." >&2
  exit 1
fi

NETWORK="$NETWORK" RUN_ID="$RUN_ID" "$ROOT_DIR/ops/tools/verify_bundle.sh"

BUNDLE_DIR="$BUNDLE_DIR" NETWORK="$NETWORK" RUN_ID="$RUN_ID" APPROVER="$APPROVER" APPROVER_EMAIL="$APPROVER_EMAIL" \
python3 - <<'PY'
import hashlib
import json
import os
import stat
from datetime import datetime, timezone
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
network = os.environ["NETWORK"]
run_id = os.environ["RUN_ID"]

run = json.loads((bundle_dir / "run.json").read_text())
intent = json.loads((bundle_dir / "intent.json").read_text())
policy = json.loads((bundle_dir / "policy.json").read_text())
checks = json.loads((bundle_dir / "checks.json").read_text())
manifest_path = bundle_dir / "bundle_manifest.json"

lane = run.get("lane")
if not lane:
    raise SystemExit("run.json missing lane")

lane_policy = policy.get("lanes", {}).get(lane)
if not lane_policy:
    raise SystemExit(f"lane '{lane}' not defined in policy.json")

required = lane_policy.get("required_checks", [])
check_map = {c.get("name"): c.get("status") for c in checks.get("checks", [])}
missing = [name for name in required if check_map.get(name) != "pass"]
if missing:
    raise SystemExit(f"Cannot approve: required checks not passed: {', '.join(missing)}")

if checks.get("status") != "pass":
    raise SystemExit("Cannot approve: checks.json status is not 'pass'")

bundle_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
intent_hash = hashlib.sha256((bundle_dir / "intent.json").read_bytes()).hexdigest()

approved_at = datetime.now(timezone.utc).isoformat()

approval = {
    "approval_version": "1",
    "approved_by": os.environ.get("APPROVER", "unknown"),
    "approved_by_email": os.environ.get("APPROVER_EMAIL", ""),
    "approved_at": approved_at,
    "network": network,
    "lane": lane,
    "run_id": run_id,
    "bundle_hash": bundle_hash,
    "intent_hash": intent_hash,
    "statement": intent.get("description", "") or "Approved intent bundle",
}

approval_path = bundle_dir / "approval.json"
approval_path.write_text(json.dumps(approval, indent=2, sort_keys=True) + "\n")

manifest = json.loads(manifest_path.read_text())
immutable_paths = [bundle_dir / e["path"] for e in manifest.get("files", [])]
immutable_paths.append(manifest_path)

for path in immutable_paths:
    mode = path.stat().st_mode
    # remove write bits
    path.chmod(mode & ~stat.S_IWUSR & ~stat.S_IWGRP & ~stat.S_IWOTH)

print("Approval written and immutables frozen")
PY
