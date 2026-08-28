#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

require_file() {
  [ -f "$1" ] || { echo "Missing required file: $1" >&2; exit 1; }
}

validate_json() {
  if command -v jq >/dev/null 2>&1; then
    jq empty "$1"
  else
    python3 -m json.tool "$1" >/dev/null
  fi
}

for file in \
  "$SCRIPT_DIR/fnos/package/manifest" \
  "$SCRIPT_DIR/fnos/package/config/privilege" \
  "$SCRIPT_DIR/fnos/package/config/resource" \
  "$SCRIPT_DIR/fnos/package/ICON.PNG" \
  "$SCRIPT_DIR/fnos/package/ICON_256.PNG" \
  "$SCRIPT_DIR/fnos/package/cmd/main" \
  "$SCRIPT_DIR/fnos/package/app/ui/config" \
  "$SCRIPT_DIR/fnos/package/app/ui/images/64.png" \
  "$SCRIPT_DIR/fnos/package/app/ui/images/256.png" \
  "$SCRIPT_DIR/fnos/package/wizard/install" \
  "$SCRIPT_DIR/fnos/package/wizard/config" \
  "$SCRIPT_DIR/synology/package/INFO" \
  "$SCRIPT_DIR/synology/package/conf/privilege" \
  "$SCRIPT_DIR/synology/package/conf/resource" \
  "$SCRIPT_DIR/synology/package/scripts/start-stop-status" \
  "$SCRIPT_DIR/synology/payload/ui/config" \
  "$SCRIPT_DIR/synology/payload/port_conf/NanoOpsAgent.sc" \
  "$SCRIPT_DIR/synology/package/PACKAGE_ICON.PNG" \
  "$SCRIPT_DIR/synology/package/PACKAGE_ICON_256.PNG" \
  "$SCRIPT_DIR/ugos/project.yaml" \
  "$SCRIPT_DIR/ugos/rootfs_common/icon.png" \
  "$SCRIPT_DIR/ugos/rootfs_common/www/.keep" \
  "$SCRIPT_DIR/ugos/rootfs_amd64/bin/.keep" \
  "$SCRIPT_DIR/ugos/rootfs_arm64/bin/.keep" \
  "$SCRIPT_DIR/../src/management/nas_status.html"
do
  require_file "$file"
done

find "$SCRIPT_DIR/fnos/package/config" "$SCRIPT_DIR/fnos/package/wizard" \
  "$SCRIPT_DIR/synology/package/conf" "$SCRIPT_DIR/synology/package/WIZARD_UIFILES" \
  -type f | while IFS= read -r file; do validate_json "$file"; done
validate_json "$SCRIPT_DIR/fnos/package/app/ui/config"
validate_json "$SCRIPT_DIR/synology/payload/ui/config"

find "$SCRIPT_DIR" -type f \( -name '*.sh' -o -path '*/cmd/*' -o -path '*/scripts/*' \) \
  | while IFS= read -r file; do sh -n "$file"; done

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], permitted_symbols: [], aliases: false)' "$SCRIPT_DIR/ugos/project.yaml"
fi

grep -q '^appname[[:space:]]*=' "$SCRIPT_DIR/fnos/package/manifest"
grep -q '^desktop_uidir[[:space:]]*=' "$SCRIPT_DIR/fnos/package/manifest"
grep -q '"nanolink-agent\.' "$SCRIPT_DIR/fnos/package/app/ui/config"
grep -q 'run-as.*package' "$SCRIPT_DIR/fnos/package/config/privilege"
grep -q 'os_min_ver="7.0-40000"' "$SCRIPT_DIR/synology/package/INFO"
grep -q 'run-as.*package' "$SCRIPT_DIR/synology/package/conf/privilege"
grep -q '^spec_version: "2.1"' "$SCRIPT_DIR/ugos/project.yaml"
grep -q 'NETWORK.ACCESS_INTERNET' "$SCRIPT_DIR/ugos/project.yaml"
grep -q 'build_dir/pkgs/upk' "$SCRIPT_DIR/ugos/build.sh"
grep -q 'nas-start --config-path' "$SCRIPT_DIR/fnos/package/cmd/main"
grep -q 'nas-start --config-path' "$SCRIPT_DIR/synology/package/scripts/start-stop-status"
if grep -q 'SYSTEM.EXEC_SYSTEM_COMMAND' "$SCRIPT_DIR/ugos/project.yaml"; then
  echo "UGOS package must not request system-command permission" >&2
  exit 1
fi

echo "NAS package sources are structurally valid"
