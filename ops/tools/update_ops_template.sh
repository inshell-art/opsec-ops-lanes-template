#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
cd "$ROOT_DIR"

echo "Updating ops-lanes template subtree..."

git subtree pull \
  --prefix opsec-ops-lanes-template \
  https://github.com/inshell-art/opsec-ops-lanes-template.git \
  main \
  --squash

echo "Subtree update complete. Review and push if desired."
