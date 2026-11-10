#!/bin/sh
# Updates and starts BASA on this machine. Run from the repository, with
# .env in place. Safe to run again: migrations and seeds are idempotent.
set -eu

cd "$(dirname "$0")/.."

[ -f .env ] || { echo "No .env here: copy .env.example to .env and fill it in." >&2; exit 1; }

if [ "${1:-}" != "--no-pull" ]; then
  git pull --ff-only
fi

docker compose --profile prod build
docker compose --profile prod up -d --remove-orphans
docker compose --profile prod ps
