FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG VERSION=latest

# Install gosu for clean root→user privilege drop in entrypoint
RUN apt-get update \
    && apt-get install -y --no-install-recommends gosu \
    && rm -rf /var/lib/apt/lists/*

# Copy security scripts (co-located so install.sh's dirname trick works)
COPY src/claude-code/install.sh /tmp/install.sh
COPY src/claude-code/init-firewall.sh /tmp/init-firewall.sh
COPY src/claude-code/harden-env.sh /tmp/harden-env.sh

# Run install.sh with the devcontainer feature contract variables
ENV _REMOTE_USER=vscode
ENV _REMOTE_USER_HOME=/home/vscode
RUN chmod +x /tmp/install.sh /tmp/init-firewall.sh /tmp/harden-env.sh \
    && cd /tmp && VERSION="${VERSION}" bash install.sh \
    && cp "$(readlink -f /home/vscode/.local/bin/claude)" /usr/local/bin/claude \
    && chmod +x /usr/local/bin/claude

# Copy entrypoint
COPY standalone/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Credential-stripping environment variables
ENV GIT_TERMINAL_PROMPT=0
ENV SSH_AUTH_SOCK=""
ENV GIT_ASKPASS=/bin/false
ENV VSCODE_GIT_ASKPASS_MAIN=""
ENV VSCODE_GIT_ASKPASS_NODE=""
ENV VSCODE_GIT_ASKPASS_EXTRA_ARGS=""
ENV GH_TOKEN=""
ENV GITHUB_TOKEN=""
ENV GIT_CONFIG_COUNT=1
ENV GIT_CONFIG_KEY_0=credential.helper
ENV GIT_CONFIG_VALUE_0=/bin/false
ENV BROWSER=""
ENV GPG_AGENT_INFO=""

# Ensure claude is on PATH for all shell types (profile.d only runs for login shells)
ENV PATH="/home/vscode/.local/bin:${PATH}"

WORKDIR /workspaces/project

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude", "--dangerously-skip-permissions"]
