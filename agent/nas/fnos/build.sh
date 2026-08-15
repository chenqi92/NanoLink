#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <agent-binary> <x86|arm> [output-directory]" >&2
  exit 2
fi

BINARY="$1"
PLATFORM="$2"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${3:-$SCRIPT_DIR/../../../dist/nas/packages}"

[ -f "$BINARY" ] || { echo "Agent binary not found: $BINARY" >&2; exit 1; }
command -v fnpack >/dev/null 2>&1 || {
  echo "fnpack is required to build an official fnOS .fpk package" >&2
  exit 1
}

case "$PLATFORM" in
  x86|x86_64|amd64) PLATFORM="x86" ;;
  arm|arm64|aarch64) PLATFORM="arm" ;;
  *) echo "Unsupported fnOS platform: $PLATFORM" >&2; exit 2 ;;
esac

VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$SCRIPT_DIR/../../Cargo.toml" | sed -n '1p')"
WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT HUP INT TERM

cp -R "$SCRIPT_DIR/package/." "$WORK_DIR/"
mkdir -p "$WORK_DIR/app/bin" "$OUTPUT_DIR"
install -m 0755 "$BINARY" "$WORK_DIR/app/bin/nanolink-agent"

awk -v version="$VERSION" -v platform="$PLATFORM" '
  /^version[[:space:]]*=/ { printf "version                = %s\n", version; next }
  /^platform[[:space:]]*=/ { printf "platform               = %s\n", platform; next }
  { print }
' "$WORK_DIR/manifest" > "$WORK_DIR/manifest.new"
mv "$WORK_DIR/manifest.new" "$WORK_DIR/manifest"

(cd "$WORK_DIR" && fnpack build)
FPK="$(find "$WORK_DIR" -maxdepth 1 -type f -name '*.fpk' -print | sed -n '1p')"
[ -n "$FPK" ] || { echo "fnpack did not produce an .fpk file" >&2; exit 1; }
DESTINATION="$OUTPUT_DIR/nanolink-agent_${VERSION}_${PLATFORM}.fpk"
mv "$FPK" "$DESTINATION"
echo "$DESTINATION"
