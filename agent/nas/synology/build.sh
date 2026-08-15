#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <agent-binary> <x86_64|armv8> [output-directory]" >&2
  exit 2
fi

BINARY="$1"
ARCH="$2"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${3:-$SCRIPT_DIR/../../../dist/nas/packages}"

[ -f "$BINARY" ] || { echo "Agent binary not found: $BINARY" >&2; exit 1; }
case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  armv8|arm64|aarch64) ARCH="armv8" ;;
  *) echo "Unsupported Synology architecture: $ARCH" >&2; exit 2 ;;
esac

VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$SCRIPT_DIR/../../Cargo.toml" | sed -n '1p')"
WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT HUP INT TERM
export COPYFILE_DISABLE=1

mkdir -p "$WORK_DIR/spk" "$WORK_DIR/payload/bin" "$OUTPUT_DIR"
cp -R "$SCRIPT_DIR/package/." "$WORK_DIR/spk/"
cp -R "$SCRIPT_DIR/payload/." "$WORK_DIR/payload/"
install -m 0755 "$BINARY" "$WORK_DIR/payload/bin/nanolink-agent"

awk -v version="$VERSION" -v arch="$ARCH" '
  { gsub(/@VERSION@/, version); gsub(/@ARCH@/, arch); print }
' "$WORK_DIR/spk/INFO" > "$WORK_DIR/spk/INFO.new"
mv "$WORK_DIR/spk/INFO.new" "$WORK_DIR/spk/INFO"
chmod 0755 "$WORK_DIR/spk/scripts/"*

tar -czf "$WORK_DIR/spk/package.tgz" -C "$WORK_DIR/payload" bin ui port_conf
DESTINATION="$OUTPUT_DIR/NanoLinkAgent-${VERSION}-1_${ARCH}.spk"
tar -cf "$DESTINATION" -C "$WORK_DIR/spk" \
  INFO package.tgz scripts conf WIZARD_UIFILES PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG
echo "$DESTINATION"
