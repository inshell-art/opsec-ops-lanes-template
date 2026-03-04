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

export BUNDLE_DIR

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
manifest_path = bundle_dir / "bundle_manifest.json"
manifest = json.loads(manifest_path.read_text())

items = manifest.get("immutable_files", [])
if not items:
    raise SystemExit("manifest has no immutable_files")

required = {"run.json", "intent.json", "checks.json"}
paths = {item.get("path") for item in items}
missing = required - paths
if missing:
    raise SystemExit(f"manifest missing required files: {', '.join(sorted(missing))}")

recomputed = []
for item in items:
    path = item.get("path")
    if not path:
        raise SystemExit("manifest entry missing path")
    data = (bundle_dir / path).read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != item.get("sha256"):
        raise SystemExit(f"hash mismatch for {path}")
    recomputed.append({"path": path, "sha256": digest})

bundle_hash_input = "\n".join([f"{i['path']}={i['sha256']}" for i in recomputed]).encode()
expected_bundle_hash = hashlib.sha256(bundle_hash_input).hexdigest()
if expected_bundle_hash != manifest.get("bundle_hash"):
    raise SystemExit("bundle_hash mismatch")

print("Manifest hashes verified")
PY

if [[ ! -f "$BUNDLE_DIR/run.json" ]]; then
  echo "Missing run.json" >&2
  exit 2
fi

RUN_COMMIT=$(python3 - <<'PY'
import json
import os
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
run = json.loads((bundle_dir / "run.json").read_text())
print(run.get("git_commit", ""))
PY
)

if [[ -z "$RUN_COMMIT" ]]; then
  echo "run.json missing git_commit" >&2
  exit 2
fi

CURRENT_COMMIT=$(git rev-parse HEAD)
if [[ "$CURRENT_COMMIT" != "$RUN_COMMIT" ]]; then
  echo "Commit mismatch: run.json=$RUN_COMMIT current=$CURRENT_COMMIT" >&2
  exit 2
fi

NETWORK_FROM_RUN=$(python3 - <<'PY'
import json
import os
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
run = json.loads((bundle_dir / "run.json").read_text())
print(run.get("network", ""))
PY
)

LANE_FROM_RUN=$(python3 - <<'PY'
import json
import os
from pathlib import Path
bundle_dir = Path(os.environ["BUNDLE_DIR"])
run = json.loads((bundle_dir / "run.json").read_text())
print(run.get("lane", ""))
PY
)

if [[ -z "$NETWORK_FROM_RUN" || -z "$LANE_FROM_RUN" ]]; then
  echo "run.json missing network or lane" >&2
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

LANE_OK=$(POLICY_FILE="$POLICY_FILE" RUN_LANE="$LANE_FROM_RUN" python3 - <<'PY'
import json
import os
from pathlib import Path
policy_path = Path(os.environ["POLICY_FILE"])
run_lane = os.environ["RUN_LANE"]
policy = json.loads(policy_path.read_text())
lanes = policy.get("lanes", {})
print("ok" if run_lane in lanes else "missing")
PY
)

if [[ "$LANE_OK" != "ok" ]]; then
  echo "Lane '$LANE_FROM_RUN' not found in policy: $POLICY_FILE" >&2
  exit 2
fi

ROOT="$ROOT" POLICY_FILE="$POLICY_FILE" BUNDLE_DIR="$BUNDLE_DIR" RUN_NETWORK="$NETWORK_FROM_RUN" RUN_LANE="$LANE_FROM_RUN" python3 - <<'PY'
import hashlib
import json
import os
import subprocess
from pathlib import Path


def type_ok(value, expected):
    mapping = {
        "string": str,
        "number": (int, float),
        "integer": int,
        "boolean": bool,
        "object": dict,
        "array": list,
    }
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return (isinstance(value, (int, float)) and not isinstance(value, bool))
    py_type = mapping.get(expected)
    return isinstance(value, py_type) if py_type else True


def validate_schema(schema, value, path="$"):
    if "oneOf" in schema:
        errors = []
        for branch in schema["oneOf"]:
            try:
                validate_schema(branch, value, path)
                return
            except ValueError as exc:
                errors.append(str(exc))
        raise ValueError(f"{path}: oneOf validation failed ({'; '.join(errors)})")

    expected_type = schema.get("type")
    if isinstance(expected_type, list):
        if not any(type_ok(value, t) for t in expected_type):
            raise ValueError(f"{path}: expected one of types {expected_type}, got {type(value).__name__}")
    elif isinstance(expected_type, str):
        if not type_ok(value, expected_type):
            raise ValueError(f"{path}: expected type {expected_type}, got {type(value).__name__}")

    enum = schema.get("enum")
    if enum is not None and value not in enum:
        raise ValueError(f"{path}: value {value!r} not in enum {enum!r}")

    if isinstance(value, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in value:
                raise ValueError(f"{path}: missing required key '{key}'")
        for key, child_schema in schema.get("properties", {}).items():
            if key in value:
                validate_schema(child_schema, value[key], f"{path}.{key}")


root = Path(os.environ["ROOT"])
policy_path = Path(os.environ["POLICY_FILE"])
bundle_dir = Path(os.environ["BUNDLE_DIR"])
run_network = os.environ["RUN_NETWORK"]
run_lane = os.environ["RUN_LANE"]

policy = json.loads(policy_path.read_text())
lane_cfg = ((policy.get("lanes") or {}).get(run_lane) or {})
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
    run_network in required_networks
    and run_lane in required_lanes
    and "deploy_params_pinned" in required_checks
)

if not requires_deploy_params:
    print("Deploy params pinning check skipped")
    raise SystemExit(0)

params_filename = str(deploy_params_cfg.get("bundle_filename", "deploy_params.json"))
canonicalization = str(deploy_params_cfg.get("canonicalization", "json_sorted"))
if canonicalization != "json_sorted":
    raise SystemExit(f"unsupported deploy params canonicalization: {canonicalization}")
params_path = bundle_dir / params_filename
if not params_path.exists():
    raise SystemExit(f"deploy params required but missing: {params_path}")

manifest = json.loads((bundle_dir / "bundle_manifest.json").read_text())
manifest_entries = {
    item.get("path"): item.get("sha256")
    for item in (manifest.get("immutable_files") or [])
    if isinstance(item, dict)
}
if params_filename not in manifest_entries:
    raise SystemExit(f"deploy params not listed in immutable manifest: {params_filename}")

actual_hash = hashlib.sha256(params_path.read_bytes()).hexdigest()
if manifest_entries.get(params_filename) != actual_hash:
    raise SystemExit("deploy params hash mismatch against manifest")

intent = json.loads((bundle_dir / "intent.json").read_text())
intent_hash = intent.get("deploy_params_sha256", "")
if not intent_hash:
    raise SystemExit("intent.json missing deploy_params_sha256")
if intent_hash != actual_hash:
    raise SystemExit("deploy_params_sha256 mismatch: intent vs file")

checks = json.loads((bundle_dir / "checks.json").read_text())
if checks.get("deploy_params_pinned") is not True:
    raise SystemExit("checks.json requires deploy_params_pinned=true")

schema_rel = str(deploy_params_cfg.get("schema_file", "schemas/deploy_params.schema.json"))
schema_path = Path(schema_rel)
if not schema_path.is_absolute():
    schema_path = root / schema_rel
if not schema_path.exists():
    raise SystemExit(f"deploy params schema file not found: {schema_path}")

schema = json.loads(schema_path.read_text())
params_payload = json.loads(params_path.read_text())
validate_schema(schema, params_payload)

semantic_cmd = str(deploy_params_cfg.get("semantic_validator_cmd", "")).strip()
if semantic_cmd:
    env = os.environ.copy()
    env[str(deploy_params_cfg.get("apply_env_var", "DEPLOY_PARAMS_FILE"))] = str(params_path)
    proc = subprocess.run(semantic_cmd, shell=True, env=env, capture_output=True, text=True)
    if proc.returncode != 0:
        details = proc.stderr.strip() or proc.stdout.strip() or "semantic validator failed"
        raise SystemExit(f"semantic validator failed: {details}")

print(f"Deploy params pinned: {params_filename} sha256={actual_hash}")
PY

echo "Bundle verified: $BUNDLE_DIR"
