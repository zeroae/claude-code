#!/bin/bash
#
# verify-source.sh - Verifies Claude Code GCS bucket URL in Dockerfile
#
# Purpose:
#   Compares the GCS_BUCKET URL in the Dockerfile against the authoritative
#   source at https://claude.ai/install.sh. Ensures container builds use
#   the current Claude Code distribution endpoint.
#
# Usage:
#   ./verify-source.sh          # Verification only
#   ./verify-source.sh --update # Auto-update Dockerfile if URLs differ
#
# Exit codes:
#   0 - URLs match (Dockerfile is current)
#   1 - URLs differ or verification failed
#
# Dependencies: curl, grep, cut, sed (all standard on Linux/macOS)

set -euo pipefail

# ANSI color codes for terminal output
# These improve readability by color-coding success (green), warnings (yellow), and errors (red)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color (reset)

echo "=== Claude Code Source Verification ==="
echo ""

# Fetch official install script from Claude.ai
echo "📥 Fetching official install script..."
if ! INSTALL_SCRIPT=$(curl -fsSL https://claude.ai/install.sh 2>&1); then
    echo -e "${RED}❌ Failed to fetch install script${NC}"
    echo ""
    echo "Possible causes:"
    echo "  - No internet connection"
    echo "  - claude.ai is unreachable"
    echo "  - curl is not installed"
    echo ""
    echo "Try:"
    echo "  curl https://claude.ai/install.sh"
    exit 1
fi

# Extract GCS_BUCKET variable from install script
# The official script defines: GCS_BUCKET="https://storage.googleapis.com/..."
echo "🔍 Extracting GCS bucket URL..."
OFFICIAL_BUCKET=$(echo "$INSTALL_SCRIPT" | grep '^GCS_BUCKET=' | head -1 | cut -d'"' -f2)

if [ -z "$OFFICIAL_BUCKET" ]; then
    echo -e "${RED}❌ Failed to extract GCS_BUCKET from install script${NC}"
    echo ""
    echo "The install script format may have changed."
    echo "Manually verify the GCS bucket URL at:"
    echo "  https://claude.ai/install.sh"
    exit 1
fi

echo "   Official URL: $OFFICIAL_BUCKET"
echo ""

# Verify the official bucket is accessible and returns a valid version
echo "🌐 Verifying bucket accessibility..."
if ! VERSION=$(curl -fsSL "${OFFICIAL_BUCKET}/latest" 2>&1); then
    echo -e "${RED}❌ Failed to fetch version from bucket${NC}"
    echo ""
    echo "Bucket URL: $OFFICIAL_BUCKET"
    echo ""
    echo "Possible causes:"
    echo "  - Bucket URL format changed"
    echo "  - Google Cloud Storage is unreachable"
    echo "  - The URL was incorrectly extracted"
    echo ""
    echo "Try manually accessing:"
    echo "  curl ${OFFICIAL_BUCKET}/latest"
    exit 1
fi

# Validate version format (should be semantic version like "2.1.17")
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo -e "${YELLOW}⚠️  Unexpected version format: $VERSION${NC}"
    echo "Expected format: X.Y.Z (e.g., 2.1.17)"
fi

echo -e "${GREEN}✅ Bucket is accessible${NC}"
echo "   Latest version: $VERSION"
echo ""

# Check for Dockerfile in current directory
echo "📄 Checking Dockerfile..."
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}❌ Dockerfile not found in current directory${NC}"
    echo ""
    echo "Run this script from the project root:"
    echo "  cd /path/to/claude-code"
    echo "  .claude/skills/update-claude-source/scripts/verify-source.sh"
    exit 1
fi

# Extract GCS_BUCKET from Dockerfile
DOCKERFILE_BUCKET=$(grep 'GCS_BUCKET=' Dockerfile | head -1 | cut -d'"' -f2)

if [ -z "$DOCKERFILE_BUCKET" ]; then
    echo -e "${RED}❌ Failed to find GCS_BUCKET in Dockerfile${NC}"
    echo ""
    echo "The Dockerfile may not contain a GCS_BUCKET variable."
    echo "Expected format:"
    echo '  GCS_BUCKET="https://storage.googleapis.com/..."'
    exit 1
fi

echo "   Dockerfile URL: $DOCKERFILE_BUCKET"
echo ""

# Compare URLs
if [ "$OFFICIAL_BUCKET" = "$DOCKERFILE_BUCKET" ]; then
    echo -e "${GREEN}✅ Dockerfile is up to date${NC}"
    echo ""
    echo "Summary:"
    echo "  Current version: $VERSION"
    echo "  Bucket URL: $OFFICIAL_BUCKET"
    exit 0
else
    echo -e "${YELLOW}⚠️  Dockerfile URL differs from official install script${NC}"
    echo ""
    echo "Official: $OFFICIAL_BUCKET"
    echo "Dockerfile: $DOCKERFILE_BUCKET"
    echo ""

    # Auto-update if --update flag provided
    if [ "${UPDATE:-}" = "true" ] || [ "${1:-}" = "--update" ]; then
        echo "🔧 Updating Dockerfile..."

        # Using | as sed delimiter to avoid conflicts with / in URLs
        # The -i.tmp creates a temp file for compatibility across macOS and Linux
        if ! sed -i.tmp "s|GCS_BUCKET=\"[^\"]*\"|GCS_BUCKET=\"$OFFICIAL_BUCKET\"|" Dockerfile; then
            echo -e "${RED}❌ Failed to update Dockerfile${NC}"
            echo ""
            echo "Manual update required:"
            echo "  1. Edit Dockerfile"
            echo "  2. Find the GCS_BUCKET line (around line 11)"
            echo "  3. Replace the URL with: $OFFICIAL_BUCKET"
            rm -f Dockerfile.tmp
            exit 1
        fi

        # Clean up sed's temporary file
        rm -f Dockerfile.tmp

        echo -e "${GREEN}✅ Dockerfile updated${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Review changes:    git diff Dockerfile"
        echo "  2. Test build:        docker compose build --no-cache"
        echo "  3. Verify version:    docker compose run --rm claude --version"
        echo "  4. Commit:            git add Dockerfile && git commit -m 'Update Claude Code GCS bucket URL'"
    else
        echo "To update automatically, run:"
        echo "  $0 --update"
        echo ""
        echo "Or manually update the GCS_BUCKET line in Dockerfile (around line 11) to:"
        echo "  GCS_BUCKET=\"$OFFICIAL_BUCKET\""
        exit 1
    fi
fi
