#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/../.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

run_dry_run() {
  bash "$repo_root/scripts/tasks/deploy-server.sh" \
    --dry-run --skip-checks --allow-dirty --config "$1"
}

default_config="$test_root/default.env"
cp "$repo_root/.env.deploy.example" "$default_config"
default_output=$(run_dry_run "$default_config")
grep -F 'Health target: http://127.0.0.1:8080/api/health' <<<"$default_output" >/dev/null

custom_config="$test_root/custom.env"
cp "$repo_root/.env.deploy.example" "$custom_config"
printf '\nDEPLOY_HOST_HTTP_PORT=49123\nDEPLOY_LOCAL_HEALTH_URL=http://127.0.0.1:49123/api/health\n' >> "$custom_config"
custom_output=$(run_dry_run "$custom_config")
grep -F 'Health target: http://127.0.0.1:49123/api/health' <<<"$custom_output" >/dev/null

invalid_config="$test_root/invalid.env"
cp "$repo_root/.env.deploy.example" "$invalid_config"
printf '\nDEPLOY_LOCAL_HEALTH_URL=http://0.0.0.0:8080/api/health\n' >> "$invalid_config"
if run_dry_run "$invalid_config" >"$test_root/invalid.out" 2>&1; then
  echo 'unsafe deployment health URL was accepted' >&2
  exit 1
fi
grep -F 'DEPLOY_LOCAL_HEALTH_URL must be a loopback URL' "$test_root/invalid.out" >/dev/null

echo 'deploy-server config tests passed'
