#!/usr/bin/env bash
set -euo pipefail

NETWORK=${NETWORK:-}
LANE=${LANE:-}
RUN_ID=${RUN_ID:-}
FORCE=${FORCE:-0}

if [[ -z "$NETWORK" || -z "$LANE" || -z "$RUN_ID" ]]; then
  echo "Usage: NETWORK=<devnet|sepolia|mainnet> LANE=<observe|plan|deploy|handoff|govern|treasury|operate|emergency> RUN_ID=<id> $0" >&2
  exit 2
fi

case "$NETWORK" in
  devnet|sepolia|mainnet) ;;
  *) echo "Invalid NETWORK: $NETWORK" >&2; exit 2 ;;
esac

case "$LANE" in
  observe|plan|deploy|handoff|govern|treasury|operate|emergency) ;;
  *) echo "Invalid LANE: $LANE" >&2; exit 2 ;;
esac

ROOT=$(git rev-parse --show-toplevel)
BUNDLE_DIR="$ROOT/bundles/$NETWORK/$RUN_ID"

if [[ -d "$BUNDLE_DIR" ]] && [[ -n "$(ls -A "$BUNDLE_DIR" 2>/dev/null)" ]] && [[ "$FORCE" != "1" ]]; then
  echo "Bundle dir already exists and is not empty: $BUNDLE_DIR" >&2
  echo "Set FORCE=1 to overwrite." >&2
  exit 2
fi

mkdir -p "$BUNDLE_DIR"

POLICY_FILE=""
for candidate in \
  "$ROOT/ops/policy/lane.${NETWORK}.json" \
  "$ROOT/ops/policy/${NETWORK}.policy.json" \
  "$ROOT/ops/policy/lane.${NETWORK}.example.json" \
  "$ROOT/ops/policy/${NETWORK}.policy.example.json" \
  "$ROOT/policy/${NETWORK}.policy.example.json"
do
  if [[ -f "$candidate" ]]; then
    POLICY_FILE="$candidate"
    break
  fi
done

GIT_COMMIT=$(git rev-parse HEAD)
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export BUNDLE_DIR NETWORK LANE RUN_ID GIT_COMMIT CREATED_AT ROOT POLICY_FILE

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


bundle_dir = Path(os.environ["BUNDLE_DIR"])
root = Path(os.environ["ROOT"])
network = os.environ["NETWORK"]
lane = os.environ["LANE"]
run_id = os.environ["RUN_ID"]
git_commit = os.environ["GIT_COMMIT"]
created_at = os.environ["CREATED_AT"]
policy_file = os.environ.get("POLICY_FILE", "")

policy = {}
if policy_file and Path(policy_file).exists():
    policy = json.loads(Path(policy_file).read_text())

lane_cfg = ((policy.get("lanes") or {}).get(lane) or {})
required_checks = lane_cfg.get("required_checks", [])
if not isinstance(required_checks, list):
    required_checks = []

deploy_params_defaults = {
    "required_networks": ["sepolia", "mainnet"],
    "required_lanes": ["deploy"],
    "bundle_filename": "deploy_params.json",
    "apply_env_var": "DEPLOY_PARAMS_FILE",
    "canonicalization": "json_sorted",
    "allow_external_override": False,
    "schema_file": "schemas/deploy_params.schema.json",
    "semantic_validator_cmd": "",
}

deploy_params_cfg = dict(deploy_params_defaults)
if isinstance(policy.get("deploy_params"), dict):
    deploy_params_cfg.update(policy["deploy_params"])

required_networks = deploy_params_cfg.get("required_networks", [])
required_lanes = deploy_params_cfg.get("required_lanes", [])
if not isinstance(required_networks, list):
    required_networks = []
if not isinstance(required_lanes, list):
    required_lanes = []

requires_deploy_params = (
    network in required_networks
    and lane in required_lanes
    and "deploy_params_pinned" in required_checks
)

params_env_var = str(deploy_params_cfg.get("apply_env_var", "DEPLOY_PARAMS_FILE"))
params_filename = str(deploy_params_cfg.get("bundle_filename", "deploy_params.json"))
canonicalization = str(deploy_params_cfg.get("canonicalization", "json_sorted"))
if canonicalization != "json_sorted":
    raise SystemExit(f"unsupported deploy params canonicalization: {canonicalization}")
params_source_path = os.environ.get(params_env_var, "").strip()
include_deploy_params = bool(params_source_path) or requires_deploy_params

deploy_params_sha256 = ""
if include_deploy_params:
    if not params_source_path:
        raise SystemExit(
            f"Missing required deploy params source. Set {params_env_var}=<path> for {network}/{lane}."
        )
    params_source = Path(params_source_path)
    if not params_source.exists():
        raise SystemExit(f"Deploy params source file not found: {params_source}")
    payload = json.loads(params_source.read_text())
    canonicalized = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    bundle_params_path = bundle_dir / params_filename
    bundle_params_path.write_text(canonicalized)
    deploy_params_sha256 = sha256_bytes(bundle_params_path.read_bytes())

run = {
    "run_id": run_id,
    "network": network,
    "lane": lane,
    "git_commit": git_commit,
    "created_at": created_at,
}
intent = {
    "intent_version": 1,
    "network": network,
    "lane": lane,
    "ops": ["stub"],
    "notes": "Scaffold stub. Replace with real intent generation.",
}
if deploy_params_sha256:
    intent["deploy_params_sha256"] = deploy_params_sha256

checks = {
    "checks_version": 1,
    "network": network,
    "lane": lane,
    "pass": True,
    "stub": True,
    "notes": "Scaffold stub. Replace with real checks/simulations.",
}
if include_deploy_params:
    checks["deploy_params_pinned"] = bool(deploy_params_sha256)

(bundle_dir / "run.json").write_text(json.dumps(run, indent=2, sort_keys=True) + "\n")
(bundle_dir / "intent.json").write_text(json.dumps(intent, indent=2, sort_keys=True) + "\n")
(bundle_dir / "checks.json").write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")

immutable_files = ["run.json", "intent.json", "checks.json"]
if deploy_params_sha256:
    immutable_files.append(params_filename)

items = []
for name in immutable_files:
    data = (bundle_dir / name).read_bytes()
    digest = sha256_bytes(data)
    items.append({"path": name, "sha256": digest})

bundle_hash_input = "\n".join([f"{i['path']}={i['sha256']}" for i in items]).encode()
bundle_hash = sha256_bytes(bundle_hash_input)

manifest = {
    "manifest_version": 1,
    "bundle_hash": bundle_hash,
    "network": network,
    "lane": lane,
    "run_id": run_id,
    "git_commit": git_commit,
    "generated_at": created_at,
    "immutable_files": items,
}

(bundle_dir / "bundle_manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

if deploy_params_sha256:
    print(f"Bundle created at {bundle_dir} (deploy_params_sha256={deploy_params_sha256})")
else:
    print(f"Bundle created at {bundle_dir}")
PY
