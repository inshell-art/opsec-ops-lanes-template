#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
NETWORK="${NETWORK:-}"
RUN_ID="${RUN_ID:-}"

if [[ -z "$NETWORK" || -z "$RUN_ID" ]]; then
  echo "Missing NETWORK or RUN_ID env vars." >&2
  exit 1
fi

BUNDLE_DIR="$ROOT_DIR/bundles/$NETWORK/$RUN_ID"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Bundle dir not found: $BUNDLE_DIR" >&2
  exit 1
fi

BUNDLE_DIR="$BUNDLE_DIR" NETWORK="$NETWORK" RUN_ID="$RUN_ID" \
python3 - <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
network = os.environ["NETWORK"]
run_id = os.environ["RUN_ID"]

required_files = [
    "intent.json",
    "checks.json",
    "run.json",
    "policy.json",
    "bundle_manifest.json",
]

missing = [name for name in required_files if not (bundle_dir / name).exists()]
if missing:
    raise SystemExit(f"Missing required bundle files: {', '.join(missing)}")

manifest_path = bundle_dir / "bundle_manifest.json"
manifest = json.loads(manifest_path.read_text())
if manifest.get("manifest_version") != "1":
    raise SystemExit("bundle_manifest.json manifest_version mismatch")

entries = manifest.get("files", [])
if not isinstance(entries, list) or not entries:
    raise SystemExit("bundle_manifest.json has no files entries")

bundle_meta = manifest.get("bundle", {})
if bundle_meta.get("network") != network:
    raise SystemExit("bundle_manifest.json network mismatch")
if bundle_meta.get("run_id") != run_id:
    raise SystemExit("bundle_manifest.json run_id mismatch")

manifest_paths = [entry.get("path") for entry in entries]
if "txs.json" in manifest_paths:
    raise SystemExit("bundle_manifest.json must not include txs.json (untrusted output)")
for req in ["intent.json", "checks.json", "run.json", "policy.json"]:
    if req not in manifest_paths:
        raise SystemExit(f"bundle_manifest.json missing required file entry: {req}")

for entry in entries:
    rel = entry.get("path")
    if not rel:
        raise SystemExit("bundle_manifest.json entry missing path")
    path = bundle_dir / rel
    if not path.exists():
        raise SystemExit(f"bundle_manifest.json references missing file: {rel}")
    data = path.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    size = len(data)
    if entry.get("sha256") != sha:
        raise SystemExit(f"hash mismatch for {rel}")
    if entry.get("bytes") != size:
        raise SystemExit(f"size mismatch for {rel}")

run = json.loads((bundle_dir / "run.json").read_text())
if run.get("network") != network:
    raise SystemExit("run.json network mismatch")
if run.get("run_id") != run_id:
    raise SystemExit("run.json run_id mismatch")

lane = run.get("lane")
if not lane:
    raise SystemExit("run.json missing lane")
if bundle_meta.get("lane") != lane:
    raise SystemExit("bundle_manifest.json lane mismatch")

intent = json.loads((bundle_dir / "intent.json").read_text())
if intent.get("network") != network:
    raise SystemExit("intent.json network mismatch")
if intent.get("lane") != lane:
    raise SystemExit("intent.json lane mismatch")
if intent.get("intent_version") not in (None, "1"):
    raise SystemExit("intent.json intent_version mismatch")

policy = json.loads((bundle_dir / "policy.json").read_text())
if policy.get("policy_version") != "1":
    raise SystemExit("policy.json policy_version mismatch")
lanes = policy.get("lanes", {})
if lane not in lanes:
    raise SystemExit(f"lane '{lane}' not defined in policy.json")

allowlist = policy.get("network_allowlist")
if isinstance(allowlist, list) and network not in allowlist:
    raise SystemExit(f"network '{network}' not in policy allowlist")

approval_path = bundle_dir / "approval.json"
if approval_path.exists():
    approval = json.loads(approval_path.read_text())
    bundle_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    intent_hash = hashlib.sha256((bundle_dir / "intent.json").read_bytes()).hexdigest()

    if approval.get("bundle_hash") != bundle_hash:
        raise SystemExit("approval.json bundle_hash mismatch")
    if approval.get("intent_hash") != intent_hash:
        raise SystemExit("approval.json intent_hash mismatch")
    if approval.get("network") != network:
        raise SystemExit("approval.json network mismatch")
    if approval.get("lane") != lane:
        raise SystemExit("approval.json lane mismatch")
    if approval.get("run_id") != run_id:
        raise SystemExit("approval.json run_id mismatch")

    # Freeze check: immutables must not be writable after approval.
    immutable_paths = [bundle_dir / e["path"] for e in entries]
    immutable_paths.append(manifest_path)
    for path in immutable_paths:
        mode = path.stat().st_mode
        if mode & stat.S_IWUSR or mode & stat.S_IWGRP or mode & stat.S_IWOTH:
            raise SystemExit(f"immutable file is writable after approval: {path.name}")

print("Bundle verification OK")
PY
