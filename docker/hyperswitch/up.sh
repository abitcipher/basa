#!/usr/bin/env bash
# Starts a local Hyperswitch (router API on :8080, payment page SDK on :9050).
#   docker/hyperswitch/up.sh            # start
#   docker/hyperswitch/up.sh down       # stop
# Needs Hyperswitch checked out next to BASA:
#   git clone --depth 1 --branch latest https://github.com/juspay/hyperswitch ../hyperswitch
# The analytics hooks and the Control Center are not started.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
hs="${HYPERSWITCH_DIR:-$here/../../../hyperswitch}"
compose=(docker compose -p basa-hyperswitch -f "$hs/docker-compose.yml" -f "$here/compose.override.yml")

if [[ "${1:-up}" == "down" ]]; then
  "${compose[@]}" down
else
  "${compose[@]}" up -d hyperswitch-server hyperswitch-web
  echo "Router: http://localhost:8080 (admin key: test_admin) · SDK: http://localhost:9050"
fi
