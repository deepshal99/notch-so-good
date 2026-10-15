#!/bin/bash
# Installs Notch So Good hooks for all supported AI coding agents
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Notch So Good hooks..."
echo ""

# Claude Code
if command -v claude &> /dev/null || [ -d "$HOME/.claude" ]; then
    echo "→ Claude Code detected"
    bash "$DIR/install-hooks.sh"
    echo ""
else
    echo "· Claude Code not found (skipping)"
fi

# Codex CLI
if command -v codex &> /dev/null || [ -d "$HOME/.codex" ]; then
    echo "→ Codex CLI detected"
    bash "$DIR/install-codex-hooks.sh"
    echo ""
else
    echo "· Codex CLI not found (skipping)"
fi

# Gemini CLI (watching only)
if command -v gemini &> /dev/null || [ -d "$HOME/.gemini" ]; then
    echo "→ Gemini CLI detected"
    bash "$DIR/install-gemini-hooks.sh"
    echo ""
else
    echo "· Gemini CLI not found (skipping)"
fi

echo "Done! All detected agents are now connected to Notch So Good."
