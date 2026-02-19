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

# Install networking tools for the firewall
apt-get update
apt-get install -y --no-install-recommends iptables ipset iproute2 dnsutils
rm -rf /var/lib/apt/lists/*

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
CLAUDE_JSON="${_REMOTE_USER_HOME}/.claude.json"
if [ ! -f "${CLAUDE_JSON}" ]; then
    echo '{"hasCompletedOnboarding":true,"numStartups":1,"installMethod":"native"}' > "${CLAUDE_JSON}"
    chown "${_REMOTE_USER}:${_REMOTE_USER}" "${CLAUDE_JSON}"
fi

# Install firewall script
cp "$(dirname "$0")/init-firewall.sh" /usr/local/bin/init-firewall.sh
chmod +x /usr/local/bin/init-firewall.sh

# Grant the container user passwordless sudo ONLY for the firewall script
echo "${_REMOTE_USER} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/${_REMOTE_USER}-firewall
chmod 0440 /etc/sudoers.d/${_REMOTE_USER}-firewall

echo "Claude Code installed successfully."
