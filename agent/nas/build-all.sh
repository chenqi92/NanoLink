#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 <amd64-agent> <arm64-agent> [ugos-build-number] [output-directory]" >&2
  exit 2
fi

AMD64_BINARY="$1"
ARM64_BINARY="$2"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
BUILD_NUMBER="${3:-1}"
OUTPUT_DIR="${4:-$SCRIPT_DIR/../../dist/nas/packages}"

[ -f "$AMD64_BINARY" ] || { echo "amd64 Agent binary not found: $AMD64_BINARY" >&2; exit 1; }
[ -f "$ARM64_BINARY" ] || { echo "arm64 Agent binary not found: $ARM64_BINARY" >&2; exit 1; }
case "$BUILD_NUMBER" in
  ''|*[!0-9]*) echo "UGOS build number must be numeric" >&2; exit 2 ;;
esac

mkdir -p "$OUTPUT_DIR"
"$SCRIPT_DIR/validate.sh"

"$SCRIPT_DIR/fnos/build.sh" "$AMD64_BINARY" x86 "$OUTPUT_DIR"
"$SCRIPT_DIR/fnos/build.sh" "$ARM64_BINARY" arm "$OUTPUT_DIR"
"$SCRIPT_DIR/synology/build.sh" "$AMD64_BINARY" x86_64 "$OUTPUT_DIR"
"$SCRIPT_DIR/synology/build.sh" "$ARM64_BINARY" armv8 "$OUTPUT_DIR"
"$SCRIPT_DIR/ugos/build.sh" "$AMD64_BINARY" "$ARM64_BINARY" "$BUILD_NUMBER" "$OUTPUT_DIR"

VERSION="$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$SCRIPT_DIR/../Cargo.toml" | sed -n '1p')"
UGOS_BUILD="$(printf '%04d' "$BUILD_NUMBER")"
for package in \
  "$OUTPUT_DIR/nanolink-agent_${VERSION}_x86.fpk" \
  "$OUTPUT_DIR/nanolink-agent_${VERSION}_arm.fpk" \
  "$OUTPUT_DIR/NanoLinkAgent-${VERSION}-1_x86_64.spk" \
  "$OUTPUT_DIR/NanoLinkAgent-${VERSION}-1_armv8.spk" \
  "$OUTPUT_DIR/amd64_com.nanoops.nanolinkagent_${VERSION}.${UGOS_BUILD}.upk" \
  "$OUTPUT_DIR/arm64_com.nanoops.nanolinkagent_${VERSION}.${UGOS_BUILD}.upk"
do
  [ -s "$package" ] || { echo "Expected NAS package was not produced: $package" >&2; exit 1; }
done

(cd "$OUTPUT_DIR" && sha256sum \
  "nanolink-agent_${VERSION}_x86.fpk" \
  "nanolink-agent_${VERSION}_arm.fpk" \
  "NanoLinkAgent-${VERSION}-1_x86_64.spk" \
  "NanoLinkAgent-${VERSION}-1_armv8.spk" \
  "amd64_com.nanoops.nanolinkagent_${VERSION}.${UGOS_BUILD}.upk" \
  "arm64_com.nanoops.nanolinkagent_${VERSION}.${UGOS_BUILD}.upk" \
  > SHA256SUMS.txt)
