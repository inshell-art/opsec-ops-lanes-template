#!/usr/bin/env bash
set -euo pipefail

if [[ "${OPS_LANES_SIGNING_CONTEXT:-}" != "1" ]]; then
  echo "Refusing to run: apply must run in signing context."
  echo "Set OPS_LANES_SIGNING_CONTEXT=1 only on the signing OS."
  exit 2
fi

echo "TODO: implement apply for your repo."
echo "This stub fails by design."
exit 2
