#!/bin/bash
#
# Install Git hooks for NanoLink project
#
# This script installs the pre-commit hook that automatically removes BOM characters.
#
# Usage:
#   ./install-hooks.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$ROOT_DIR/.git/hooks"
HOOKS_SRC="$SCRIPT_DIR/hooks"

echo "Installing Git hooks for NanoLink..."

# Check if we're in a git repository
if [ ! -d "$ROOT_DIR/.git" ]; then
    echo "Error: Not a git repository. Run this script from the NanoLink root directory."
    exit 1
fi

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

# Install pre-commit hook
if [ -f "$HOOKS_SRC/pre-commit" ]; then
    cp "$HOOKS_SRC/pre-commit" "$HOOKS_DIR/pre-commit"
    chmod +x "$HOOKS_DIR/pre-commit"
    echo "✓ Installed pre-commit hook"
else
    echo "Error: pre-commit hook source not found at $HOOKS_SRC/pre-commit"
    exit 1
fi

echo ""
echo "Git hooks installed successfully!"
echo "The pre-commit hook will automatically run BOM removal before each commit."
