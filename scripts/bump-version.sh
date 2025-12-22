#!/bin/bash

# NanoLink Version Bump Script
# Usage: ./bump-version.sh <new_version>
# Example: ./bump-version.sh 0.2.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print with color
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Validate version format (semver)
validate_version() {
    if [[ ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$ ]]; then
        error "Invalid version format: $1. Expected semver format (e.g., 1.2.3, 1.2.3-beta.1)"
    fi
}

# Get current version from version.json
get_current_version() {
    if command -v jq &> /dev/null; then
        jq -r '.version' "$SCRIPT_DIR/version.json"
    else
        grep -o '"version": "[^"]*"' "$SCRIPT_DIR/version.json" | head -1 | cut -d'"' -f4
    fi
}

# Update version in a file using sed
update_file() {
    local file="$1"
    local old_version="$2"
    local new_version="$3"
    local full_path="$ROOT_DIR/$file"

    if [[ ! -f "$full_path" ]]; then
        warn "File not found: $file"
        return
    fi

    # Create backup
    cp "$full_path" "$full_path.bak"

    # Replace version (escape dots for regex)
    local old_escaped=$(echo "$old_version" | sed 's/\./\\./g')

    if sed -i.tmp "s/$old_escaped/$new_version/g" "$full_path"; then
        rm -f "$full_path.tmp"
        rm -f "$full_path.bak"
        success "Updated: $file"
    else
        mv "$full_path.bak" "$full_path"
        warn "Failed to update: $file"
    fi
}

# Main
main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <new_version>"
        echo ""
        echo "Examples:"
        echo "  $0 0.2.0"
        echo "  $0 1.0.0-beta.1"
        echo ""
        CURRENT=$(get_current_version)
        echo "Current version: $CURRENT"
        exit 1
    fi

    NEW_VERSION="$1"
    validate_version "$NEW_VERSION"

    CURRENT_VERSION=$(get_current_version)

    echo ""
    echo "=========================================="
    echo "  NanoLink Version Bump"
    echo "=========================================="
    echo ""
    info "Current version: $CURRENT_VERSION"
    info "New version:     $NEW_VERSION"
    echo ""

    # Confirm
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Aborted."
        exit 0
    fi

    echo ""
    info "Updating version in all files..."
    echo ""

    # Update each file
    update_file "agent/Cargo.toml" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "agent/src/main.rs" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "sdk/java/pom.xml" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "sdk/go/nanolink/version.go" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "sdk/python/pyproject.toml" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "sdk/python/nanolink/__init__.py" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "dashboard/package.json" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "apps/server/cmd/main.go" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "apps/server/web/package.json" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "apps/desktop/pubspec.yaml" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "demo/spring-boot/pom.xml" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "scripts/version.json" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "agent/scripts/install.sh" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "agent/scripts/install.ps1" "$CURRENT_VERSION" "$NEW_VERSION"
    
    # Update README files (Chinese and English)
    update_file "README.md" "$CURRENT_VERSION" "$NEW_VERSION"
    update_file "README_CN.md" "$CURRENT_VERSION" "$NEW_VERSION"
    
    # Update root VERSION file (triggers auto-release)
    echo "$NEW_VERSION" > "$ROOT_DIR/VERSION"
    success "Updated: VERSION"

    echo ""
    success "Version bumped from $CURRENT_VERSION to $NEW_VERSION"
    echo ""
    info "Next steps:"
    echo "  1. Review changes: git diff"
    echo "  2. Commit: git commit -am \"chore: bump version to $NEW_VERSION\""
    echo "  3. Tag: git tag v$NEW_VERSION"
    echo "  4. Push: git push && git push --tags"
    echo ""
}

main "$@"
