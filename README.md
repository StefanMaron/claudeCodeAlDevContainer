# Claude Code Dev Container Feature

A [Dev Container Feature](https://containers.dev/features) that installs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with multi-layered security hardening for running AI coding agents in sandboxed environments.

Designed for use with `--dangerously-skip-permissions` (bypass mode), where the agent can execute arbitrary commands without user confirmation. The security model assumes the agent is untrusted and restricts what damage it can do.

## Quick Start

Create `.devcontainer/devcontainer.json` in your project:

```jsonc
{
    "name": "Claude Code",
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
        "ghcr.io/stefanmaron/claudeCodeAlDevContainer/claude-code:latest": {}
    },
    "runArgs": ["--cap-drop=ALL"],
    "remoteUser": "vscode",
    "mounts": [
        "source=claude-code-config,target=/home/vscode/.claude,type=volume",
        "source=claude-code-data,target=/home/vscode/.local/share/claude,type=volume"
    ],
    "containerEnv": {
        "GIT_TERMINAL_PROMPT": "0",
        "SSH_AUTH_SOCK": "",
        "GIT_ASKPASS": "/bin/false",
        "VSCODE_GIT_ASKPASS_MAIN": "",
        "VSCODE_GIT_ASKPASS_NODE": "",
        "VSCODE_GIT_ASKPASS_EXTRA_ARGS": "",
        "GH_TOKEN": "",
        "GITHUB_TOKEN": "",
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "credential.helper",
        "GIT_CONFIG_VALUE_0": "/bin/false"
    },
    "remoteEnv": {
        "VSCODE_IPC_HOOK_CLI": null,
        "VSCODE_GIT_IPC_HANDLE": null,
        "REMOTE_CONTAINERS_IPC": null,
        "REMOTE_CONTAINERS_SOCKETS": null,
        "REMOTE_CONTAINERS_DISPLAY_SOCK": null,
        "GPG_AGENT_INFO": "",
        "BROWSER": "",
        "WAYLAND_DISPLAY": ""
    },
    "customizations": {
        "vscode": {
            "settings": {
                "github.gitAuthentication": false,
                "git.terminalAuthentication": false
            }
        }
    },
    "postCreateCommand": "echo '{\"hasCompletedOnboarding\":true,\"numStartups\":1,\"installMethod\":\"native\"}' > ~/.claude.json",
    "postStartCommand": "sudo /usr/local/bin/init-firewall.sh",
    "waitFor": "postStartCommand"
}
```

Open in VS Code with the Dev Containers extension, or use the [devcontainer CLI](https://github.com/devcontainers/cli):

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . claude --dangerously-skip-permissions
```

## Security Model

### The Problem

VS Code Dev Containers are not a security boundary. By Microsoft's own design, the VS Code server running inside the container is in the same trust boundary as the VS Code client on the host. Specifically:

1. **IPC Socket Escape**: VS Code injects Unix sockets (`/tmp/vscode-ipc-*.sock`) and environment variables (`VSCODE_IPC_HOOK_CLI`) into the container. Any process can use these to execute arbitrary commands on the host via VS Code's `TerminalService` API.

2. **Credential Forwarding**: VS Code forwards Git credentials, SSH agents, and GPG keys into the container, giving the agent access to your identity.

3. **devcontainer.json Manipulation**: An agent can modify `.devcontainer/devcontainer.json` to add host filesystem mounts or `initializeCommand` entries that execute on the host at next rebuild.

4. **Network Exfiltration**: By default, containers have full outbound network access. An agent can exfiltrate code, secrets, or data to any endpoint.

This Feature applies defense-in-depth mitigations across all four vectors.

### Layer 1: Network Firewall

An iptables-based allowlist firewall configured at container start:

- **Default-deny outbound**: All traffic blocked except explicitly allowed domains
- **Allowlist**: Only Anthropic API (`api.anthropic.com`, `claude.ai`, `console.anthropic.com`, `statsig.anthropic.com`) and VS Code marketplace infrastructure
- **IPv6 disabled**: Prevents bypass through IPv6 stack
- **DNS restricted**: Only Docker's internal resolver (`127.0.0.11`) is allowed, blocking DNS tunneling
- **Host gateway**: Only the Docker host gateway IP is permitted (not the entire subnet)
- **Git push blocked**: System-level `pre-push` hook rejects all pushes

### Layer 2: Credential Stripping

Prevents the agent from using your identity:

- `containerEnv` clears `SSH_AUTH_SOCK`, `GIT_ASKPASS`, `GH_TOKEN`, `GITHUB_TOKEN`, and VS Code's git askpass helpers at the container level
- `GIT_CONFIG_VALUE_0` sets `credential.helper` to `/bin/false`
- VS Code settings disable `github.gitAuthentication` and `git.terminalAuthentication`
- Named volumes persist Claude's own auth across rebuilds without exposing host credentials

### Layer 3: VS Code IPC Escape Prevention

Multiple overlapping mitigations for the IPC socket escape vector:

| Mitigation | What It Does | Coverage |
|---|---|---|
| `remoteEnv` (null) | Tells VS Code not to set `VSCODE_IPC_HOOK_CLI` and related variables | VS Code-spawned processes |
| `harden-env.sh` in `.bashrc` | Unsets IPC variables at shell startup, before the interactive guard | All bash sessions including non-interactive |
| Socket cleanup (immediate) | Deletes `/tmp/vscode-*.sock` files at firewall init | Sockets created before `postStartCommand` |
| Socket cleanup (daemon) | Background process deletes sockets every 30s for ~5 minutes | Late-created sockets (VS Code creates some 60s+ after attach) |
| `devcontainer.json` immutable | `chattr +i` prevents modification of devcontainer config files | Blocks host mount injection and malicious `initializeCommand` |

### Layer 4: Privilege Reduction

- `--cap-drop=ALL` in `runArgs` drops all Linux capabilities (the Feature adds back only `NET_ADMIN` + `NET_RAW` for firewall setup)
- SUID/SGID bits stripped from all binaries except `sudo`
- Sudo access limited to a single command (`init-firewall.sh`), then the user is removed from the sudo group entirely
- Firewall script, hardening script, and devcontainer.json are made immutable with `chattr +i`

## Usage Modes

| Mode | IPC Escape Risk | Setup Complexity | IDE Experience |
|---|---|---|---|
| VS Code Desktop | Best-effort mitigations (small race window) | Lowest | Full VS Code |
| Browser (code-server) | None — no host IPC bridge | Medium | VS Code in browser |
| Headless CLI | None — no IDE at all | Medium | Terminal only |
| Plain Docker | None — no devcontainer tooling | Highest | Bring your own |

### VS Code Desktop (Convenience)

The standard Dev Containers workflow: open the folder in VS Code, click "Reopen in Container."

**Trade-off**: VS Code's remote architecture injects IPC sockets and environment variables into the container by design. The mitigations above are best-effort — there is a small race window between socket creation and cleanup, and VS Code may re-inject environment variables in ways that bypass the shell hardening.

This mode is suitable for working on code you broadly trust, with the firewall preventing network exfiltration as the primary security boundary.

### Browser-Based (Full Isolation)

Run a VS Code-compatible editor inside the container and connect via browser. No VS Code desktop client means no IPC socket bridge to the host — the container is genuinely isolated.

**With the devcontainer CLI:**

```jsonc
// .devcontainer/devcontainer.json — add to the Quick Start config:
{
    // ... existing config ...
    "forwardPorts": [8080],
    "postCreateCommand": "curl -fsSL https://code-server.dev/install.sh | sh && echo '{\"hasCompletedOnboarding\":true,\"numStartups\":1,\"installMethod\":\"native\"}' > ~/.claude.json"
}
```

```bash
devcontainer up --workspace-folder .
# Open http://localhost:8080 in your browser
```

**With plain Docker (no devcontainer CLI needed):**

```bash
# Build the container image with the Feature pre-applied
devcontainer build --workspace-folder . --image-name claude-sandbox

# Or if you don't want devcontainer CLI at all, build from a Dockerfile:
docker run -it --name claude-sandbox \
    --cap-drop=ALL --cap-add=NET_ADMIN --cap-add=NET_RAW \
    -p 8080:8080 \
    -v claude-code-config:/home/vscode/.claude \
    -v claude-code-data:/home/vscode/.local/share/claude \
    -v "$(pwd):/workspaces/project" \
    -e GIT_TERMINAL_PROMPT=0 \
    -e SSH_AUTH_SOCK= \
    -e GIT_ASKPASS=/bin/false \
    -e GH_TOKEN= \
    -e GITHUB_TOKEN= \
    mcr.microsoft.com/devcontainers/base:ubuntu-24.04 \
    bash
```

Note: When using plain `docker run`, the Feature's install script doesn't run automatically. You would need to either:
1. Use `devcontainer build` first to bake the Feature into an image, then `docker run` that image
2. Or install Claude Code and the firewall manually inside the container

Option 1 is recommended — it gives you a plain Docker image with all hardening pre-applied:

```bash
# One-time: build the image using devcontainer CLI
devcontainer build --workspace-folder . --image-name claude-sandbox

# Then use plain Docker from here on — no devcontainer CLI needed
docker run -it --rm \
    --cap-drop=ALL --cap-add=NET_ADMIN --cap-add=NET_RAW \
    -v claude-code-config:/home/vscode/.claude \
    -v claude-code-data:/home/vscode/.local/share/claude \
    -v "$(pwd):/workspaces/project" \
    -e GIT_TERMINAL_PROMPT=0 \
    -e SSH_AUTH_SOCK= \
    -e GIT_ASKPASS=/bin/false \
    -e GH_TOKEN= \
    -e GITHUB_TOKEN= \
    -u vscode \
    claude-sandbox \
    bash -c "sudo /usr/local/bin/init-firewall.sh && code-server --bind-addr 0.0.0.0:8080 /workspaces/project"

# Open http://localhost:8080
```

### Headless CLI (No IDE)

Run Claude Code directly without any IDE:

```bash
# With devcontainer CLI
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . claude --dangerously-skip-permissions -p "Fix the bug in auth.ts"

# With plain Docker (using pre-built image from above)
docker run -it --rm \
    --cap-drop=ALL --cap-add=NET_ADMIN --cap-add=NET_RAW \
    -v claude-code-config:/home/vscode/.claude \
    -v claude-code-data:/home/vscode/.local/share/claude \
    -v "$(pwd):/workspaces/project" \
    -e GIT_TERMINAL_PROMPT=0 \
    -e SSH_AUTH_SOCK= \
    -e GIT_ASKPASS=/bin/false \
    -e GH_TOKEN= \
    -e GITHUB_TOKEN= \
    -u vscode \
    claude-sandbox \
    bash -c "sudo /usr/local/bin/init-firewall.sh && claude --dangerously-skip-permissions -p 'Fix the bug in auth.ts'"
```

No IPC sockets exist in either approach. Combined with the network firewall, this provides strong isolation.

## Known Limitations

- **IPC race window (VS Code Desktop)**: There is a brief window between VS Code creating IPC sockets and the cleanup daemon deleting them. An agent that acts in this window could potentially use a socket before it is removed.

- **`chattr` on overlay filesystems**: The `chattr +i` immutability flag may not work on Docker's default overlay2 filesystem. The scripts log warnings when this fails. The security value is defense-in-depth; the firewall is the primary boundary.

- **DNS is point-in-time**: Domain allowlist IPs are resolved once at container start. If a service's IP changes during a long session, connections may break. Restart the container to re-resolve.

- **VS Code may change behavior**: Microsoft could change how IPC sockets or environment variables work in future VS Code versions, potentially bypassing current mitigations. The layered approach reduces the impact of any single mitigation being defeated.

- **`remoteEnv` null behavior**: Setting variables to `null` in `remoteEnv` tells VS Code not to set them, but this depends on VS Code respecting the directive. It is not equivalent to `unset` at the OS level (which `harden-env.sh` provides).

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `version` | string | `latest` | Claude Code version to install (`latest`, `stable`, or specific like `1.0.58`) |

## Credits

Thanks to [Janrik Ö.](https://www.linkedin.com/feed/update/urn:li:activity:7430243862134112256?commentUrn=urn%3Ali%3Acomment%3A%28activity%3A7430243862134112256%2C7430483952223715329%29) for flagging the VS Code container escape issue — without his heads-up this would likely have gone unaddressed.

The IPC escape mitigations are based on research and techniques from:

- [Daniel Demmel](https://blog.demml.com/post/hardening-dev-containers-for-ai-agents/) — Comprehensive hardening guide for dev containers running AI agents
- [The Red Guild](https://blog.theredguild.org/escaping-satisfying-vscode-containers/) — Technical breakdown of VS Code container escape mechanisms
- [Anthropic](https://docs.anthropic.com/en/docs/claude-code/bedrock-vertex#docker-dev-container-setup) — Official Claude Code devcontainer reference

## License

MIT
