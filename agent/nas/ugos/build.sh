#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <amd64-agent> <arm64-agent> [build-number] [output-directory]" >&2
  exit 2
fi

AMD64_BINARY="$1"
ARM64_BINARY="$2"
BUILD_NUMBER="${3:-1}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${4:-$SCRIPT_DIR/../../../dist/nas/packages}"
STATUS_PAGE="$SCRIPT_DIR/../../src/management/nas_status.html"

[ -f "$AMD64_BINARY" ] || { echo "amd64 Agent binary not found: $AMD64_BINARY" >&2; exit 1; }
[ -f "$ARM64_BINARY" ] || { echo "arm64 Agent binary not found: $ARM64_BINARY" >&2; exit 1; }
case "$BUILD_NUMBER" in
  ''|*[!0-9]*) echo "Build number must be numeric" >&2; exit 2 ;;
esac
command -v ugcli >/dev/null 2>&1 || {
  echo "ugcli is required to build an official UGOS Pro .upk package" >&2
  exit 1
}

VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$SCRIPT_DIR/../../Cargo.toml" | sed -n '1p')"
WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT HUP INT TERM

cp -R "$SCRIPT_DIR/." "$WORK_DIR/"
rm -f "$WORK_DIR/rootfs_amd64/bin/.keep" "$WORK_DIR/rootfs_arm64/bin/.keep" "$WORK_DIR/rootfs_common/www/.keep"
install -m 0755 "$AMD64_BINARY" "$WORK_DIR/rootfs_amd64/bin/nanolink-agent"
install -m 0755 "$ARM64_BINARY" "$WORK_DIR/rootfs_arm64/bin/nanolink-agent"
install -m 0644 "$STATUS_PAGE" "$WORK_DIR/rootfs_common/www/index.html"
mkdir -p "$OUTPUT_DIR"

awk -v version="$VERSION" '
  /^version:/ { printf "version: %s\n", version; next }
  { print }
' "$WORK_DIR/project.yaml" > "$WORK_DIR/project.yaml.new"
mv "$WORK_DIR/project.yaml.new" "$WORK_DIR/project.yaml"

(cd "$WORK_DIR" && ugcli check && ugcli pack --arch all --build "$BUILD_NUMBER")
FOUND="false"
for package in "$WORK_DIR"/build_dir/pkgs/upk/*.upk; do
  [ -f "$package" ] || continue
  FOUND="true"
  destination="$OUTPUT_DIR/$(basename "$package")"
  mv "$package" "$destination"
  echo "$destination"
done
[ "$FOUND" = "true" ] || { echo "ugcli did not produce an .upk file" >&2; exit 1; }
