#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "apply_bundle.sh accepts no args. Use env NETWORK=... RUN_ID=..." >&2
  exit 1
fi

ROOT_DIR=$(git rev-parse --show-toplevel)
NETWORK="${NETWORK:-}"
RUN_ID="${RUN_ID:-}"
export ROOT_DIR

if [[ -z "$NETWORK" || -z "$RUN_ID" ]]; then
  echo "Missing NETWORK or RUN_ID env vars." >&2
  exit 1
fi

if [[ -z "${STARKNET_RPC:-}" ]]; then
  echo "Missing STARKNET_RPC env var." >&2
  exit 1
fi
if [[ -z "${STARKNET_ACCOUNT:-}" ]]; then
  echo "Missing STARKNET_ACCOUNT env var." >&2
  exit 1
fi
if [[ -z "${STARKNET_KEYSTORE:-}" || -z "${STARKNET_LEDGER_PATH:-}" ]]; then
  echo "Missing STARKNET_KEYSTORE or STARKNET_LEDGER_PATH env vars." >&2
  exit 1
fi

BUNDLE_DIR="$ROOT_DIR/bundles/$NETWORK/$RUN_ID"
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "Bundle dir not found: $BUNDLE_DIR" >&2
  exit 1
fi

# Do not allow keystore/account files inside the repo.
python3 - <<'PY'
import os
from pathlib import Path

root = Path(os.environ["ROOT_DIR"]).resolve()
for key in ("STARKNET_ACCOUNT", "STARKNET_KEYSTORE"):
    val = os.environ.get(key)
    if not val:
        continue
    path = Path(val)
    if not path.exists():
        continue
    try:
        resolved = path.resolve()
    except Exception:
        continue
    if str(resolved).startswith(str(root)):
        raise SystemExit(f"{key} must not live inside the repo: {resolved}")
PY

NETWORK="$NETWORK" RUN_ID="$RUN_ID" "$ROOT_DIR/ops/tools/verify_bundle.sh"

RUN_JSON="$BUNDLE_DIR/run.json"
if [[ ! -f "$RUN_JSON" ]]; then
  echo "Missing run.json in bundle." >&2
  exit 1
fi

RUN_COMMIT=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$RUN_JSON").read_text()).get("git_commit", ""))
PY
)
RUN_DIRTY=$(python3 - <<PY
import json
from pathlib import Path
print(json.loads(Path("$RUN_JSON").read_text()).get("git_dirty", False))
PY
)
HEAD_COMMIT=$(git rev-parse HEAD)
if [[ "$RUN_COMMIT" != "$HEAD_COMMIT" ]]; then
  echo "Git commit mismatch. bundle=$RUN_COMMIT repo=$HEAD_COMMIT" >&2
  exit 1
fi
if [[ "$RUN_DIRTY" == "True" || -n "$(git status --porcelain)" ]]; then
  echo "Repo must be clean to apply. Commit your changes first." >&2
  exit 1
fi

BUNDLE_DIR="$BUNDLE_DIR" NETWORK="$NETWORK" RUN_ID="$RUN_ID" ROOT_DIR="$ROOT_DIR" \
STARKNET_RPC="$STARKNET_RPC" STARKNET_ACCOUNT="$STARKNET_ACCOUNT" \
STARKNET_KEYSTORE="$STARKNET_KEYSTORE" STARKNET_LEDGER_PATH="$STARKNET_LEDGER_PATH" \
python3 - <<'PY'
import hashlib
import json
import os
import re
import subprocess
import sys
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
approval_path = bundle_dir / "approval.json"

lane = run.get("lane")
if not lane:
    raise SystemExit("run.json missing lane")

lane_policy = policy.get("lanes", {}).get(lane)
if not lane_policy:
    raise SystemExit(f"lane '{lane}' not defined in policy.json")

if not lane_policy.get("apply_allowed", False):
    raise SystemExit(f"apply is not allowed for lane '{lane}'")

if lane_policy.get("require_approval", True) and not approval_path.exists():
    raise SystemExit("approval.json is required before apply")

required = lane_policy.get("required_checks", [])
check_map = {c.get("name"): c.get("status") for c in checks.get("checks", [])}
missing = [name for name in required if check_map.get(name) != "pass"]
if missing:
    raise SystemExit(f"Required checks not passed: {', '.join(missing)}")

if checks.get("status") != "pass":
    raise SystemExit("checks.json status is not 'pass'")

if approval_path.exists():
    approval = json.loads(approval_path.read_text())
    bundle_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    intent_hash = hashlib.sha256((bundle_dir / "intent.json").read_bytes()).hexdigest()
    if approval.get("bundle_hash") != bundle_hash:
        raise SystemExit("approval.json bundle_hash mismatch")
    if approval.get("intent_hash") != intent_hash:
        raise SystemExit("approval.json intent_hash mismatch")

ops = intent.get("ops")
if not isinstance(ops, list) or not ops:
    raise SystemExit("intent.json has no ops to apply")

allowed_ops = lane_policy.get("allowed_ops")
if isinstance(allowed_ops, list) and allowed_ops:
    for op in ops:
        if op.get("kind") not in allowed_ops:
            raise SystemExit(f"op kind '{op.get('kind')}' not allowed for lane '{lane}'")

rpc = os.environ["STARKNET_RPC"]
account = os.environ["STARKNET_ACCOUNT"]
keystore = os.environ["STARKNET_KEYSTORE"]
ledger_path = os.environ["STARKNET_LEDGER_PATH"]

if not (keystore and ledger_path):
    raise SystemExit("keystore + ledger are required for apply")


def run_cmd(cmd):
    proc = subprocess.run(cmd, text=True, capture_output=True)
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    return (proc.stdout or "") + (proc.stderr or "")


def selector_for(entrypoint):
    out = run_cmd(["starkli", "selector", entrypoint])
    matches = re.findall(r"0x[0-9a-fA-F]+", out)
    if not matches:
        raise SystemExit(f"Failed to derive selector for {entrypoint}")
    return matches[-1]


def extract_tx_hash(output):
    patterns = [
        r"transaction_hash\"?[: ]+\"?(0x[0-9a-fA-F]+)",
        r"Transaction hash[: ]+(0x[0-9a-fA-F]+)",
    ]
    for pat in patterns:
        m = re.search(pat, output)
        if m:
            return m.group(1)
    # fallback
    m = re.search(r"0x[0-9a-fA-F]{10,}", output)
    if m:
        return m.group(0)
    return ""


txs = []
for idx, op in enumerate(ops, start=1):
    kind = op.get("kind")
    if kind != "invoke":
        raise SystemExit(f"Unsupported op kind for apply: {kind}")

    target = op.get("contract_address")
    if not target and isinstance(op.get("target"), dict):
        target = op["target"].get("address")
    if not target:
        raise SystemExit("invoke op missing contract address")

    entrypoint = op.get("entrypoint")
    selector = op.get("selector")
    if not selector:
        if not entrypoint:
            raise SystemExit("invoke op missing entrypoint/selector")
        selector = selector_for(entrypoint)

    calldata = op.get("calldata") or []
    if not isinstance(calldata, list):
        raise SystemExit("invoke op calldata must be a list")
    calldata = [str(item) for item in calldata]

    ledger_flags = ["--ledger"] if ledger_path.lower() in {"1", "true", "yes"} else ["--ledger-path", ledger_path]
    cmd = [
        "starkli",
        "invoke",
        "--rpc", rpc,
        "--account", account,
        "--keystore", keystore,
    ] + ledger_flags + [
        target,
        selector,
    ] + calldata

    output = run_cmd(cmd)
    tx_hash = extract_tx_hash(output)
    if not tx_hash:
        raise SystemExit("Failed to parse transaction hash from invoke output")

    txs.append({
        "id": op.get("id", f"op_{idx}"),
        "kind": kind,
        "contract_address": target,
        "entrypoint": entrypoint or selector,
        "selector": selector,
        "calldata": calldata,
        "tx_hash": tx_hash,
    })


txs_payload = {
    "network": network,
    "lane": lane,
    "run_id": run_id,
    "executed_at": datetime.now(timezone.utc).isoformat(),
    "ops": txs,
}

out_path = bundle_dir / "txs.json"
if out_path.exists():
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_path.rename(bundle_dir / f"txs.prev.{ts}.json")

out_path.write_text(json.dumps(txs_payload, indent=2, sort_keys=True) + "\n")
print(f"Wrote {out_path}")
PY
