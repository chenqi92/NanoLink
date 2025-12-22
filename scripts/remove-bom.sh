#!/bin/bash
#
# Remove BOM (Byte Order Mark) from text files in the NanoLink project.
# BOM characters can cause build failures in Go, Python, and Docker.
#
# Usage:
#   ./remove-bom.sh          # Scan and fix all files
#   ./remove-bom.sh --dry-run # Only report files with BOM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        *)
            ROOT_DIR="$1"
            shift
            ;;
    esac
done

echo "Scanning for BOM characters in: $ROOT_DIR"

FOUND_COUNT=0
FIXED_COUNT=0

# Function to check if file has BOM
has_bom() {
    local file="$1"
    local first_bytes=$(head -c 3 "$file" | xxd -p)
    [[ "$first_bytes" == "efbbbf" ]]
}

# Function to remove BOM from file
remove_bom() {
    local file="$1"
    if has_bom "$file"; then
        # Create temp file without BOM
        tail -c +4 "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
        return 0
    fi
    return 1
}

# File extensions to check
EXTENSIONS=("go" "py" "rs" "toml" "json" "yaml" "yml" "java" "tsx" "ts" "js")

# Build find pattern
FIND_PATTERN=""
for ext in "${EXTENSIONS[@]}"; do
    if [[ -n "$FIND_PATTERN" ]]; then
        FIND_PATTERN="$FIND_PATTERN -o"
    fi
    FIND_PATTERN="$FIND_PATTERN -name '*.$ext'"
done

# Find and process files
while IFS= read -r -d '' file; do
    # Skip excluded directories
    if [[ "$file" == *"/node_modules/"* ]] || \
       [[ "$file" == *"/.git/"* ]] || \
       [[ "$file" == */target/* ]] || \
       [[ "$file" == */build/* ]] || \
       [[ "$file" == */dist/* ]] || \
       [[ "$file" == */__pycache__/* ]]; then
        continue
    fi
    
    if has_bom "$file"; then
        FOUND_COUNT=$((FOUND_COUNT + 1))
        REL_PATH="${file#$ROOT_DIR/}"
        
        if $DRY_RUN; then
            echo "  [BOM] $REL_PATH"
        else
            if remove_bom "$file"; then
                echo "  [FIXED] $REL_PATH"
                FIXED_COUNT=$((FIXED_COUNT + 1))
            fi
        fi
    fi
done < <(eval "find '$ROOT_DIR' -type f \( $FIND_PATTERN \) -print0" 2>/dev/null)

# Check VERSION file specifically
VERSION_FILE="$ROOT_DIR/VERSION"
if [[ -f "$VERSION_FILE" ]] && has_bom "$VERSION_FILE"; then
    FOUND_COUNT=$((FOUND_COUNT + 1))
    if $DRY_RUN; then
        echo "  [BOM] VERSION"
    else
        if remove_bom "$VERSION_FILE"; then
            echo "  [FIXED] VERSION"
            FIXED_COUNT=$((FIXED_COUNT + 1))
        fi
    fi
fi

echo ""
if $DRY_RUN; then
    echo "Found $FOUND_COUNT file(s) with BOM. Run without --dry-run to fix."
else
    if [[ $FIXED_COUNT -gt 0 ]]; then
        echo "Fixed $FIXED_COUNT file(s)."
    else
        echo "No files with BOM found."
    fi
fi
