#!/bin/bash
set -e

echo "Testing Claude Code installation..."

# Verify claude binary is on PATH
if ! command -v claude &> /dev/null; then
    echo "FAIL: claude not found on PATH"
    exit 1
fi

# Verify it runs and prints a version
CLAUDE_VERSION=$(claude --version 2>&1 || true)
if [ -z "$CLAUDE_VERSION" ]; then
    echo "FAIL: claude --version returned empty output"
    exit 1
fi

echo "PASS: Claude Code ${CLAUDE_VERSION} installed successfully"
