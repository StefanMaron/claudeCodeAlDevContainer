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

# Pre-seed ~/.claude.json to skip onboarding wizard
# Claude Code checks hasCompletedOnboarding to decide whether to show the first-run flow.
# Without this, every new container triggers full onboarding even if credentials exist.
CLAUDE_JSON="${_REMOTE_USER_HOME}/.claude.json"
if [ ! -f "${CLAUDE_JSON}" ]; then
    echo '{"hasCompletedOnboarding":true,"numStartups":1,"installMethod":"native"}' > "${CLAUDE_JSON}"
    chown "${_REMOTE_USER}:${_REMOTE_USER}" "${CLAUDE_JSON}"
fi

echo "Claude Code installed successfully."
