#!/bin/bash
set -e

# Run as root: initialize firewall and harden the environment
/usr/local/bin/init-firewall.sh

# Persist ~/.claude.json across container restarts by storing it in the volume.
# Claude Code writes onboarding state and user config to ~/.claude.json, which
# lives outside the ~/.claude/ volume mount. We symlink it into the volume so
# the data survives container removal.
CLAUDE_JSON="/home/vscode/.claude.json"
CLAUDE_JSON_VOL="/home/vscode/.claude/.claude.json"
if [ -f "$CLAUDE_JSON_VOL" ] && [ ! -L "$CLAUDE_JSON" ]; then
    # Volume has persisted data from a previous run — replace the image copy with a symlink
    rm -f "$CLAUDE_JSON"
    ln -s "$CLAUDE_JSON_VOL" "$CLAUDE_JSON"
    chown -h vscode:vscode "$CLAUDE_JSON"
elif [ -f "$CLAUDE_JSON" ] && [ ! -L "$CLAUDE_JSON" ]; then
    # First run: move the image-baked file into the volume, then symlink
    mv "$CLAUDE_JSON" "$CLAUDE_JSON_VOL"
    ln -s "$CLAUDE_JSON_VOL" "$CLAUDE_JSON"
    chown vscode:vscode "$CLAUDE_JSON_VOL"
    chown -h vscode:vscode "$CLAUDE_JSON"
fi

# Fix workspace ownership (bind mount may be owned by host UID)
if [ -d /workspaces/project ]; then
    chown vscode:vscode /workspaces/project
fi

# Drop privileges and exec the user command
exec gosu vscode "$@"
