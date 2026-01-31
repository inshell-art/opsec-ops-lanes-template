#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

ROOT_DIR="$ROOT_DIR" python3 - <<'PY'
from __future__ import annotations
import os
import time
from pathlib import Path

state_file = Path(os.environ["ROOT_DIR"]) / "artifacts" / "salt_counter.txt"
state_file.parent.mkdir(parents=True, exist_ok=True)

now = int(time.time())
if state_file.exists():
    try:
        last = int(state_file.read_text().strip())
    except ValueError:
        last = 0
else:
    last = 0

next_value = now if now > last else last + 1
state_file.write_text(str(next_value))
print(next_value)
PY
