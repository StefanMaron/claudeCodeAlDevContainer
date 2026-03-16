#!/bin/bash
set -e

# Run as root: initialize firewall and harden the environment
/usr/local/bin/init-firewall.sh

# Persist ~/.claude.json in the host config folder. Claude Code writes onboarding
# state and user config to ~/.claude.json, which lives outside ~/.claude/. We
# symlink it into the mounted folder so it survives container removal.
CLAUDE_JSON="/home/vscode/.claude.json"
CLAUDE_JSON_HOST="/home/vscode/.claude/.claude.json"
if [ -f "$CLAUDE_JSON_HOST" ] && [ ! -L "$CLAUDE_JSON" ]; then
    # Host folder has persisted data from a previous run — symlink to it
    rm -f "$CLAUDE_JSON"
    ln -s "$CLAUDE_JSON_HOST" "$CLAUDE_JSON"
    chown -h vscode:vscode "$CLAUDE_JSON"
elif [ -f "$CLAUDE_JSON" ] && [ ! -L "$CLAUDE_JSON" ]; then
    # First run: move the image-baked file into the host folder, then symlink
    mv "$CLAUDE_JSON" "$CLAUDE_JSON_HOST"
    ln -s "$CLAUDE_JSON_HOST" "$CLAUDE_JSON"
    chown vscode:vscode "$CLAUDE_JSON_HOST"
    chown -h vscode:vscode "$CLAUDE_JSON"
fi

# Fix workspace ownership (bind mount may be owned by host UID)
if [ -d /workspaces/project ]; then
    chown vscode:vscode /workspaces/project
fi

# Drop privileges and exec the user command
exec gosu vscode "$@"
