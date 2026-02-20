#!/bin/bash
# VS Code IPC escape prevention — strip variables that enable host command execution.
# Sourced as the first line of .bashrc so it runs for ALL bash invocations,
# catching VS Code's per-process re-injection of these variables.
#
# See: https://blog.demml.com/post/hardening-dev-containers-for-ai-agents/

# Primary IPC escape vectors
unset VSCODE_IPC_HOOK_CLI
unset VSCODE_GIT_IPC_HANDLE
unset REMOTE_CONTAINERS_IPC
unset REMOTE_CONTAINERS_SOCKETS
unset REMOTE_CONTAINERS_DISPLAY_SOCK

# Git credential forwarding (VS Code injects these to proxy git auth through the host)
unset GIT_ASKPASS
unset VSCODE_GIT_ASKPASS_MAIN
unset VSCODE_GIT_ASKPASS_NODE
unset VSCODE_GIT_ASKPASS_EXTRA_ARGS

# Prevent browser-open and display forwarding escapes
export BROWSER=""
export SSH_AUTH_SOCK=""
export GPG_AGENT_INFO=""
export WAYLAND_DISPLAY=""
