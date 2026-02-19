#!/bin/bash
set -e

CLAUDE_CODE_VERSION="${VERSION:-latest}"

echo "Installing Claude Code ${CLAUDE_CODE_VERSION} for user ${_REMOTE_USER}..."

# Ensure curl is available
if ! command -v curl &> /dev/null; then
    apt-get update
    apt-get install -y --no-install-recommends curl ca-certificates
    rm -rf /var/lib/apt/lists/*
fi

# Install Claude Code for the remote user
if [ "${_REMOTE_USER}" = "root" ]; then
    if [ "${CLAUDE_CODE_VERSION}" = "latest" ]; then
        curl -fsSL https://claude.ai/install.sh | bash
    else
        curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"
    fi
else
    if [ "${CLAUDE_CODE_VERSION}" = "latest" ]; then
        su - "${_REMOTE_USER}" -c "curl -fsSL https://claude.ai/install.sh | bash"
    else
        su - "${_REMOTE_USER}" -c "curl -fsSL https://claude.ai/install.sh | bash -s '${CLAUDE_CODE_VERSION}'"
    fi
fi

# Add to PATH for all users and non-interactive shells
echo "export PATH=\"${_REMOTE_USER_HOME}/.local/bin:\$PATH\"" > /etc/profile.d/claude-code.sh
chmod +x /etc/profile.d/claude-code.sh

echo "Claude Code installed successfully."
