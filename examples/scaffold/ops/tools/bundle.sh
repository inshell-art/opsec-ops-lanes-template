#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
NETWORK="${NETWORK:-}"
LANE="${LANE:-}"
RUN_ID="${RUN_ID:-}"
POLICY_TEMPLATE="${POLICY_TEMPLATE:-}"
INTENT_TEMPLATE="${INTENT_TEMPLATE:-}"
FORCE="${FORCE:-0}"

if [[ -z "$NETWORK" || -z "$LANE" ]]; then
  echo "Missing NETWORK or LANE env vars." >&2
  exit 1
fi

if [[ -z "$RUN_ID" ]]; then
  if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
    RUN_ID="$GITHUB_RUN_ID"
  else
    RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
  fi
fi

BUNDLE_DIR="$ROOT_DIR/bundles/$NETWORK/$RUN_ID"
if [[ -d "$BUNDLE_DIR" ]] && [[ -n "$(ls -A "$BUNDLE_DIR" 2>/dev/null)" ]] && [[ "$FORCE" != "1" ]]; then
  echo "Bundle dir already exists and is not empty: $BUNDLE_DIR" >&2
  echo "Set FORCE=1 to overwrite." >&2
  exit 1
fi
mkdir -p "$BUNDLE_DIR"

if [[ -z "$POLICY_TEMPLATE" ]]; then
  if [[ -n "$NETWORK" && -f "$ROOT_DIR/ops/policy/${NETWORK}.policy.json" ]]; then
    POLICY_TEMPLATE="$ROOT_DIR/ops/policy/${NETWORK}.policy.json"
  elif [[ -f "$ROOT_DIR/ops/policy/policy.template.json" ]]; then
    POLICY_TEMPLATE="$ROOT_DIR/ops/policy/policy.template.json"
  fi
fi

if [[ -z "$POLICY_TEMPLATE" || ! -f "$POLICY_TEMPLATE" ]]; then
  echo "Missing policy template: $POLICY_TEMPLATE" >&2
  exit 1
fi

GIT_COMMIT=$(git rev-parse HEAD)
GIT_DIRTY="false"
if [[ -n "$(git status --porcelain)" ]]; then
  GIT_DIRTY="true"
fi

CREATED_AT=$(python3 - <<'PY'
import os
from datetime import datetime, timezone

epoch = os.environ.get("SOURCE_DATE_EPOCH")
if epoch:
    ts = datetime.fromtimestamp(int(epoch), tz=timezone.utc)
else:
    ts = datetime.now(timezone.utc)
print(ts.isoformat())
PY
)

RUN_JSON="$BUNDLE_DIR/run.json"
POLICY_JSON="$BUNDLE_DIR/policy.json"
INTENT_JSON="$BUNDLE_DIR/intent.json"
CHECKS_JSON="$BUNDLE_DIR/checks.json"
MANIFEST_JSON="$BUNDLE_DIR/bundle_manifest.json"

export NETWORK LANE RUN_ID GIT_COMMIT GIT_DIRTY CREATED_AT
export POLICY_TEMPLATE INTENT_TEMPLATE BUNDLE_DIR
export RUN_JSON POLICY_JSON INTENT_JSON CHECKS_JSON MANIFEST_JSON

python3 - <<'PY'
import json
import os
from pathlib import Path

run = {
    "run_id": os.environ["RUN_ID"],
    "network": os.environ["NETWORK"],
    "lane": os.environ["LANE"],
    "git_commit": os.environ["GIT_COMMIT"],
    "git_dirty": os.environ["GIT_DIRTY"] == "true",
    "created_at": os.environ["CREATED_AT"],
    "generator": {
        "tool": "ops/tools/bundle.sh",
        "version": "1"
    }
}
Path(os.environ["RUN_JSON"]).write_text(json.dumps(run, indent=2, sort_keys=True) + "\n")
PY

python3 - <<'PY'
import json
import os
from pathlib import Path

policy_path = Path(os.environ["POLICY_TEMPLATE"])
policy = json.loads(policy_path.read_text())
lane = os.environ["LANE"]
if lane not in policy.get("lanes", {}):
    raise SystemExit(f"lane '{lane}' not defined in policy template")
policy["snapshot"] = {
    "network": os.environ["NETWORK"],
    "lane": lane,
    "created_at": os.environ["CREATED_AT"],
}
Path(os.environ["POLICY_JSON"]).write_text(json.dumps(policy, indent=2, sort_keys=True) + "\n")
PY

python3 - <<'PY'
import json
import os
from pathlib import Path

intent_path = os.environ.get("INTENT_TEMPLATE")
if intent_path:
    intent = json.loads(Path(intent_path).read_text())
else:
    intent = {
        "intent_version": "1",
        "network": os.environ["NETWORK"],
        "lane": os.environ["LANE"],
        "ops": [],
        "description": "Template intent. Populate ops before approval/apply.",
        "created_at": os.environ["CREATED_AT"],
    }

intent.setdefault("network", os.environ["NETWORK"])
intent.setdefault("lane", os.environ["LANE"])
intent.setdefault("created_at", os.environ["CREATED_AT"])

if intent["network"] != os.environ["NETWORK"]:
    raise SystemExit("intent.json network mismatch")
if intent["lane"] != os.environ["LANE"]:
    raise SystemExit("intent.json lane mismatch")

Path(os.environ["INTENT_JSON"]).write_text(json.dumps(intent, indent=2, sort_keys=True) + "\n")
PY

python3 - <<'PY'
import json
import os
from pathlib import Path

policy = json.loads(Path(os.environ["POLICY_JSON"]).read_text())
lane = os.environ["LANE"]
required = policy.get("lanes", {}).get(lane, {}).get("required_checks")
if required is None:
    required = policy.get("lane_defaults", {}).get("required_checks", [])

checks = {
    "checks_version": "1",
    "network": os.environ["NETWORK"],
    "lane": lane,
    "required_checks": required,
    "checks": [
        {"name": "bundle_manifest", "status": "pending", "details": "manifest not yet generated"}
    ],
    "status": "pending",
    "generated_at": os.environ["CREATED_AT"],
    "notes": "CI-generated placeholder. Populate required checks before approval/apply."
}
Path(os.environ["CHECKS_JSON"]).write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")
PY

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
files = ["intent.json", "checks.json", "run.json", "policy.json"]
entries = []
for name in sorted(files):
    path = bundle_dir / name
    data = path.read_bytes()
    entries.append({
        "path": name,
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
    })

manifest = {
    "manifest_version": "1",
    "bundle": {
        "network": os.environ["NETWORK"],
        "lane": os.environ["LANE"],
        "run_id": os.environ["RUN_ID"],
    },
    "created_at": os.environ["CREATED_AT"],
    "files": entries,
}

Path(os.environ["MANIFEST_JSON"]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY

python3 - <<'PY'
import json
import os
from pathlib import Path

checks_path = Path(os.environ["CHECKS_JSON"])
checks = json.loads(checks_path.read_text())
required = checks.get("required_checks", [])
entries = checks.get("checks", [])
found = False
for entry in entries:
    if entry.get("name") == "bundle_manifest":
        entry["status"] = "pass"
        entry["details"] = "manifest hash recorded at bundle time"
        found = True
        break
if not found:
    entries.append({"name": "bundle_manifest", "status": "pass", "details": "manifest hash recorded at bundle time"})
checks["checks"] = entries

status_map = {c.get("name"): c.get("status") for c in entries}
missing = [name for name in required if status_map.get(name) != "pass"]
checks["status"] = "pass" if not missing else "pending"
checks["missing_required_checks"] = missing
checks_path.write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")
PY

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

bundle_dir = Path(os.environ["BUNDLE_DIR"])
files = ["intent.json", "checks.json", "run.json", "policy.json"]
entries = []
for name in sorted(files):
    path = bundle_dir / name
    data = path.read_bytes()
    entries.append({
        "path": name,
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
    })

manifest = {
    "manifest_version": "1",
    "bundle": {
        "network": os.environ["NETWORK"],
        "lane": os.environ["LANE"],
        "run_id": os.environ["RUN_ID"],
    },
    "created_at": os.environ["CREATED_AT"],
    "files": entries,
}

Path(os.environ["MANIFEST_JSON"]).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PY

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "run_id=$RUN_ID"
    echo "bundle_dir=$BUNDLE_DIR"
  } >> "$GITHUB_OUTPUT"
fi

cat <<SUMMARY
Bundle created
- network: $NETWORK
- lane: $LANE
- run_id: $RUN_ID
- dir: $BUNDLE_DIR
SUMMARY
