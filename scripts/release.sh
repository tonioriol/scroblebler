#!/bin/bash
set -e

# Single-command automated release
# Just run this - it does everything
# Usage: ./scripts/release.sh

echo ""
echo "🚀 Automated Release"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check Node.js
if ! command -v npx &> /dev/null; then
  echo "❌ Node.js required: brew install node"
  exit 1
fi

# Export GitHub token from gh CLI
export GITHUB_TOKEN=$(gh auth token)

# Run semantic-release (npx auto-installs dependencies)
npx --yes \
  -p semantic-release@24 \
  -p @semantic-release/git \
  -p @semantic-release/changelog \
  -p @semantic-release/exec \
  -p @semantic-release/github \
  semantic-release --no-ci

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Complete! Homebrew tap will auto-sync"
echo ""
