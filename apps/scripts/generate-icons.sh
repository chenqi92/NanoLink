#!/bin/bash
# Script to generate app icons from SVG for Flutter desktop apps
# Requires: rsvg-convert (librsvg) or ImageMagick

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$(dirname "$SCRIPT_DIR")"

SVG_FILE="$APPS_DIR/logo.svg"
SVG_MACOS="$APPS_DIR/logo-macos.svg"
DESKTOP_DIR="$APPS_DIR/desktop"

if ! command -v rsvg-convert &> /dev/null && ! command -v convert &> /dev/null; then
    echo "Error: Either rsvg-convert (librsvg) or ImageMagick (convert) is required"
    echo "Install with: brew install librsvg"
    exit 1
fi

convert_svg() {
    local input="$1"
    local output="$2"
    local size="$3"
    
    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert -w "$size" -h "$size" "$input" -o "$output"
    else
        convert -background none -resize "${size}x${size}" "$input" "$output"
    fi
}

echo "Generating macOS icons..."
MACOS_ICONS="$DESKTOP_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$MACOS_ICONS"

# Use macOS-specific SVG with proper padding
for size in 16 32 64 128 256 512 1024; do
    echo "  - ${size}x${size}"
    convert_svg "$SVG_MACOS" "$MACOS_ICONS/app_icon_${size}.png" "$size"
done

echo "Generating Windows icon..."
WINDOWS_ICONS="$DESKTOP_DIR/windows/runner/resources"
mkdir -p "$WINDOWS_ICONS"

# Generate multiple sizes for ICO
TEMP_DIR=$(mktemp -d)
for size in 16 32 48 64 128 256; do
    convert_svg "$SVG_FILE" "$TEMP_DIR/icon_${size}.png" "$size"
done

# Combine into ICO (requires ImageMagick)
if command -v convert &> /dev/null; then
    convert "$TEMP_DIR/icon_16.png" "$TEMP_DIR/icon_32.png" "$TEMP_DIR/icon_48.png" \
            "$TEMP_DIR/icon_64.png" "$TEMP_DIR/icon_128.png" "$TEMP_DIR/icon_256.png" \
            "$WINDOWS_ICONS/app_icon.ico"
    echo "  - app_icon.ico created"
else
    echo "  - Warning: ImageMagick not found, cannot create .ico file"
    cp "$TEMP_DIR/icon_256.png" "$WINDOWS_ICONS/app_icon.png"
fi
rm -rf "$TEMP_DIR"

echo "Generating Linux icons..."
LINUX_ICONS="$DESKTOP_DIR/linux/icons"
mkdir -p "$LINUX_ICONS"

for size in 16 32 48 64 128 256 512; do
    convert_svg "$SVG_FILE" "$LINUX_ICONS/icon_${size}.png" "$size"
    echo "  - ${size}x${size}"
done

echo "Copying SVG to web..."
WEB_PUBLIC="$APPS_DIR/server/web/public"
mkdir -p "$WEB_PUBLIC"
cp "$SVG_FILE" "$WEB_PUBLIC/favicon.svg"
cp "$SVG_FILE" "$WEB_PUBLIC/logo.svg"

echo ""
echo "✓ Icons generated successfully!"
echo ""
echo "Files created:"
echo "  - macOS: $MACOS_ICONS/app_icon_*.png"
echo "  - Windows: $WINDOWS_ICONS/app_icon.ico"
echo "  - Linux: $LINUX_ICONS/icon_*.png"
echo "  - Web: $WEB_PUBLIC/favicon.svg, logo.svg"
